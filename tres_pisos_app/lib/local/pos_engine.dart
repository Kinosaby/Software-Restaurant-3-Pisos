import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite_common/sqlite_api.dart';

typedef Json = Map<String, dynamic>;

class PosError implements Exception {
  final int status;
  final String message;
  PosError(this.status, this.message);
  @override
  String toString() => message;
}

String randomKey() =>
    base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)));

/// One authoritative SQLite database. Mutations and their retry receipts commit
/// together, so an acknowledgement lost over Wi-Fi cannot duplicate an order.
class PosEngine {
  final Database db;
  final DateTime Function() clock;
  PosEngine(this.db, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  static Future<void> createSchema(Database db, int version) async {
    for (final sql in [
      'CREATE TABLE records(kind TEXT NOT NULL,id INTEGER NOT NULL,payload TEXT NOT NULL,estado TEXT,creado_en TEXT,PRIMARY KEY(kind,id))',
      'CREATE INDEX records_queue ON records(kind,estado,creado_en,id)',
      'CREATE INDEX records_date ON records(kind,creado_en,id)',
      'CREATE TABLE order_items(order_id INTEGER,item_id INTEGER,product_id INTEGER,nombre TEXT,cantidad INTEGER,PRIMARY KEY(order_id,item_id))',
      'CREATE INDEX order_items_product ON order_items(product_id)',
      'CREATE TABLE sequences(kind TEXT PRIMARY KEY,value INTEGER NOT NULL)',
      'CREATE TABLE sessions(token TEXT PRIMARY KEY,user_id INTEGER NOT NULL,expires TEXT NOT NULL)',
      'CREATE TABLE receipts(key TEXT PRIMARY KEY,user_id INTEGER NOT NULL,fingerprint TEXT NOT NULL,response TEXT NOT NULL)',
      'CREATE TABLE events(seq INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,payload TEXT NOT NULL)',
      'CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
      'CREATE TABLE cache(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
      'CREATE TABLE outbox(id TEXT PRIMARY KEY,user_id INTEGER NOT NULL,token TEXT NOT NULL,path TEXT NOT NULL,body TEXT NOT NULL,status TEXT NOT NULL,error TEXT,created TEXT NOT NULL)',
    ]) {
      await db.execute(sql);
    }
  }

  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where: 'key=?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Json>> records(
    DatabaseExecutor tx,
    String kind, {
    String extra = '',
    List<Object?> args = const [],
    int? limit,
    int? offset,
    String order = 'id ASC',
  }) async {
    final rows = await tx.query(
      'records',
      where: 'kind=? $extra',
      whereArgs: [kind, ...args],
      orderBy: order,
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => jsonDecode(r['payload'] as String) as Json).toList();
  }

  Future<Json> record(DatabaseExecutor tx, String kind, int id) async {
    final rows = await records(tx, kind, extra: 'AND id=?', args: [id]);
    if (rows.isEmpty) {
      throw PosError(404, 'Registro no encontrado');
    }
    return rows.first;
  }

