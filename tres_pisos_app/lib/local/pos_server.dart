import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'pos_engine.dart';

class LanCipher {
  final SecretKey key;
  LanCipher(String secret) : key = SecretKey(base64Url.decode(secret));
  Future<Json> seal(Json v) async {
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(v)),
      secretKey: key,
    );
    return {
      'nonce': base64Encode(box.nonce),
      'data': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  Future<Json> open(Json v) async {
    final bytes = await AesGcm.with256bits().decrypt(
      SecretBox(
        base64Decode(v['data']),
        nonce: base64Decode(v['nonce']),
        mac: Mac(base64Decode(v['mac'])),
      ),
      secretKey: key,
    );
    return jsonDecode(utf8.decode(bytes)) as Json;
  }
}

class PosServer {
  final PosEngine engine;
  final bool central;
  final String pairSecret, hubId;
  final Uri? hub;
  final String uiSecret = randomKey();
  final Future<List<int>> Function(String path) asset;
  HttpServer? localServer, lanServer;
  Timer? timer;
  bool connected = false, syncing = false, closed = false;
  final Map<String, List<DateTime>> loginAttempts = {};
  final Map<String, DateTime> challenges = {};
  int activeRequests = 0;
  final HttpClient http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3);
  PosServer({
    required this.engine,
    required this.central,
    required this.pairSecret,
    required this.hubId,
    required this.asset,
    this.hub,
  });
  Future<void> start({int uiPort = 8788, int lanPort = 8787}) async {
    localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, uiPort);
    localServer!.listen((r) => handle(r, false));
    if (central) {
      lanServer = await HttpServer.bind(InternetAddress.anyIPv4, lanPort);
      lanServer!.listen((r) => handle(r, true));
    }
    connected = central;
    timer = Timer.periodic(const Duration(seconds: 4), (_) => sync());
  }

  Future<void> stop() async {
    closed = true;
    timer?.cancel();
    http.close(force: true);
    await localServer?.close(force: true);
    await lanServer?.close(force: true);
  }

  Future<Json> parseBody(HttpRequest r) async {
    final data = <int>[];
    final elapsed = Stopwatch()..start();
    await for (final p in r.timeout(const Duration(seconds: 8))) {
      if (elapsed.elapsed > const Duration(seconds: 8)) { throw PosError(408, 'La solicitud tardó demasiado'); }
      data.addAll(p);
      if (data.length > 2 * 1024 * 1024) {
        throw PosError(413, 'La solicitud es demasiado grande');
      }
    }
    if (data.isEmpty) {
      return {};
    }
    try {
      return jsonDecode(utf8.decode(data)) as Json;
    } catch (_) {
      throw PosError(400, 'Solicitud inválida');
    }
  }

  Future<void> jsonResponse(HttpRequest r, int status, Json data) async {
    try {
      r.response.statusCode = status;
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(data));
      await r.response.close();
    } on IOException {
      // A disconnected peer must not terminate the central's isolate.
    }
  }

  void throttle(String client, {int limit = 10}) {
    final now = DateTime.now();
    final attempts = loginAttempts.putIfAbsent(client, () => []);
    attempts.removeWhere((t) => now.difference(t) > const Duration(minutes: 5));
    if (attempts.length >= limit) {
      throw PosError(429, 'Demasiados intentos. Espera cinco minutos');
    }
    attempts.add(now);
    if (loginAttempts.length > 1000) {
      loginAttempts.remove(loginAttempts.keys.first);
    }
  }

  void throttleLogin(Json body, String address) {
    throttle('address:$address', limit: 60);
    final name = (body['username'] ?? '').toString().trim().toLowerCase();
    throttle('account:${name.length > 100 ? 'invalid' : name}');
  }

  Future<void> forgetSession(String token, {bool revoke = false}) async {
    await engine.db.transaction((tx) async {
      if (revoke) {
        await tx.insert('revocations', {'token': token}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await tx.delete('settings', where: 'key IN (?,?)',
          whereArgs: ['session-user:$token', 'session-expiry:$token']);
      await tx.delete('cache', where: 'substr(key,1,?)=?',
          whereArgs: ['$hubId|$token|'.length, '$hubId|$token|']);
    });
  }

  Future<int> localUser(String? token) async {
    final id = await engine.setting('session-user:$token');
    final expiry = DateTime.tryParse(await engine.setting('session-expiry:$token') ?? '');
    if (token == null || id == null || expiry == null || !expiry.isAfter(engine.clock().toUtc())) {
      if (token != null) { await forgetSession(token); }
      throw PosError(401, 'Inicia sesión de nuevo en la central');
    }
    return int.parse(id);
  }

  Future<void> handle(HttpRequest req, bool lan) async {
    req.response.headers.set('X-Content-Type-Options', 'nosniff');
    req.response.headers.set('Cache-Control', 'no-store');
    req.response.headers.set('Referrer-Policy', 'no-referrer');
    activeRequests++;
    try {
      if (activeRequests > 32) { throw PosError(503, 'Central ocupada; vuelve a intentar'); }
      if (lan) {
        if (!['/link/rpc', '/link/challenge'].contains(req.uri.path) || req.method != 'POST') {
          throw PosError(404, 'Ruta no encontrada');
        }
        if (req.headers.contentType?.mimeType != 'application/json') { throw PosError(415, 'Se requiere JSON'); }
        final address = req.connectionInfo?.remoteAddress.address ?? 'unknown';
        throttle('lan:$address', limit: 2400);
        final cipher = LanCipher(pairSecret);
        Json call;
        try {
          call = await cipher.open(await parseBody(req));
        } catch (_) {
          throw PosError(403, 'Enlace no autorizado');
        }
        Json response;
        try {
          if (call['hub_id'] != hubId) {
            throw PosError(409, 'Esta no es la central vinculada');
          }
          if (call['request_id'] is! String || (call['request_id'] as String).length != 44) {
            throw PosError(400, 'Identificador de enlace inválido');
          }
          final now = DateTime.now();
          challenges.removeWhere((_, expiry) => !expiry.isAfter(now));
          if (req.uri.path == '/link/challenge') {
            if (challenges.length >= 256) { throw PosError(429, 'Demasiados enlaces pendientes'); }
            final challenge = randomKey();
            challenges[challenge] = now.add(const Duration(seconds: 20));
            await jsonResponse(req, 200, await cipher.seal({
              'status': 200, 'request_id': call['request_id'],
              'body': {'challenge': challenge, 'protocol': 2},
            }));
            return;
          }
          // Consume before awaiting execution; restarting also invalidates challenges.
          if (challenges.remove(call['challenge']) == null) {
            throw PosError(409, 'Enlace vencido o repetido. Actualiza las tres tablets y vuelve a intentar');
          }
          if (call['path'] is! String || call['method'] is! String || call['body'] is! Map ||
              (call['token'] != null && call['token'] is! String) ||
              (call['operation_id'] != null && call['operation_id'] is! String)) {
            throw PosError(400, 'Operación inválida');
          }
          if (Uri.parse(call['path']).path == '/api/local/backup') {
            throw PosError(403, 'Guarda el respaldo desde la tablet central');
          }
          if (Uri.parse(call['path']).path == '/api/auth/login') { throttleLogin(Json.from(call['body']), address); }
          response = {
            'status': 200,
            'body': await execute(call),
            'request_id': call['request_id'],
          };
        } on PosError catch (e) {
          response = {
            'status': e.status,
            'body': {'error': e.message},
            'request_id': call['request_id'],
          };
        }
        await jsonResponse(req, 200, await cipher.seal(response));
        return;
      }
      if (req.headers.value('host') != '127.0.0.1:${localServer!.port}') { throw PosError(403, 'Servidor local inválido'); }
      final origin = req.headers.value('origin');
      if (origin != null && origin != 'http://127.0.0.1:${localServer!.port}') {
        throw PosError(403, 'Origen no autorizado');
      }
      final nativeEntry = req.uri.path == '/' && req.method == 'GET' && req.headers.value('x-pos-ui-key') == uiSecret;
      if (nativeEntry) {
        req.response.headers.add('Set-Cookie', 'pos_ui=$uiSecret; Path=/; HttpOnly; SameSite=Strict');
      } else if (!req.cookies.any((c) => c.name == 'pos_ui' && c.value == uiSecret)) {
        throw PosError(403, 'Abre el sistema desde la aplicación');
      }
      if (req.uri.path.startsWith('/api/')) {
        final token = req.headers
            .value('authorization')
            ?.replaceFirst('Bearer ', '');
        if (req.uri.path == '/api/local/status' && req.method == 'GET') {
          final userId = central || token == null ? null : await localUser(token);
          final rows = userId == null
              ? <Map<String, Object?>>[]
              : await engine.db.query(
                  'outbox',
                  columns: ['id', 'status', 'error', 'created', 'body'],
                  where: 'user_id=?',
                  whereArgs: [userId],
                  orderBy: 'created ASC',
                );
          await jsonResponse(req, 200, {
            'central': central,
            'connected': connected,
            'pending': rows
                .map(
                  (r) => {
                    'id': r['id'],
                    'status': r['status'],
                    'error': r['error'],
                    'created': r['created'],
                    'body': jsonDecode(r['body'] as String),
                  },
                )
                .toList(),
          });
          return;
        }
        if (req.method != 'GET' && req.headers.contentType?.mimeType != 'application/json') { throw PosError(415, 'Se requiere JSON'); }
        final body = await parseBody(req);
        if (req.uri.path == '/api/local/retry' &&
            req.method == 'POST' &&
            !central) {
          await localUser(token);
          final identity = await remote({
            'method': 'GET',
            'path': '/api/auth/me',
            'token': token,
            'body': {},
          });
          await engine.db.update(
            'outbox',
            {'status': 'pending', 'error': null, 'token': token},
            where: 'id=? AND user_id=?',
            whereArgs: [body['id'], identity['user']['id']],
          );
          await sync();
          await jsonResponse(req, 200, {'success': true});
          return;
        }
        if (req.uri.path == '/api/auth/login') {
          throttleLogin(body, 'local');
        }
        final result = await request(
          req.method,
          req.uri.toString(),
          body,
          token,
          req.headers.value('x-operation-id'),
        );
        await jsonResponse(req, result['queued'] == true ? 202 : 200, result);
      } else {
        final path = req.uri.path == '/'
            ? 'index.html'
            : req.uri.path.substring(1);
        if (path.contains('..') || path.contains('\\')) {
          throw PosError(404, 'Archivo no encontrado');
        }
        final bytes = await asset(path);
        const mime = {
          'html': 'text/html; charset=utf-8',
          'js': 'application/javascript; charset=utf-8',
          'css': 'text/css; charset=utf-8',
          'jpg': 'image/jpeg',
          'png': 'image/png',
          'woff2': 'font/woff2',
          'ttf': 'font/ttf',
        };
        req.response.headers.set(
          'Content-Type',
          mime[path.split('.').last] ?? 'application/octet-stream',
        );
        req.response.headers.set(
          'Content-Security-Policy',
          "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-src 'none'; object-src 'none'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
        );
        req.response.add(bytes);
        await req.response.close();
      }
    } on PosError catch (e) {
      await jsonResponse(req, e.status, {'error': e.message});
    } catch (_) {
      await jsonResponse(req, 500, {
        'error': 'No se pudo completar la operación. Los datos guardados se conservan.',
      });
    } finally {
      activeRequests--;
    }
  }

  Future<Json> execute(Json call) async {
    if (call['path'] == '/api/local/ping') {
      return {'hub_id': hubId};
    }
    return engine.call(
      call['method'],
      Uri.parse(call['path']),
      body: Json.from(call['body'] ?? {}),
      token: call['token'],
      operationId: call['operation_id'],
    );
  }

  Future<Json> remote(Json call) async {
    final challenge = await exchange('/link/challenge', {});
    if (challenge['protocol'] != 2 || challenge['challenge'] is! String) {
      throw PosError(409, 'Actualiza la app en las tres tablets');
    }
    return exchange('/link/rpc', {...call, 'challenge': challenge['challenge']});
  }

  Future<Json> exchange(String path, Json call) async {
    final cipher = LanCipher(pairSecret);
    final nonce = randomKey();
    final req = await http
        .postUrl(hub!.resolve(path))
        .timeout(const Duration(seconds: 4));
    req.headers.contentType = ContentType.json;
    req.followRedirects = false;
    req.write(
      jsonEncode(
        await cipher.seal({...call, 'hub_id': hubId, 'request_id': nonce}),
      ),
    );
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode == 403) {
      throw PosError(403, 'El código de enlace no coincide con la central');
    }
    if (res.statusCode != 200) { throw PosError(res.statusCode, 'No se pudo validar el enlace con cocina'); }
    final bytes = <int>[];
    await (() async {
      await for (final chunk in res) {
        bytes.addAll(chunk);
        if (bytes.length > 16 * 1024 * 1024) { throw PosError(413, 'Respuesta demasiado grande'); }
      }
    })().timeout(const Duration(seconds: 8));
    final raw = utf8.decode(bytes);
    final result = await cipher.open(jsonDecode(raw) as Json);
    if (result['request_id'] != nonce) {
      throw PosError(409, 'Respuesta de enlace inválida');
    }
    connected = true;
    if ((result['status'] as int) >= 400) {
      throw PosError(result['status'], result['body']['error']);
    }
    return Json.from(result['body']);
  }

  Future<Json> request(
    String method,
    String path,
    Json body,
    String? token,
    String? op,
  ) async {
    final call = {
      'method': method,
      'path': path,
      'body': body,
      'token': token,
      'operation_id': op,
    };
    if (central) {
      return execute(call);
    }
    if (method == 'POST' && path == '/api/auth/logout') {
      if (token != null) { await forgetSession(token, revoke: true); await sync(); }
      return {'success': true};
    }
    if (path != '/api/auth/login') { await localUser(token); }
    final cacheKey = '$hubId|$token|$path';
    final queueable =
        method == 'POST' &&
        ['/api/pedidos', '/api/pedidos/lote'].contains(path);
    if (queueable) {
      if (token == null || op == null) {
        throw PosError(401, 'Inicia sesión antes de enviar');
      }
      final userId = await engine.setting('session-user:$token');
      if (userId == null) {
        throw PosError(401, 'Inicia sesión de nuevo para habilitar los envíos');
      }
      final existing = await engine.db.query(
        'outbox',
        where: 'id=?',
        whereArgs: [op],
      );
      if (existing.isNotEmpty &&
          (existing.first['token'] != token || existing.first['path'] != path ||
              existing.first['body'] != jsonEncode(body))) {
        throw PosError(409, 'Operación pendiente diferente');
      }
      await engine.db.insert('outbox', {
        'id': op,
        'user_id': int.parse(userId),
        'token': token,
        'path': path,
        'body': jsonEncode(body),
        'status': 'pending',
        'created': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    try {
      final result = await remote(call);
      if (method == 'POST' && path == '/api/auth/login') {
        final newToken = result['token'] as String;
        await engine.setSetting(
          'session-user:$newToken',
          '${result['user']['id']}',
        );
        await engine.setSetting('session-expiry:$newToken', result['expires_at']);
        await engine.db.insert('cache', {
          'key': '$hubId|$newToken|/api/auth/me',
          'value': jsonEncode({'user': result['user']}),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await engine.db.update(
          'outbox',
          {'token': newToken},
          where: 'user_id=?',
          whereArgs: [result['user']['id']],
        );
      }
      if (method == 'GET' &&
          !path.startsWith('/api/local/events') &&
          !path.endsWith('/backup')) {
        await engine.db.insert('cache', {
          'key': cacheKey,
          'value': jsonEncode(result),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (queueable) {
        await engine.db.delete('outbox', where: 'id=?', whereArgs: [op]);
      }
      return result;
    } on PosError catch (e) {
      if (e.status == 401 && token != null) { await forgetSession(token); }
      if (queueable) {
        await engine.db.update(
          'outbox',
          {'status': 'blocked', 'error': e.message},
          where: 'id=?',
          whereArgs: [op],
        );
        return {
          'queued': true,
          'blocked': true,
          'operation_id': op,
          'mensaje': e.message,
        };
      }
      rethrow;
    } catch (_) {
      connected = false;
      if (queueable) {
        return {
          'queued': true,
          'operation_id': op,
          'mensaje':
              'Guardado en esta tablet. Cocina todavía no ha confirmado.',
        };
      }
      if (method == 'GET' && !path.startsWith('/api/local/events')) {
        final cached = await engine.db.query(
          'cache',
          where: 'key=?',
          whereArgs: [cacheKey],
        );
        if (cached.isNotEmpty) {
          return {
            ...jsonDecode(cached.first['value'] as String) as Json,
            'cached': true,
          };
        }
      }
      throw PosError(
        503,
        'Sin enlace con cocina. Conserva los cambios y vuelve a intentar al reconectar.',
      );
    }
  }

  Future<void> sync() async {
    if (closed || central || syncing) {
      return;
    }
    syncing = true;
    try {
      await remote({'method': 'GET', 'path': '/api/local/ping', 'body': {}});
      for (final row in await engine.db.query('revocations')) {
        await remote({'method': 'POST', 'path': '/api/auth/logout', 'body': {}, 'token': row['token']});
        await engine.db.delete('revocations', where: 'token=?', whereArgs: [row['token']]);
      }
      for (final row in await engine.db.query(
        'outbox',
        where: 'status=?',
        whereArgs: ['pending'],
        orderBy: 'created ASC',
      )) {
        try {
          await remote({
            'method': 'POST',
            'path': row['path'],
            'body': jsonDecode(row['body'] as String),
            'token': row['token'],
            'operation_id': row['id'],
          });
          await engine.db.delete(
            'outbox',
            where: 'id=?',
            whereArgs: [row['id']],
          );
        } on PosError catch (e) {
          await engine.db.update(
            'outbox',
            {'status': 'blocked', 'error': e.message},
            where: 'id=?',
            whereArgs: [row['id']],
          );
        }
      }
    } catch (_) {
      connected = false;
    } finally {
      syncing = false;
    }
  }
}
