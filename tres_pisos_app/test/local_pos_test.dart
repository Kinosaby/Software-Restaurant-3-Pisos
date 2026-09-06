import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tres_pisos_app/local/pos_engine.dart';
import 'package:tres_pisos_app/local/pos_server.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late PosEngine pos;
  String admin = '';
  late String waiter, kitchen;
  Matcher rejects(int code) =>
      throwsA(isA<PosError>().having((e) => e.status, 'status', code));
  Future<Json> call(
    String method,
    String path, [
    Json body = const {},
    String? token,
    String? id,
  ]) => pos.call(
    method,
    Uri.parse(path),
    body: body,
    token: token ?? admin,
    operationId: id ?? randomKey(),
  );
  Future<String> login(String user) async => (await call(
    'POST',
    '/api/auth/login',
    {'username': user, 'password': 'test-password'},
  ))['token'];
  Future<Json> order([int count = 1]) async =>
      (await call('POST', '/api/pedidos', {
        'mesa': 1,
        'comensal': 'Ana',
        'productos': [
          {'producto_id': 1, 'cantidad': count, 'nota': 'Sin cebolla'},
        ],
      }, waiter))['pedido'];
  Future<void> ready(int id) async {
    await call('PUT', '/api/pedidos/$id/estado', {
      'estado': 'preparando',
    }, kitchen);
    await call('PUT', '/api/pedidos/$id/estado', {'estado': 'listo'}, kitchen);
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: PosEngine.createSchema,
      ),
    );
    pos = PosEngine(db, clock: () => DateTime.utc(2026, 9, 6, 19));
    await pos.bootstrap('admin', 'test-password');
    admin = await login('admin');
    for (final role in ['mesero', 'cocina']) {
      await call('POST', '/api/auth/register', {
        'username': role,
        'password': 'test-password',
        'role': role,
      });
    }
    waiter = await login('mesero');
    kitchen = await login('cocina');
    await call('POST', '/api/productos', {
      'nombre': 'Taco',
      'precio': '12.50',
      'categoria': 'Tacos',
    });
  });
  tearDown(() async => db.close());
  test('Roles, passwords, last administrator and session revocation', () async {
    await expectLater(
      call('GET', '/api/auth/usuarios', {}, waiter),
      rejects(403),
    );
    await expectLater(
      call('POST', '/api/productos', {'nombre': 'X', 'precio': 1}, kitchen),
      rejects(403),
    );
    await expectLater(
      call('PUT', '/api/auth/1', {'role': 'mesero'}),
      rejects(409),
    );
    await expectLater(
      call('POST', '/api/auth/login', {'username': 'admin', 'password': 'bad'}),
      rejects(401),
    );
    await call('PUT', '/api/auth/2', {'password': 'new-password'});
    await expectLater(call('GET', '/api/auth/me', {}, waiter), rejects(401));
  });
  test(
    'Diner batches are atomic and concurrent retries deliver exactly once',
    () async {
      final body = {
            'pedidos': [
              {
                'mesa': 3,
                'comensal': 'A',
                'productos': [
                  {'producto_id': 1, 'cantidad': 2},
                ],
              },
              {
                'mesa': 3,
                'comensal': 'B',
                'productos': [
                  {'producto_id': 1, 'cantidad': 1},
                ],
              },
            ],
          },
          op = randomKey();
      final results = await Future.wait(
        List.generate(
          3,
          (_) => call('POST', '/api/pedidos/lote', body, waiter, op),
        ),
      );
      expect(results[0], results[1]);
      expect((await call('GET', '/api/pedidos'))['pedidos'], hasLength(2));
      await expectLater(
        call('POST', '/api/pedidos/lote', {
          'pedidos': [
            (body['pedidos'] as List).first,
            {
              'mesa': 4,
              'productos': [
                {'producto_id': 999, 'cantidad': 1},
              ],
            },
          ],
        }, waiter),
        rejects(404),
      );
      expect((await call('GET', '/api/pedidos'))['pedidos'], hasLength(2));
      await expectLater(
        call('POST', '/api/pedidos/lote', {'pedidos': []}, waiter, op),
        rejects(409),
      );
    },
  );
  test('Original prices survive edits and stale edits are rejected', () async {
    final p = await order(2);
    await call('PUT', '/api/productos/1', {'precio': '99.99'});
    final edit = {
      'version': p['version'],
      'mesa': 8,
      'items': [
        {
          'detalle_id': p['productos'][0]['id'],
          'cantidad': 3,
          'nota': 'Bien dorado',
        },
      ],
    };
    final changed = (await call(
      'PATCH',
      '/api/pedidos/${p['id']}/editar',
      edit,
      waiter,
    ))['pedido'];
    expect(changed['total'], 37.5);
    expect(changed['mesa'], 8);
    await expectLater(
      call('PATCH', '/api/pedidos/${p['id']}/editar', edit, waiter),
      rejects(409),
    );
    await expectLater(
      call('PUT', '/api/pedidos/${p['id']}/estado', {
        'estado': 'listo',
      }, waiter),
      rejects(403),
    );
  });
  test(
    'Kitchen item checks and extras persist; payment waits for extras',
    () async {
      final p = await order(), id = p['id'];
      await call('PATCH', '/api/pedidos/$id/item', {
        'detalle_id': p['productos'][0]['id'],
        'listo': true,
      }, kitchen);
      expect(
        (await call(
          'GET',
          '/api/pedidos/$id',
        ))['pedido']['productos'][0]['listo'],
        true,
      );
      await ready(id);
      await call('PATCH', '/api/pedidos/$id/agregar', {
        'productos': [
          {'producto_id': 1, 'cantidad': 2},
        ],
      }, waiter);
      final ex = (await call('GET', '/api/extras'))['extras'][0];
      await call('PATCH', '/api/extras/${ex['id']}', {
        'item': 0,
        'listo': true,
      }, kitchen);
      expect(
        (await call('GET', '/api/extras'))['extras'][0]['_done']['0'],
        true,
      );
      final payment = {
        'ids': [id],
        'total_esperado': 37.5,
        'recibido': 50,
      };
      await expectLater(
        call('POST', '/api/pedidos/cobrar', payment, waiter),
        rejects(409),
      );
      await call('PATCH', '/api/extras/${ex['id']}', {'done': true}, kitchen);
      expect(
        (await call('POST', '/api/pedidos/cobrar', payment, waiter))['cambio'],
        12.5,
      );
    },
  );
  test(
    'Combined cash payment is atomic; paid accounts cannot be reopened',
    () async {
      final a = await order(2), b = await order();
      await ready(a['id']);
      await ready(b['id']);
      await expectLater(
        call('POST', '/api/pedidos/cobrar', {
          'ids': [a['id'], b['id']],
          'total_esperado': 25,
          'recibido': 100,
        }, waiter),
        rejects(409),
      );
      expect(
        (await call('GET', '/api/pedidos/${a['id']}'))['pedido']['estado'],
        'listo',
      );
      final payment = {
            'ids': [a['id'], b['id']],
            'total_esperado': 37.5,
            'recibido': 50,
          },
          op = randomKey();
      final paid = await call(
        'POST',
        '/api/pedidos/cobrar',
        payment,
        waiter,
        op,
      );
      expect(
        await call('POST', '/api/pedidos/cobrar', payment, waiter, op),
        paid,
      );
      expect(paid['cambio'], 12.5);
      final next = await call('PATCH', '/api/pedidos/${a['id']}/agregar', {
        'productos': [
          {'producto_id': 1, 'cantidad': 1},
        ],
      }, waiter);
      expect(next['nueva_cuenta'], true);
      expect(next['pedido']['id'], isNot(a['id']));
      expect(
        (await call('GET', '/api/pedidos/${a['id']}'))['pedido']['estado'],
        'pagado',
      );
      expect(
        (await call('GET', '/api/metricas/resumen'))['dia']['total_ventas'],
        37.5,
      );
    },
  );
  test('601 orders, history pagination and complete backup recovery', () async {
    final watch = Stopwatch()..start();
    final op = randomKey(),
        first = {
          'mesa': 2,
          'productos': [
            {'producto_id': 1, 'cantidad': 1},
          ],
        };
    await call('POST', '/api/pedidos', first, waiter, op);
    for (var n = 1; n < 601; n++) {
      await order();
    }
    final page = await call('GET', '/api/pedidos?scope=history&page=0');
    expect(page['pedidos'], hasLength(100));
    expect(page['hasMore'], true);
    expect(
      (await call('GET', '/api/pedidos?scope=history&page=6'))['pedidos'],
      hasLength(1),
    );
    final backup = await call('GET', '/api/local/backup');
    final restoredDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: PosEngine.createSchema,
        singleInstance: false,
      ),
    );
    try {
      final restored = PosEngine(restoredDb);
      await restored.restore(backup);
      final token = (await restored.call(
        'POST',
        Uri.parse('/api/auth/login'),
        body: {'username': 'mesero', 'password': 'test-password'},
      ))['token'];
      expect(
        (await restored.call(
          'POST',
          Uri.parse('/api/pedidos'),
          body: first,
          token: token,
          operationId: op,
        ))['pedido']['id'],
        1,
      );
      expect(await restored.records(restoredDb, 'orders'), hasLength(601));
      await expectLater(restored.restore(backup), rejects(409));
    } finally {
      await restoredDb.close();
    }
    // ignore: avoid_print
    print(
      '601 orders and backup/restore on test host: ${watch.elapsedMilliseconds} ms',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
  test(
    'Encrypted LAN, disk queue, process restart and lost acknowledgement',
    () async {
      final secret = randomKey(), hubId = randomKey();
      final hub = PosServer(
        engine: pos,
        central: true,
        pairSecret: secret,
        hubId: hubId,
        asset: (_) async => utf8.encode('local'),
      );
      await hub.start(uiPort: 0, lanPort: 0);
      final temp = await Directory.systemTemp.createTemp('pos-queue-'),
          path = '${temp.path}/client.db';
      Database? clientDb;
      PosServer? client;
      try {
        clientDb = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: PosEngine.createSchema,
          ),
        );
        final endpoint = Uri.parse('http://127.0.0.1:${hub.lanServer!.port}');
        client = PosServer(
          engine: PosEngine(clientDb),
          central: false,
          pairSecret: secret,
          hubId: hubId,
          hub: endpoint,
          asset: (_) async => [],
        );
        final token =
            (await client.request(
                  'POST',
                  '/api/auth/login',
                  {'username': 'mesero', 'password': 'test-password'},
                  null,
                  randomKey(),
                ))['token']
                as String;
        final wrong = PosServer(
          engine: PosEngine(clientDb),
          central: false,
          pairSecret: randomKey(),
          hubId: hubId,
          hub: endpoint,
          asset: (_) async => [],
        );
        await expectLater(
          wrong.remote({'method': 'GET', 'path': '/api/local/ping'}),
          rejects(403),
        );
        await wrong.stop();
        final body = {
              'mesa': 5,
              'productos': [
                {'producto_id': 1, 'cantidad': 2},
              ],
            },
            op = randomKey();
        await call('POST', '/api/pedidos', body, token, op);
        final port = hub.lanServer!.port;
        await hub.lanServer!.close(force: true);
        hub.lanServer = null;
        expect(
          (await client.request(
            'POST',
            '/api/pedidos',
            body,
            token,
            op,
          ))['queued'],
          true,
        );
        expect(await clientDb.query('outbox'), hasLength(1));
        await client.stop();
        await clientDb.close();
        clientDb = await databaseFactoryFfi.openDatabase(path);
        client = PosServer(
          engine: PosEngine(clientDb),
          central: false,
          pairSecret: secret,
          hubId: hubId,
          hub: endpoint,
          asset: (_) async => [],
        );
        hub.lanServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        hub.lanServer!.listen((r) => hub.handle(r, true));
        await client.sync();
        expect(await clientDb.query('outbox'), isEmpty);
        expect((await call('GET', '/api/pedidos'))['pedidos'], hasLength(1));
      } finally {
        await client?.stop();
        await clientDb?.close();
        await hub.stop();
        await temp.delete(recursive: true);
      }
    },
  );
}