  Future<void> save(DatabaseExecutor tx, String kind, Json value) async {
    await tx.insert('records', {
      'kind': kind,
      'id': value['id'],
      'payload': jsonEncode(value),
      'estado': value['estado'],
      'creado_en': value['creado_en'] ?? value['fecha'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (kind == 'orders') {
      await tx.delete(
        'order_items',
        where: 'order_id=?',
        whereArgs: [value['id']],
      );
      if (value['estado'] != 'cancelado') {
        for (final i in value['productos'] as List) {
          await tx.insert('order_items', {
            'order_id': value['id'],
            'item_id': i['id'],
            'product_id': i['producto_id'],
            'nombre': i['nombre'],
            'cantidad': i['cantidad'],
          });
        }
      }
    }
  }

  Future<int> nextId(DatabaseExecutor tx, String kind) async {
    await tx.rawInsert(
      'INSERT OR IGNORE INTO sequences(kind,value) VALUES(?,0)',
      [kind],
    );
    await tx.rawUpdate('UPDATE sequences SET value=value+1 WHERE kind=?', [
      kind,
    ]);
    return (await tx.query(
          'sequences',
          where: 'kind=?',
          whereArgs: [kind],
        )).first['value']
        as int;
  }

  Future<void> event(DatabaseExecutor tx, String name, Json data) async {
    await tx.insert('events', {'name': name, 'payload': jsonEncode(data)});
    await tx.rawDelete(
      'DELETE FROM events WHERE seq < (SELECT MAX(seq)-10000 FROM events)',
    );
  }

  String now() => clock().toUtc().toIso8601String();
  String day(DateTime time) => time
      .toUtc()
      .subtract(const Duration(hours: 6))
      .toIso8601String()
      .substring(0, 10);
  String get today => day(clock());
  String get dayStart => '${today}T06:00:00.000Z';
  static int integer(dynamic v, {int min = 1, int max = 1000000000}) {
    final n = int.tryParse('$v');
    if (n == null || n < min || n > max) {
      throw PosError(400, 'Número fuera de rango');
    }
    return n;
  }

  // The legacy web templates interpolate strings into HTML and event attributes.
  static String label(dynamic v, {int max = 100, bool empty = false}) {
    final s = (v ?? '').toString().trim();
    if ((!empty && s.isEmpty) ||
        s.length > max ||
        RegExp(r'''[<>"'`\\&\x00-\x1f]''').hasMatch(s)) {
      throw PosError(
        400,
        'Texto inválido: usa letras, números, espacios y puntuación simple',
      );
    }
    return s;
  }

  static int money(dynamic v) {
    final s = '$v';
    if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(s)) {
      throw PosError(400, 'Importe inválido');
    }
    return (double.parse(s) * 100).round();
  }

  Future<String> passwordHash(String p, String salt) async {
    final k = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(p)), nonce: utf8.encode(salt));
    return base64Encode(await k.extractBytes());
  }

  Json publicUser(Json u) => {
    'id': u['id'],
    'username': u['username'],
    'role': u['role'],
  };
  Future<Json> user(DatabaseExecutor tx, String? token) async {
    final s = await tx.query(
      'sessions',
      where: 'token=? AND expires>?',
      whereArgs: [token ?? '', now()],
    );
    if (s.isEmpty) {
      throw PosError(401, 'Inicia sesión en la central');
    }
    return record(tx, 'users', s.first['user_id'] as int);
  }

  void require(Json actor, List<String> roles) {
    if (!roles.contains(actor['role'])) {
      throw PosError(403, 'Tu rol no puede realizar esta operación');
    }
  }

  Future<void> bootstrap(String username, String password) async {
    await db.transaction((tx) async {
      if ((await records(tx, 'users')).isNotEmpty) {
        throw PosError(409, 'La central ya está configurada');
      }
      await writeUser(tx, null, {
        'username': username,
        'password': password,
        'role': 'admin',
      }, null);
    });
  }

  Future<Json> writeUser(
    DatabaseExecutor tx,
    int? id,
    Json b,
    Json? actor,
  ) async {
    if (actor != null) {
      require(actor, ['admin']);
    }
    final old = id == null ? null : await record(tx, 'users', id);
    final name = label(b['username'] ?? old?['username'], max: 30);
    final role = b['role'] ?? old?['role'];
    if (!['admin', 'mesero', 'cocina'].contains(role)) {
      throw PosError(400, 'Rol inválido');
    }
    final all = await records(tx, 'users');
    if (all.any(
      (u) =>
          u['id'] != id &&
          u['username'].toString().toLowerCase() == name.toLowerCase(),
    )) {
      throw PosError(409, 'Ese usuario ya existe');
    }
    if (old?['role'] == 'admin' &&
        role != 'admin' &&
        all.where((u) => u['role'] == 'admin').length == 1) {
      throw PosError(409, 'Debe existir al menos un administrador');
    }
    final p = (b['password'] ?? '').toString();
    if ((old == null || p.isNotEmpty) && (p.length < 8 || p.length > 128)) {
      throw PosError(400, 'La contraseña debe tener entre 8 y 128 caracteres');
    }
    final salt = p.isEmpty ? old!['salt'] as String : randomKey();
    final result = {
      'id': id ?? await nextId(tx, 'users'),
      'username': name,
      'role': role,
      'salt': salt,
      'password': p.isEmpty ? old!['password'] : await passwordHash(p, salt),
    };
    await save(tx, 'users', result);
    if (old != null && (p.isNotEmpty || old['role'] != role)) {
      await tx.delete('sessions', where: 'user_id=?', whereArgs: [id]);
    }
    return {'usuario': publicUser(result)};
  }

