import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tres_pisos_app/local/pos_engine.dart';
import 'package:tres_pisos_app/local/pos_server.dart';

class DelayedOrderClient extends PosServer {
  final started = Completer<void>(), rejected = Completer<void>();
  bool delayed = false;
  DelayedOrderClient(PosEngine local, PosServer central)
      : super(engine: local, central: false, pairSecret: central.pairSecret,
          hubId: central.hubId, hub: Uri.parse('http://127.0.0.1:${central.lanServer!.port}'),
          asset: (_) async => []);

  @override
  Future<Json> remote(Json call) async {
    if (!delayed && call['method'] == 'POST' && call['path'] == '/api/pedidos') {
      delayed = true;
      started.complete();
      await rejected.future;
      throw PosError(401, 'La sesión anterior venció');
    }
    return super.remote(call);
  }
}

void main() {
  sqfliteFfiInit();
  final databases = <Database>[], servers = <PosServer>[];
  late PosEngine engine;
  late PosServer hub;
  late String admin;
  late DateTime time;
  Matcher denied(int status) => throwsA(isA<PosError>().having((e) => e.status, 'status', status));
  Future<PosEngine> database([String path = inMemoryDatabasePath]) async {
    final db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(
      singleInstance: false, version: 3, onCreate: PosEngine.createSchema, onUpgrade: PosEngine.upgradeSchema));
    databases.add(db); return PosEngine(db, clock: () => time);
  }
  Future<Json> call(String method, String path, [Json body = const {}, String? token]) =>
    engine.call(method, Uri.parse(path), body: body, token: token ?? admin, operationId: randomKey());
  Future<PosServer> client([PosEngine? local]) async {
    final c = PosServer(engine: local ?? await database(), central: false,
      pairSecret: hub.pairSecret, hubId: hub.hubId,
      hub: Uri.parse('http://127.0.0.1:${hub.lanServer!.port}'), asset: (_) async => []);
    servers.add(c); return c;
  }
  Future<String> login(PosServer s, [String name = 'mesero']) async =>
    (await s.request('POST', '/api/auth/login', {'username': name, 'password': 'test-password'}, null, null))['token'];
  Future<Json> order() async => (await call('POST', '/api/pedidos', {
    'mesa': 1, 'productos': [{'producto_id': 1, 'cantidad': 1}]}))['pedido'];
  Future<void> ready(int id) async {
    await call('PUT', '/api/pedidos/$id/estado', {'estado': 'preparando'});
    await call('PUT', '/api/pedidos/$id/estado', {'estado': 'listo'});
  }
  setUp(() async {
    time = DateTime.now().toUtc();
    engine = await database(); await engine.bootstrap('admin', 'test-password');
    admin = (await engine.call('POST', Uri.parse('/api/auth/login'),
      body: {'username': 'admin', 'password': 'test-password'}))['token'];
    await call('POST', '/api/auth/register', {'username': 'mesero', 'password': 'test-password', 'role': 'mesero'});
    await call('POST', '/api/productos', {'nombre': 'Taco', 'precio': 18, 'categoria': 'Tacos'});
    hub = PosServer(engine: engine, central: true, pairSecret: randomKey(), hubId: randomKey(), asset: (_) async => utf8.encode('<html>POS</html>'));
    servers.add(hub); await hub.start(uiPort: 0, lanPort: 0);
  });
  tearDown(() async {
    for (final s in servers.reversed) { await s.stop(); } servers.clear();
    for (final d in databases.reversed) { if (d.isOpen) { await d.close(); } } databases.clear();
  });
  test('Mixed-type payment IDs cannot charge the same account twice', () async {
    final p = await order(); await ready(p['id']);
    await expectLater(call('POST', '/api/pedidos/cobrar', {
      'ids': [p['id'], '${p['id']}'], 'total_esperado': 36, 'recibido': 40}), denied(400));
    expect(await engine.records(engine.db, 'sales'), isEmpty);
    expect((await engine.record(engine.db, 'orders', p['id']))['estado'], 'listo');
    final results = await Future.wait(List.generate(2, (_) async {
      try { return await call('POST', '/api/pedidos/cobrar', {'ids': [p['id']], 'total_esperado': 18, 'recibido': 20}); }
      on PosError catch (e) { return {'status': e.status}; }
    }));
    expect(results.where((r) => r['success'] == true), hasLength(1));
    expect(results.where((r) => r['status'] == 409), hasLength(1));
    expect(await engine.records(engine.db, 'sales'), hasLength(1));
  });
  test('Logout is idempotent and revokes only the current session', () async {
    final other = await login(hub, 'admin');
    await call('POST', '/api/auth/logout'); await call('POST', '/api/auth/logout');
    await expectLater(call('GET', '/api/auth/me'), denied(401));
    expect((await call('GET', '/api/auth/me', {}, other))['user']['role'], 'admin');
    await expectLater(call('PUT', '/api/auth/logout', {}, other), denied(404));
  });
  test('Web server rejects foreign origins, DNS rebinding and other local apps', () async {
    final http = HttpClient(), url = Uri.parse('http://127.0.0.1:${hub.localServer!.port}/');
    Future<int> request(String path, Map<String, String> headers, [String method = 'GET']) async {
      final req = await http.openUrl(method, url.resolve(path)); headers.forEach(req.headers.set);
      final res = await req.close(); await res.drain<void>(); return res.statusCode;
    }
    try {
      expect(await request('/', {}), 403);
      expect(await request('/', {'X-Pos-UI-Key': hub.uiSecret}), 200);
      final cookie = {'Cookie': 'pos_ui=${hub.uiSecret}'};
      expect(await request('/api/productos', {...cookie, 'Authorization': 'Bearer $admin'}), 200);
      expect(await request('/api/productos', {...cookie, 'Host': 'attacker.invalid'}), 403);
      expect(await request('/api/productos', {...cookie, 'Origin': 'https://attacker.invalid'}), 403);
      expect(await request('/api/auth/login', cookie, 'POST'), 415);
      expect(await request('/api/productos', {'Authorization': 'Bearer $admin'}), 403);
    } finally { http.close(force: true); }
  });
  test('LAN challenge is required, authenticated and single-use', () async {
    final c = await client(), cipher = LanCipher(hub.pairSecret), http = HttpClient();
    final challenge = await c.exchange('/link/challenge', {});
    final envelope = await cipher.seal({'hub_id': hub.hubId, 'request_id': randomKey(),
      'challenge': challenge['challenge'], 'method': 'POST', 'path': '/api/pedidos',
      'body': {'mesa': 1, 'productos': [{'producto_id': 1, 'cantidad': 1}]},
      'token': admin, 'operation_id': randomKey()});
    Future<Json> send(Json box) async {
      final req = await http.postUrl(c.hub!.resolve('/link/rpc'));
      req.headers.contentType = ContentType.json; req.write(jsonEncode(box));
      final res = await req.close(), raw = await utf8.decoder.bind(res).join();
      return res.statusCode == 200 ? await cipher.open(jsonDecode(raw) as Json) : <String, dynamic>{'status': res.statusCode};
    }
    try {
      expect((await send(envelope))['status'], 200); expect((await send(envelope))['status'], 409);
      expect(await engine.records(engine.db, 'orders'), hasLength(1));
      expect((await send({...envelope, 'mac': base64Encode(List.filled(16, 0))}))['status'], 403);
      final stale = await c.exchange('/link/challenge', {});
      hub.challenges[stale['challenge']] = DateTime.now().subtract(const Duration(seconds: 1));
      await expectLater(c.exchange('/link/rpc', {'challenge': stale['challenge'], 'method': 'GET', 'path': '/api/auth/me', 'body': {}, 'token': admin}), denied(409));
      await expectLater(c.remote({'method': 'GET', 'path': '/api/local/backup', 'body': {}, 'token': admin}), denied(403));
    } finally { http.close(force: true); }
  });
  test('Login throttling uses normalized account names across addresses', () async {
    final c = await client();
    for (var i = 0; i < 10; i++) {
      await expectLater(c.remote({'method': 'POST', 'path': '/api/auth/login', 'body': {
        'username': i.isEven ? ' MESERO ' : 'mesero', 'password': 'wrong-password'}}), denied(401));
    }
    await expectLater(login(c), denied(429));
    expect(() => hub.throttleLogin({'username': 'MeSeRo'}, 'another-address'),
      throwsA(isA<PosError>().having((e) => e.status, 'status', 429)));
    await expectLater(call('POST', '/api/auth/login', {'username': 'admin', 'password': 'x' * 10000}), denied(401));
  });
  test('Offline logout survives a process restart and revokes on reconnection', () async {
    final dir = await Directory.systemTemp.createTemp('pos-revoke-');
    final local = await database('${dir.path}/client.db'), c = await client(local), token = await login(c);
    await c.request('GET', '/api/productos', {}, token, null);
    final port = hub.lanServer!.port;
    await hub.lanServer!.close(force: true); hub.lanServer = null;
    await c.request('POST', '/api/pedidos', {'mesa': 2, 'productos': [{'producto_id': 1, 'cantidad': 1}]}, token, randomKey());
    expect(await local.db.query('outbox'), hasLength(1));
    await c.request('POST', '/api/auth/logout', {}, token, null);
    await expectLater(c.request('GET', '/api/productos', {}, token, null), denied(401));
    expect(await local.db.query('cache'), isEmpty); expect(await local.db.query('revocations'), hasLength(1));
    await c.stop(); await local.db.close();
    hub.lanServer = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    hub.lanServer!.listen((r) => hub.handle(r, true));
    final restored = await client(await database('${dir.path}/client.db')); await restored.sync();
    expect(await restored.engine.db.query('revocations'), isEmpty);
    await expectLater(call('GET', '/api/auth/me', {}, token), denied(401));
    expect(await restored.engine.db.query('outbox'), hasLength(1));
    expect((await restored.engine.db.query('outbox')).single['status'], 'blocked');
    await restored.stop(); await restored.engine.db.close(); await dir.delete(recursive: true);
  });
  test('A revoked or expired client session cannot fall back to old cached access', () async {
    final c = await client(), token = await login(c);
    await c.request('GET', '/api/productos', {}, token, null);
    await call('PUT', '/api/auth/2', {'password': 'changed-password'});
    await expectLater(c.request('GET', '/api/productos', {}, token, null), denied(401));
    await hub.lanServer!.close(force: true); hub.lanServer = null;
    await expectLater(c.request('GET', '/api/productos', {}, token, null), denied(401));
    await c.engine.setSetting('session-user:expired', '2');
    await c.engine.setSetting('session-expiry:expired', DateTime.now().subtract(const Duration(seconds: 1)).toIso8601String());
    await expectLater(c.localUser('expired'), denied(401));
  });
  test('Restoring rejects injected HTML and repairs sequence collisions atomically', () async {
    final backup = jsonDecode(jsonEncode(await call('GET', '/api/local/backup'))) as Json, target = await database();
    final product = (backup['records'] as List).singleWhere((r) => r['kind'] == 'products');
    final payload = jsonDecode(product['payload']) as Json;
    product['payload'] = jsonEncode({...payload, 'nombre': '<img src=x onerror=alert(1)>'});
    await expectLater(target.restore(backup), denied(400));
    expect(await target.records(target.db, 'users'), isEmpty);
    product['payload'] = jsonEncode(payload); backup['sequences'] = []; await target.restore(backup);
    expect(await target.nextId(target.db, 'products'), 2); expect(await target.nextId(target.db, 'users'), 3);
  });
  test('Cancelled extras cannot be completed by a stale kitchen request', () async {
    final p = await order(); await ready(p['id']);
    await call('PATCH', '/api/pedidos/${p['id']}/agregar', {'productos': [{'producto_id': 1, 'cantidad': 1}]});
    await call('PATCH', '/api/pedidos/${p['id']}/cancelar');
    await expectLater(call('PATCH', '/api/extras/1', {'done': true}), denied(409));
  });

  test('History permissions apply to state filters, IDs, mutations and event snapshots', () async {
    await call('POST', '/api/auth/register', {'username': 'cocina', 'password': 'test-password', 'role': 'cocina'});
    final waiter = await login(hub), cook = await login(hub, 'cocina');
    final paid = await order(), cancelled = await order(), open = await order();
    await ready(paid['id']);
    await call('PATCH', '/api/pedidos/${paid['id']}/agregar', {'productos': [{'producto_id': 1, 'cantidad': 1}]});
    await call('PATCH', '/api/extras/1', {'done': true});
    await call('POST', '/api/pedidos/cobrar', {'ids': [paid['id']], 'total_esperado': 36, 'recibido': 40});
    await call('PATCH', '/api/pedidos/${cancelled['id']}/cancelar');
    time = time.add(const Duration(days: 2));
    final current = await order();
    await ready(current['id']);
    await call('POST', '/api/pedidos/cobrar', {'ids': [current['id']], 'total_esperado': 18, 'recibido': 20});
    for (final token in [waiter, cook]) {
      await expectLater(call('GET', '/api/pedidos?scope=history', {}, token), denied(403));
      expect((await call('GET', '/api/pedidos?estado=pagado', {}, token))['pedidos'].map((p) => p['id']), [current['id']]);
      expect((await call('GET', '/api/pedidos?estado=cancelado', {}, token))['pedidos'], isEmpty);
      expect((await call('GET', '/api/pedidos', {}, token))['pedidos'].map((p) => p['id']), [open['id'], current['id']]);
      for (final old in [paid, cancelled]) {
        await expectLater(call('GET', '/api/pedidos/${old['id']}', {}, token), denied(403));
      }
      expect((await call('GET', '/api/pedidos/${open['id']}', {}, token))['pedido']['id'], open['id']);
      final feed = await call('GET', '/api/local/events?after=0', {}, token);
      for (final event in feed['events']) {
        if (['nuevo_pedido', 'pedido_actualizado'].contains(event['name'])) {
          expect([open['id'], current['id']], contains(event['data']['id']));
        }
        expect(event['name'], isNot('extra_pedido'));
      }
      expect((await call('GET', '/api/local/events?after=${feed['cursor']}', {}, token))['events'], isEmpty);
    }
    await expectLater(call('PATCH', '/api/pedidos/${paid['id']}/agregar', {
      'productos': [{'producto_id': 1, 'cantidad': 1}]}, waiter), denied(403));
    expect((await call('GET', '/api/pedidos?estado=pagado'))['pedidos'], hasLength(2));
    expect((await call('GET', '/api/pedidos/${paid['id']}'))['pedido']['id'], paid['id']);
    expect((await call('GET', '/api/pedidos?scope=history'))['pedidos'], hasLength(4));
    // Closing a still-open old order removes it from the operating view without
    // revealing its historical payload through the event stream.
    final cursor = (await call('GET', '/api/local/events'))['cursor'];
    await call('PATCH', '/api/pedidos/${open['id']}/cancelar', {}, waiter);
    final updates = (await call('GET', '/api/local/events?after=$cursor', {}, waiter))['events'];
    expect(updates, contains({'name': 'pedido_eliminado', 'data': {'id': open['id']}}));
  });

  test('Moving a table updates pending extras atomically and keeps stale edits rejected', () async {
    final p = await order(); await ready(p['id']);
    await call('PATCH', '/api/pedidos/${p['id']}/agregar', {'productos': [{'producto_id': 1, 'cantidad': 1}]});
    final original = (await call('GET', '/api/pedidos/${p['id']}'))['pedido'];
    final cursor = (await call('GET', '/api/local/events'))['cursor'];
    final moved = (await call('PATCH', '/api/pedidos/${p['id']}/editar', {'mesa': 99, 'version': original['version']}))['pedido'];
    var extra = (await call('GET', '/api/extras'))['extras'].single;
    expect(extra['mesa'], 99); expect(extra['tipo'], 'llevar');
    expect(extra['items'], hasLength(1)); expect(extra['_done'], isEmpty);
    expect((await call('GET', '/api/local/events?after=$cursor'))['events'].map((e) => e['name']), contains('extras_actualizados'));
    await expectLater(call('PATCH', '/api/pedidos/${p['id']}/editar', {'mesa': 5, 'version': original['version']}), denied(409));
    // Invalid edits must roll back both the order and any changed extras.
    await expectLater(call('PATCH', '/api/pedidos/${p['id']}/editar', {'mesa': 5, 'version': moved['version'], 'items': []}), denied(409));
    extra = (await call('GET', '/api/extras'))['extras'].single;
    expect(extra['mesa'], 99);
    expect((await call('GET', '/api/pedidos/${p['id']}'))['pedido']['mesa'], 99);
    await call('PATCH', '/api/pedidos/${p['id']}/editar', {'mesa': 5, 'version': moved['version']});
    extra = (await call('GET', '/api/extras'))['extras'].single;
    expect(extra['mesa'], 5); expect(extra['tipo'], 'aqui');
    await call('PATCH', '/api/extras/${extra['id']}', {'done': true});
    expect((await call('POST', '/api/pedidos/cobrar', {'ids': [p['id']], 'total_esperado': 36, 'recibido': 40}))['total'], 36);
  });

  for (final background in [true, false]) {
    test('A stale ${background ? "background" : "foreground"} rejection cannot block a newly authenticated outbox entry', () async {
      final local = await database(), c = DelayedOrderClient(local, hub);
      servers.add(c);
      final token = await login(c), op = randomKey();
      final body = {'mesa': 2, 'productos': [{'producto_id': 1, 'cantidad': 1}]};
      await local.db.insert('outbox', {'id': op, 'user_id': 2, 'token': token,
        'path': '/api/pedidos', 'body': jsonEncode(body), 'status': 'pending', 'created': engine.now()});
      final Future<dynamic> sending = background ? c.sync() : c.request('POST', '/api/pedidos', body, token, op);
      try {
        await c.started.future.timeout(const Duration(seconds: 10));
        await call('POST', '/api/auth/logout', {}, token);
        final fresh = await login(c);
        expect(fresh, isNot(token));
        c.rejected.complete();
        final response = await sending;
        if (!background) { expect(response['blocked'], false); }
        final pending = (await local.db.query('outbox')).single;
        expect(pending['token'], fresh); expect(pending['status'], 'pending');
        expect(await c.localUser(fresh), 2);
        await expectLater(c.localUser(token), denied(401));
        await c.sync(); await c.sync();
        expect(await local.db.query('outbox'), isEmpty);
        expect(await engine.records(engine.db, 'orders'), hasLength(1));
      } finally {
        if (!c.rejected.isCompleted) { c.rejected.complete(); }
        await sending;
      }
    });
  }
}
