import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tres_pisos_app/local/local_database.dart';
import 'package:tres_pisos_app/local/pos_engine.dart';
import 'package:tres_pisos_app/local/pos_server.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Offline Operations & Outbox Queueing Tests', () {
    final databases = <Database>[];
    final servers = <PosServer>[];
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_offline_test_');
    });

    tearDown(() async {
      for (final server in servers.reversed) {
        await server.stop();
      }
      servers.clear();
      for (final db in databases.reversed) {
        await db.close();
      }
      databases.clear();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<PosEngine> createEngine([String? path]) async {
      final dbPath = path ?? inMemoryDatabasePath;
      final db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 3,
          onCreate: PosEngine.createSchema,
          onUpgrade: PosEngine.upgradeSchema,
        ),
      );
      databases.add(db);
      return PosEngine(db);
    }

    test('PATCH /api/pedidos/:id/agregar enqueues in outbox when offline and returns queued: true', () async {
      final hubEngine = await createEngine();
      await hubEngine.bootstrap('admin', 'adminpass123');
      final hubSecret = randomKey();
      final hubId = randomKey();
      final hub = PosServer(
        engine: hubEngine,
        central: true,
        pairSecret: hubSecret,
        hubId: hubId,
        asset: (_) async => [],
      );
      servers.add(hub);
      await hub.start(uiPort: 0, lanPort: 0);

      final adminLogin = await hub.request('POST', '/api/auth/login', {'username': 'admin', 'password': 'adminpass123'}, null, randomKey());
      final adminToken = adminLogin['token'] as String;

      await hub.request('POST', '/api/auth/register', {'username': 'mesero1', 'password': 'meseropass', 'role': 'mesero'}, adminToken, randomKey());
      final prodRes = await hub.request('POST', '/api/productos', {'nombre': 'Tacos al Pastor', 'precio': 25.0, 'categoria': 'Tacos', 'activo': true}, adminToken, randomKey());
      final prodId = prodRes['producto']['id'] as int;

      final clientEngine = await createEngine();
      final client = PosServer(
        engine: clientEngine,
        central: false,
        pairSecret: hubSecret,
        hubId: hubId,
        hub: Uri.parse('http://127.0.0.1:${hub.lanServer!.port}'),
        asset: (_) async => [],
      );
      servers.add(client);

      final clientLogin = await client.request('POST', '/api/auth/login', {'username': 'mesero1', 'password': 'meseropass'}, null, randomKey());
      final clientToken = clientLogin['token'] as String;

      final createRes = await client.request(
        'POST',
        '/api/pedidos',
        {
          'mesa': 4,
          'productos': [{'producto_id': prodId, 'cantidad': 2}],
        },
        clientToken,
        randomKey(),
      );
      expect(createRes['pedido'], isNotNull);
      final orderId = createRes['pedido']['id'] as int;

      final port = hub.lanServer!.port;
      await hub.lanServer!.close(force: true);
      hub.lanServer = null;

      final addOpId = randomKey();
      final addRes = await client.request(
        'PATCH',
        '/api/pedidos/$orderId/agregar',
        {
          'productos': [{'producto_id': prodId, 'cantidad': 3}],
        },
        clientToken,
        addOpId,
      );

      expect(addRes['queued'], isTrue);
      expect(addRes['operation_id'], equals(addOpId));

      final outboxRows = await clientEngine.db.query('outbox', where: 'id=?', whereArgs: [addOpId]);
      expect(outboxRows, hasLength(1));
      final outboxItem = outboxRows.first;
      expect(outboxItem['path'], equals('/api/pedidos/$orderId/agregar'));
      expect(outboxItem['status'], equals('pending'));

      hub.lanServer = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      hub.lanServer!.listen((r) => hub.handle(r, true));

      await client.sync();

      expect(await clientEngine.db.query('outbox'), isEmpty);

      final updatedOrder = await hubEngine.record(hubEngine.db, 'orders', orderId);
      expect(updatedOrder['productos'], hasLength(2));
      expect(updatedOrder['total'], equals(125.0));
    });

    test('POST /api/pedidos/cobrar enqueues in outbox when offline and syncs payment', () async {
      final hubEngine = await createEngine();
      await hubEngine.bootstrap('admin', 'adminpass123');
      final hubSecret = randomKey();
      final hubId = randomKey();
      final hub = PosServer(
        engine: hubEngine,
        central: true,
        pairSecret: hubSecret,
        hubId: hubId,
        asset: (_) async => [],
      );
      servers.add(hub);
      await hub.start(uiPort: 0, lanPort: 0);

      final adminLogin = await hub.request('POST', '/api/auth/login', {'username': 'admin', 'password': 'adminpass123'}, null, randomKey());
      final adminToken = adminLogin['token'] as String;

      await hub.request('POST', '/api/auth/register', {'username': 'mesero2', 'password': 'meseropass2', 'role': 'mesero'}, adminToken, randomKey());
      final prodRes = await hub.request('POST', '/api/productos', {'nombre': 'Enchiladas Suizas', 'precio': 50.0, 'categoria': 'Enchiladas', 'activo': true}, adminToken, randomKey());
      final prodId = prodRes['producto']['id'] as int;

      final clientEngine = await createEngine();
      final client = PosServer(
        engine: clientEngine,
        central: false,
        pairSecret: hubSecret,
        hubId: hubId,
        hub: Uri.parse('http://127.0.0.1:${hub.lanServer!.port}'),
        asset: (_) async => [],
      );
      servers.add(client);

      final clientLogin = await client.request('POST', '/api/auth/login', {'username': 'mesero2', 'password': 'meseropass2'}, null, randomKey());
      final clientToken = clientLogin['token'] as String;

      final createRes = await client.request(
        'POST',
        '/api/pedidos',
        {
          'mesa': 2,
          'productos': [{'producto_id': prodId, 'cantidad': 2}],
        },
        clientToken,
        randomKey(),
      );
      final orderId = createRes['pedido']['id'] as int;

      await hub.request('PUT', '/api/pedidos/$orderId/estado', {'estado': 'preparando'}, adminToken, randomKey());
      await hub.request('PUT', '/api/pedidos/$orderId/estado', {'estado': 'listo'}, adminToken, randomKey());

      final port = hub.lanServer!.port;
      await hub.lanServer!.close(force: true);
      hub.lanServer = null;

      final payOpId = randomKey();
      final payRes = await client.request(
        'POST',
        '/api/pedidos/cobrar',
        {
          'ids': [orderId],
          'total_esperado': 100.0,
          'recibido': 150.0,
        },
        clientToken,
        payOpId,
      );

      expect(payRes['queued'], isTrue);
      expect(payRes['operation_id'], equals(payOpId));

      final outboxRows = await clientEngine.db.query('outbox', where: 'id=?', whereArgs: [payOpId]);
      expect(outboxRows, hasLength(1));
      expect(outboxRows.first['path'], equals('/api/pedidos/cobrar'));
      expect(outboxRows.first['status'], equals('pending'));

      hub.lanServer = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      hub.lanServer!.listen((r) => hub.handle(r, true));

      await client.sync();

      expect(await clientEngine.db.query('outbox'), isEmpty);
      final paidOrder = await hubEngine.record(hubEngine.db, 'orders', orderId);
      expect(paidOrder['estado'], equals('pagado'));

      final sales = await hubEngine.db.query('records', where: 'kind=? AND id=?', whereArgs: ['sales', orderId]);
      expect(sales, hasLength(1));
    });

    test('SQLite concurrent transactions execute without locking with busy_timeout configured', () async {
      final dbPath = '${tempDir.path}/concurrent_test.db';

      final db1 = await openPosDatabase(dbPath);
      databases.add(db1);

      final timeoutRow = await db1.rawQuery('PRAGMA busy_timeout');
      expect(timeoutRow, isNotEmpty);
      final timeoutValue = timeoutRow.first.values.first as int;
      expect(timeoutValue, greaterThanOrEqualTo(1000));

      final db2 = await openPosDatabase(dbPath);
      databases.add(db2);

      final futures = <Future<void>>[];
      for (var i = 0; i < 10; i++) {
        final current = i;
        final targetDb = (current % 2 == 0) ? db1 : db2;
        futures.add(targetDb.transaction((tx) async {
          await tx.insert(
            'settings',
            {'key': 'concurrent_key_$current', 'value': 'val_$current'},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await Future.delayed(const Duration(milliseconds: 10));
        }));
      }

      await expectLater(Future.wait(futures), completes);

      final totalSettings = await db1.query('settings', where: "key LIKE 'concurrent_key_%'");
      expect(totalSettings, hasLength(10));
    });
  });
}