  Future<Json> call(
    String method,
    Uri uri, {
    Json body = const {},
    String? token,
    String? operationId,
  }) async => db.transaction((tx) async {
    if (uri.path == '/api/auth/login' && method == 'POST') {
      final matches = (await records(tx, 'users')).where(
        (u) =>
            u['username'].toString().toLowerCase() ==
            (body['username'] ?? '').toString().trim().toLowerCase(),
      );
      if (matches.isEmpty) {
        throw PosError(401, 'Usuario o contraseña incorrectos');
      }
      final u = matches.first;
      if (await passwordHash((body['password'] ?? '').toString(), u['salt']) !=
          u['password']) {
        throw PosError(401, 'Usuario o contraseña incorrectos');
      }
      final key = randomKey();
      await tx.delete('sessions', where: 'expires<=?', whereArgs: [now()]);
      await tx.insert('sessions', {
        'token': key,
        'user_id': u['id'],
        'expires': clock()
            .toUtc()
            .add(const Duration(days: 30))
            .toIso8601String(),
      });
      return {'token': key, 'user': publicUser(u)};
    }
    final actor = await user(tx, token);
    if (method == 'GET') {
      return read(tx, uri, actor);
    }
    if (operationId == null ||
        operationId.length < 16 ||
        operationId.length > 128) {
      throw PosError(400, 'Falta identificador de operación');
    }
    final fingerprint = jsonEncode([method, uri.path, body]);
    final receipts = await tx.query(
      'receipts',
      where: 'key=?',
      whereArgs: [operationId],
    );
    if (receipts.isNotEmpty) {
      final r = receipts.first;
      if (r['user_id'] != actor['id'] || r['fingerprint'] != fingerprint) {
        throw PosError(409, 'Identificador reutilizado con otra operación');
      }
      return jsonDecode(r['response'] as String) as Json;
    }
    final result = {
      'success': true,
      ...await mutate(tx, method, uri, body, actor),
    };
    await tx.insert('receipts', {
      'key': operationId,
      'user_id': actor['id'],
      'fingerprint': fingerprint,
      'response': jsonEncode(result),
    });
    return result;
  });
  Future<Json> read(DatabaseExecutor tx, Uri uri, Json actor) async {
    final path = uri.path;
    if (path == '/api/auth/me') {
      return {'user': publicUser(actor)};
    }
    if (path == '/api/productos') {
      return {'productos': await records(tx, 'products')};
    }
    if (path == '/api/auth/usuarios') {
      require(actor, ['admin']);
      return {
        'usuarios': (await records(tx, 'users')).map(publicUser).toList(),
      };
    }
    if (path == '/api/local/events') {
      final after = int.tryParse(uri.queryParameters['after'] ?? '') ?? -1;
      final bounds = (await tx.rawQuery(
        'SELECT MIN(seq) AS first,MAX(seq) AS last FROM events',
      )).first;
      final last = bounds['last'] as int? ?? 0;
      final first = bounds['first'] as int? ?? 0;
      if (after < 0 || after > last || after < first - 1) {
        return {'cursor': last, 'reset': true, 'events': []};
      }
      final rows = await tx.query(
        'events',
        where: 'seq>?',
        whereArgs: [after],
        orderBy: 'seq ASC',
        limit: 300,
      );
      return {
        'cursor': rows.isEmpty ? last : rows.last['seq'],
        'events': rows
            .map(
              (r) => {
                'name': r['name'],
                'data': jsonDecode(r['payload'] as String),
              },
            )
            .toList(),
      };
    }
    if (path == '/api/extras') {
      return {
        'extras': await records(
          tx,
          'extras',
          extra: 'AND estado=?',
          args: ['pendiente'],
        ),
      };
    }
    if (path == '/api/pedidos') {
      if (uri.queryParameters['scope'] == 'history') {
        require(actor, ['admin']);
        final page = integer(uri.queryParameters['page'] ?? '0', min: 0);
        final date = uri.queryParameters['date'];
        final args = <Object?>[];
        String filter = '';
        if (date != null && date.isNotEmpty) {
          final d = DateTime.tryParse('${date}T06:00:00Z');
          if (d == null) {
            throw PosError(400, 'Fecha inválida');
          }
          filter = 'AND creado_en>=? AND creado_en<?';
          args.addAll([
            d.toIso8601String(),
            d.add(const Duration(days: 1)).toIso8601String(),
          ]);
        }
        final rows = await records(
          tx,
          'orders',
          extra: filter,
          args: args,
          limit: 101,
          offset: page * 100,
          order: 'creado_en DESC,id DESC',
        );
        return {
          'pedidos': rows.take(100).toList(),
          'hasMore': rows.length > 100,
          'page': page,
        };
      }
      final state = uri.queryParameters['estado'];
      return {
        'pedidos': await records(
          tx,
          'orders',
          extra: state == null
              ? "AND (estado NOT IN ('pagado','cancelado') OR creado_en>=?)"
              : 'AND estado=?',
          args: state == null ? [dayStart] : [state],
          order: 'creado_en ASC,id ASC',
        ),
      };
    }
    if (RegExp(r'^/api/pedidos/\d+$').hasMatch(path)) {
      return {
        'pedido': await record(tx, 'orders', integer(uri.pathSegments.last)),
      };
    }
    if (path.startsWith('/api/metricas/')) {
      require(actor, ['admin']);
      return metrics(tx, uri);
    }
    if (path == '/api/local/backup') {
      require(actor, ['admin']);
      return {
        'format': '3pisos-local-v1',
        'created': now(),
        'records': await tx.query('records'),
        'sequences': await tx.query('sequences'),
        'receipts': await tx.query('receipts'),
      };
    }
    throw PosError(404, 'Ruta no encontrada');
  }

