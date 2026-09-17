import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tres_pisos_app/local/menu_file.dart';
import 'package:tres_pisos_app/local/pos_engine.dart';
import 'package:tres_pisos_app/local/pos_server.dart';

class NoInternet extends HttpOverrides {
  final hosts = <String>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      LocalClient(super.createHttpClient(context), hosts);
}

class LocalClient implements HttpClient {
  final HttpClient delegate;
  final List<String> hosts;
  LocalClient(this.delegate, this.hosts);
  void check(Uri uri) {
    if (!['127.0.0.1', '::1'].contains(uri.host)) {
      throw StateError('Internet disabled for this test');
    }
    hosts.add(uri.host);
  }

  @override
  Future<HttpClientRequest> postUrl(Uri uri) async {
    check(uri);
    return delegate.postUrl(uri);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    check(uri);
    return delegate.getUrl(uri);
  }

  @override
  Duration? get connectionTimeout => delegate.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) {
    delegate.connectionTimeout = value;
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();
  test(
      'No Internet: four logins, two waiters, kitchen, permissions, payment and reconnection',
      () async {
    final network = NoInternet();
    await HttpOverrides.runWithHttpOverrides(() async {
      final blocked = HttpClient();
      await expectLater(blocked.getUrl(Uri.parse('https://example.invalid/')),
          throwsStateError);
      blocked.close(force: true);
      final databases = <Database>[];
      final servers = <PosServer>[];
      Future<PosEngine> database() async {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
            options: OpenDatabaseOptions(
                singleInstance: false,
                version: 2,
                onCreate: PosEngine.createSchema));
        databases.add(db);
        return PosEngine(db);
      }

      Matcher denied(int status) =>
          throwsA(isA<PosError>().having((e) => e.status, 'status', status));
      try {
        final pos = await database();
        await pos.bootstrap('admin', 'fixture-password');
        await pos.seedMenuIfEmpty(MenuFile.parse(
            await File('assets/menu/restaurante.json').readAsBytes()));
        final key = randomKey(), hubId = randomKey();
        final hub = PosServer(
            engine: pos,
            central: true,
            pairSecret: key,
            hubId: hubId,
            asset: (_) async => []);
        servers.add(hub);
        await hub.start(uiPort: 0, lanPort: 0);
        Future<Json> call(
                PosServer server, String method, String path, String? token,
                [Json body = const {}, String? op]) =>
            server.request(method, path, body, token, op ?? randomKey());
        final admin = (await call(hub, 'POST', '/api/auth/login', null, {
          'username': 'admin',
          'password': 'fixture-password'
        }))['token'] as String;
        for (final name in ['cocina', 'mesero1', 'mesero2']) {
          await call(hub, 'POST', '/api/auth/register', admin, {
            'username': name,
            'password': 'fixture-password',
            'role': name == 'cocina' ? 'cocina' : 'mesero'
          });
        }
        final kitchen = (await call(hub, 'POST', '/api/auth/login', null, {
          'username': 'cocina',
          'password': 'fixture-password'
        }))['token'] as String;
        final clients = <PosServer>[];
        final tokens = <String>[];
        final port = hub.lanServer!.port;
        for (var i = 1; i <= 2; i++) {
          final client = PosServer(
              engine: await database(),
              central: false,
              pairSecret: key,
              hubId: hubId,
              hub: Uri.parse('http://127.0.0.1:$port'),
              asset: (_) async => []);
          clients.add(client);
          servers.add(client);
          await expectLater(
              call(client, 'POST', '/api/auth/login', null,
                  {'username': 'mesero$i', 'password': 'wrong-password'}),
              denied(401));
          tokens.add((await call(client, 'POST', '/api/auth/login', null, {
            'username': 'mesero$i',
            'password': 'fixture-password'
          }))['token'] as String);
          expect(
              (await call(
                  client, 'GET', '/api/productos', tokens.last))['productos'],
              hasLength(54));
          await expectLater(
              call(client, 'GET', '/api/auth/usuarios', tokens.last),
              denied(403));
          await expectLater(
              call(client, 'GET', '/api/metricas/resumen', tokens.last),
              denied(403));
          await expectLater(
              call(client, 'POST', '/api/productos', tokens.last,
                  {'nombre': 'Prohibido', 'precio': 1}),
              denied(403));
        }
        await expectLater(
            call(hub, 'GET', '/api/local/backup', kitchen), denied(403));
        await expectLater(
            call(hub, 'POST', '/api/pedidos', kitchen, {
              'mesa': 1,
              'productos': [
                {'producto_id': 1, 'cantidad': 1}
              ]
            }),
            denied(403));
        final menu = await pos.records(pos.db, 'products');
        final taco = menu
            .singleWhere((p) => p['nombre'] == 'Taco de Carne al Pastor')['id'];
        final birria = menu.singleWhere((p) => p['nombre'] == 'Birria')['id'];
        await expectLater(
            call(hub, 'POST', '/api/pedidos', admin, {
              'mesa': 1,
              'productos': [
                {'producto_id': birria, 'cantidad': 1}
              ]
            }),
            denied(409));
        Json order(int table) => {
              'mesa': table,
              'productos': [
                {'producto_id': taco, 'cantidad': 2}
              ]
            };
        final placed = await Future.wait(List.generate(
            2,
            (i) => call(
                clients[i], 'POST', '/api/pedidos', tokens[i], order(i + 1))));
        final id = placed[0]['pedido']['id'] as int;
        await expectLater(
            call(clients[0], 'PUT', '/api/pedidos/$id/estado', tokens[0],
                {'estado': 'preparando'}),
            denied(403));
        await call(hub, 'PUT', '/api/pedidos/$id/estado', kitchen,
            {'estado': 'preparando'});
        await call(hub, 'PUT', '/api/pedidos/$id/estado', kitchen,
            {'estado': 'listo'});
        final payment = {
          'ids': [id],
          'total_esperado': 36,
          'recibido': 50
        };
        await expectLater(
            call(hub, 'POST', '/api/pedidos/cobrar', kitchen, payment),
            denied(403));
        expect(
            (await call(clients[0], 'POST', '/api/pedidos/cobrar', tokens[0],
                payment))['cambio'],
            14);
        await hub.lanServer!.close(force: true);
        hub.lanServer = null;
        expect(
            (await call(
                clients[0], 'GET', '/api/productos', tokens[0]))['cached'],
            true);
        expect(
            (await call(
                clients[0], 'GET', '/api/auth/me', tokens[0]))['cached'],
            true);
        await expectLater(
            call(clients[0], 'POST', '/api/pedidos/cobrar', tokens[0], payment),
            denied(503));
        final pending = randomKey();
        expect(
            (await call(clients[0], 'POST', '/api/pedidos', tokens[0], order(3),
                pending))['queued'],
            true);
        expect(await clients[0].engine.db.query('outbox'), hasLength(1));
        hub.lanServer =
            await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        hub.lanServer!.listen((r) => hub.handle(r, true));
        await clients[0].sync();
        await clients[0].sync();
        expect(await clients[0].engine.db.query('outbox'), isEmpty);
        expect(await pos.records(pos.db, 'orders'), hasLength(3));
        expect(
            (await call(hub, 'GET', '/api/metricas/resumen', admin))['dia']
                ['total_ventas'],
            36);
        expect(jsonEncode(await pos.db.query('receipts')),
            isNot(contains('fixture-password')));
        expect(network.hosts, isNotEmpty);
        expect(network.hosts.toSet(), {'127.0.0.1'});
      } finally {
        for (final server in servers.reversed) {
          await server.stop();
        }
        for (final db in databases.reversed) {
          await db.close();
        }
      }
    }, network);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