  Future<List<Json>> makeItems(DatabaseExecutor tx, dynamic raw) async {
    if (raw is! List || raw.isEmpty || raw.length > 100) {
      throw PosError(400, 'Agrega de 1 a 100 productos');
    }
    final result = <Json>[];
    for (final e in raw) {
      if (e is! Map) {
        throw PosError(400, 'Producto inválido');
      }
      final p = await record(tx, 'products', integer(e['producto_id']));
      if (p['activo'] != true) {
        throw PosError(409, '${p['nombre']} no está disponible');
      }
      result.add({
        'id': await nextId(tx, 'items'),
        'producto_id': p['id'],
        'nombre': p['nombre'],
        'precio': money(p['precio']) / 100,
        'precio_unitario': money(p['precio']) / 100,
        'cantidad': integer(e['cantidad'], max: 999),
        'nota': label(e['nota'], max: 500, empty: true),
        'listo': false,
      });
    }
    return result;
  }

  int total(List<dynamic> items) => items.fold(
    0,
    (sum, i) => sum + money(i['precio']) * integer(i['cantidad'], max: 999),
  );
  Future<Json> createOrder(DatabaseExecutor tx, Json b, Json actor) async {
    require(actor, ['admin', 'mesero']);
    final type = b['tipo'] ?? 'aqui';
    if (!['aqui', 'llevar'].contains(type)) {
      throw PosError(400, 'Tipo inválido');
    }
    final items = await makeItems(tx, b['productos']);
    final p = <String, dynamic>{
      'id': await nextId(tx, 'orders'),
      'mesa': integer(b['mesa'], max: 999),
      'tipo': type,
      'comensal': label(b['comensal'], max: 50, empty: true),
      'usuario_id': actor['id'],
      'estado': 'pendiente',
      'total': total(items) / 100,
      'productos': items,
      'creado_en': now(),
      'version': 1,
    };
    await save(tx, 'orders', p);
    await event(tx, 'nuevo_pedido', p);
    return p;
  }

  Future<Json> mutate(
    DatabaseExecutor tx,
    String method,
    Uri uri,
    Json b,
    Json actor,
  ) async {
    final path = uri.path;
    if (path == '/api/auth/logout') {
      await tx.delete('sessions', where: 'user_id=?', whereArgs: [actor['id']]);
      return {};
    }
    if (path == '/api/auth/register' && method == 'POST') {
      require(actor, ['admin']);
      return writeUser(tx, null, b, actor);
    }
    if (RegExp(r'^/api/auth/\d+$').hasMatch(path)) {
      require(actor, ['admin']);
      final id = integer(uri.pathSegments.last);
      if (method == 'PUT') {
        return writeUser(tx, id, b, actor);
      }
      if (method == 'DELETE') {
        final target = await record(tx, 'users', id);
        if (id == actor['id'] ||
            (target['role'] == 'admin' &&
                (await records(
                      tx,
                      'users',
                    )).where((u) => u['role'] == 'admin').length ==
                    1)) {
          throw PosError(409, 'No puedes eliminar esta cuenta administradora');
        }
        await tx.delete(
          'records',
          where: 'kind=? AND id=?',
          whereArgs: ['users', id],
        );
        await tx.delete('sessions', where: 'user_id=?', whereArgs: [id]);
        return {};
      }
    }
    if (path == '/api/productos' ||
        RegExp(r'^/api/productos/\d+$').hasMatch(path)) {
      require(actor, ['admin']);
      final id = path == '/api/productos'
          ? null
          : integer(uri.pathSegments.last);
      final old = id == null ? null : await record(tx, 'products', id);
      if (!['POST', 'PUT', 'DELETE'].contains(method) ||
          (id == null && method != 'POST')) {
        throw PosError(405, 'Método inválido');
      }
      final cents = money(
        method == 'DELETE' ? old!['precio'] : b['precio'] ?? old?['precio'],
      );
      if (cents <= 0) {
        throw PosError(400, 'El precio debe ser mayor a cero');
      }
      final product = {
        'id': id ?? await nextId(tx, 'products'),
        'nombre': label(b['nombre'] ?? old?['nombre']),
        'precio': cents / 100,
        'categoria': label(
          b['categoria'] ?? old?['categoria'] ?? 'General',
          max: 50,
        ),
        'activo': method == 'DELETE'
            ? false
            : b['activo'] ?? old?['activo'] ?? true,
      };
      if (product['activo'] is! bool) {
        throw PosError(400, 'Disponibilidad inválida');
      }
      await save(tx, 'products', product);
      await event(tx, 'catalogo_actualizado', {});
      return {'producto': product};
    }
    if (path == '/api/pedidos' && method == 'POST') {
      return {'pedido': await createOrder(tx, b, actor)};
    }
    if (path == '/api/pedidos/lote' && method == 'POST') {
      require(actor, ['admin', 'mesero']);
      final batch = b['pedidos'];
      if (batch is! List || batch.isEmpty || batch.length > 30) {
        throw PosError(400, 'Lote inválido');
      }
      final result = <Json>[];
      for (final p in batch) {
        result.add(await createOrder(tx, Json.from(p as Map), actor));
      }
      return {'pedidos': result};
    }
    if (path == '/api/pedidos/cobrar' && method == 'POST') {
      require(actor, ['admin', 'mesero']);
      final ids = b['ids'];
      if (ids is! List ||
          ids.isEmpty ||
          ids.length > 50 ||
          ids.toSet().length != ids.length) {
        throw PosError(400, 'Cuentas inválidas');
      }
      final extras = await records(
        tx,
        'extras',
        extra: 'AND estado=?',
        args: ['pendiente'],
      );
      final orders = <Json>[];
      for (final id in ids) {
        final p = await record(tx, 'orders', integer(id));
        if (p['estado'] != 'listo') {
          throw PosError(409, 'El pedido #$id ya cambió; revisa la cuenta');
        }
        if (extras.any((e) => e['pedido_id'] == p['id'])) {
          throw PosError(409, 'Cocina aún tiene extras pendientes');
        }
        orders.add(p);
      }
      final due = orders.fold<int>(0, (s, p) => s + money(p['total']));
      if (money(b['total_esperado']) != due) {
        throw PosError(409, 'El total cambió. Revisa la cuenta');
      }
      final received = money(b['recibido']);
      if (received < due) {
        throw PosError(400, 'El pago no cubre la cuenta');
      }
      for (final p in orders) {
        p['estado'] = 'pagado';
        p['version']++;
        await save(tx, 'orders', p);
        await save(tx, 'sales', {
          'id': p['id'],
          'pedido_id': p['id'],
          'total': p['total'],
          'fecha': now(),
        });
        await event(tx, 'pedido_actualizado', p);
      }
      return {
        'pedidos': orders,
        'total': due / 100,
        'cambio': (received - due) / 100,
      };
    }
    if (RegExp(r'^/api/extras/\d+$').hasMatch(path) && method == 'PATCH') {
      require(actor, ['admin', 'cocina']);
      final ex = await record(tx, 'extras', integer(uri.pathSegments.last));
      if (b['done'] == true) {
        ex['estado'] = 'listo';
      }
      if (b['item'] != null) {
        final index = integer(
          b['item'],
          min: 0,
          max: (ex['items'] as List).length - 1,
        );
        ex['_done'] = {...?ex['_done'] as Map?, '$index': b['listo'] == true};
      }
      await save(tx, 'extras', ex);
      await event(tx, 'extras_actualizados', {});
      return {'extra': ex};
    }
    if (uri.pathSegments.length >= 3 && uri.pathSegments[1] == 'pedidos') {
      final id = integer(uri.pathSegments[2]);
      final p = await record(tx, 'orders', id);
      final action = uri.pathSegments.length > 3 ? uri.pathSegments[3] : '';
      if (method == 'DELETE' && action.isEmpty) {
        require(actor, ['admin']);
        await tx.delete(
          'records',
          where: 'kind=? AND id=?',
          whereArgs: ['orders', id],
        );
        await tx.delete('order_items', where: 'order_id=?', whereArgs: [id]);
        await cancelExtras(tx, id);
        await event(tx, 'pedido_eliminado', {'id': id});
        return {'pedido': p};
      }
      if (action == 'agregar' && method == 'PATCH') {
        require(actor, ['admin', 'mesero']);
        if (p['estado'] == 'cancelado') {
          throw PosError(409, 'El pedido está cancelado');
        }
        if (p['estado'] == 'pagado') {
          final next = await createOrder(tx, {
            'mesa': p['mesa'],
            'tipo': b['tipo'] ?? p['tipo'],
            'comensal': p['comensal'],
            'productos': b['productos'],
          }, actor);
          return {'pedido': next, 'nueva_cuenta': true};
        }
        final items = await makeItems(tx, b['productos']);
        if (p['estado'] == 'listo') {
          final eid = await nextId(tx, 'extras');
          final ex = {
            'id': eid,
            '_id': eid,
            'pedido_id': id,
            'mesa': p['mesa'],
            'tipo': p['tipo'],
            'comensal': p['comensal'],
            'items': items,
            '_done': <String, bool>{},
            'estado': 'pendiente',
            'creado_en': now(),
          };
          await save(tx, 'extras', ex);
          await event(tx, 'extra_pedido', ex);
        }
        p['productos'] = [...p['productos'] as List, ...items];
        p['total'] = total(p['productos']) / 100;
        p['_accion'] = 'productos_agregados';
      } else if (action == 'editar' && method == 'PATCH') {
        require(actor, ['admin', 'mesero']);
        if (['pagado', 'cancelado'].contains(p['estado'])) {
          throw PosError(409, 'La cuenta está cerrada');
        }
        if (b['version'] != p['version']) {
          throw PosError(
            409,
            'El pedido cambió en otra tablet. Actualiza antes de editar',
          );
        }
        if (b.containsKey('mesa')) {
          p['mesa'] = integer(b['mesa'], max: 999);
          p['tipo'] = p['mesa'] == 99 ? 'llevar' : 'aqui';
        }
        if (b.containsKey('items')) {
          if (p['estado'] == 'listo') {
            throw PosError(409, 'Los productos ya están listos');
          }
          if (b['items'] is! List) {
            throw PosError(400, 'Edición inválida');
          }
          final items = (p['productos'] as List)
              .map((i) => Json.from(i as Map))
              .toList();
          for (final change in b['items'] as List) {
            final found = items.where((i) => i['id'] == change['detalle_id']);
            if (found.isEmpty) {
              throw PosError(409, 'El producto ya no pertenece al pedido');
            }
            final i = found.first;
            i['cantidad'] = integer(change['cantidad'], min: 0, max: 999);
            i['nota'] = label(change['nota'], max: 500, empty: true);
            i['listo'] = false;
          }
          items.removeWhere((i) => i['cantidad'] == 0);
          if (items.isEmpty) {
            throw PosError(400, 'Usa Cancelar para retirar todo el pedido');
          }
          p['productos'] = items;
          p['total'] = total(items) / 100;
        }
      } else if (action == 'item' && method == 'PATCH') {
        require(actor, ['admin', 'cocina']);
        if (!['pendiente', 'preparando'].contains(p['estado'])) {
          throw PosError(409, 'El pedido ya salió de cocina');
        }
        final found = (p['productos'] as List).where(
          (i) => i['id'] == b['detalle_id'],
        );
        if (found.isEmpty) {
          throw PosError(404, 'Producto no encontrado');
        }
        found.first['listo'] = b['listo'] == true;
      } else if ((action == 'estado' && method == 'PUT') ||
          (action == 'cancelar' && method == 'PATCH')) {
        final target = action == 'cancelar' ? 'cancelado' : b['estado'];
        if (target == 'pagado') {
          throw PosError(400, 'Usa el cobro con total y pago confirmado');
        }
        if (target == p['estado']) {
          return {'pedido': p};
        }
        if (['pagado', 'cancelado'].contains(p['estado'])) {
          throw PosError(409, 'La cuenta está cerrada');
        }
        if (target == 'cancelado') {
          require(actor, ['admin', 'mesero', 'cocina']);
          if (actor['role'] == 'cocina' && p['estado'] == 'listo') {
            throw PosError(403, 'Solicita la cancelación al mesero');
          }
          await cancelExtras(tx, id);
        } else {
          require(actor, ['admin', 'cocina']);
          if (!((p['estado'] == 'pendiente' && target == 'preparando') ||
              (p['estado'] == 'preparando' && target == 'listo'))) {
            throw PosError(409, 'Cambio de estado inválido');
          }
        }
        p['estado'] = target;
      } else {
        throw PosError(404, 'Operación desconocida');
      }
      p['version']++;
      await save(tx, 'orders', p);
      await event(tx, 'pedido_actualizado', p);
      return {'pedido': p};
    }
    throw PosError(404, 'Operación no encontrada');
  }

  Future<void> cancelExtras(DatabaseExecutor tx, int id) async {
    for (final ex in await records(
      tx,
      'extras',
      extra: 'AND estado=?',
      args: ['pendiente'],
    )) {
      if (ex['pedido_id'] == id) {
        ex['estado'] = 'cancelado';
        await save(tx, 'extras', ex);
      }
    }
    await event(tx, 'extras_actualizados', {});
  }

  Future<Json> metrics(DatabaseExecutor tx, Uri uri) async {
    final sales = await records(
      tx,
      'sales',
      extra: 'AND creado_en>=?',
      args: [
        clock().toUtc().subtract(const Duration(days: 366)).toIso8601String(),
      ],
    );
    final counts = await tx.rawQuery(
      "SELECT COUNT(*) AS n FROM records WHERE kind='orders' AND estado!='cancelado' AND creado_en>=?",
      [dayStart],
    );
    final daily = <String, Json>{};
    for (final s in sales) {
      final key = day(DateTime.parse(s['fecha']));
      final v = daily.putIfAbsent(
        key,
        () => {'fecha': key, 'pedidos': 0, 'cents': 0},
      );
      v['pedidos']++;
      v['cents'] += money(s['total']);
    }
    final series =
        daily.values
            .map(
              (d) => {
                'fecha': d['fecha'],
                'pedidos': d['pedidos'],
                'total': d['cents'] / 100,
              },
            )
            .toList()
          ..sort(
            (a, b) => (a['fecha'] as String).compareTo(b['fecha'] as String),
          );
    final d = {
      'total_ventas': (daily[today]?['cents'] ?? 0) / 100,
      'total_pedidos': counts.first['n'],
    };
    final local = clock().toUtc().subtract(const Duration(hours: 6));
    final monday = local
        .subtract(Duration(days: local.weekday - 1))
        .toIso8601String()
        .substring(0, 10);
    final weekly = series
        .where((s) => (s['fecha'] as String).compareTo(monday) >= 0)
        .fold<double>(0, (v, s) => v + (s['total'] as num).toDouble());
    if (uri.path.endsWith('/ventas')) {
      final since = day(
        clock().subtract(
          Duration(days: integer(uri.queryParameters['dias'] ?? '7', max: 365)),
        ),
      );
      return {
        'ventas': series
            .where((s) => (s['fecha'] as String).compareTo(since) >= 0)
            .toList(),
      };
    }
    final states = await tx.rawQuery(
      "SELECT estado,COUNT(*) AS cantidad FROM records WHERE kind='orders' GROUP BY estado",
    );
    final top = await tx.rawQuery(
      'SELECT nombre,SUM(cantidad) AS total_pedido FROM order_items GROUP BY nombre ORDER BY total_pedido DESC LIMIT ?',
      [integer(uri.queryParameters['limit'] ?? '5', max: 50)],
    );
    if (uri.path.endsWith('/dia')) {
      return d;
    }
    if (uri.path.endsWith('/estados')) {
      return {'estados': states};
    }
    if (uri.path.endsWith('/productos-top')) {
      return {'productos': top};
    }
    return {'dia': d, 'semana': weekly, 'estados': states, 'productosTop': top};
  }

  Future<void> restore(Json backup) async {
    if (backup['format'] != '3pisos-local-v1' ||
        backup['records'] is! List ||
        backup['sequences'] is! List ||
        backup['receipts'] is! List) {
      throw PosError(400, 'Respaldo inválido');
    }
    await db.transaction((tx) async {
      if ((await tx.query('records', limit: 1)).isNotEmpty) {
        throw PosError(409, 'Solo se puede restaurar en una central nueva');
      }
      var admins = 0;
      for (final raw in backup['records'] as List) {
        final row = Json.from(raw as Map);
        if (![
          'users',
          'products',
          'orders',
          'extras',
          'sales',
        ].contains(row['kind'])) {
          throw PosError(400, 'Registro inválido');
        }
        final value = jsonDecode(row['payload'] as String) as Json;
        if (value['id'] != row['id']) {
          throw PosError(400, 'Identificador inválido');
        }
        if (row['kind'] == 'users') {
          if (!['admin', 'mesero', 'cocina'].contains(value['role']) ||
              value['salt'] is! String ||
              value['password'] is! String) {
            throw PosError(400, 'Cuenta inválida');
          }
          if (value['role'] == 'admin') {
            admins++;
          }
        }
        await save(tx, row['kind'], value);
      }
      if (admins == 0) {
        throw PosError(400, 'El respaldo no tiene administrador');
      }
      for (final r in backup['sequences'] as List) {
        await tx.insert('sequences', Json.from(r as Map));
      }
      for (final r in backup['receipts'] as List) {
        await tx.insert('receipts', Json.from(r as Map));
      }
    });
  }
}
