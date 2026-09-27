import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/central/central.dart';
import 'package:tres_pisos_app/central/seguridad.dart';
import 'package:tres_pisos_app/central/servidor_central.dart';

const menu = [
  {'nombre': 'Tacos de Pastor', 'precio': '42.00', 'categoria': 'Tacos', 'activo': true},
  {'nombre': 'Refresco', 'precio': '22.00', 'categoria': 'Bebidas', 'activo': true},
  {'nombre': 'Birria', 'precio': '100.00', 'categoria': 'Platillos', 'activo': false},
];

/// El servidor registra el WebSocket un instante después de que el cliente conecta.
Future<void> hastaQue(bool Function() condicion) async {
  for (var i = 0; i < 100 && !condicion(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late Directory carpeta;
  late Central central;
  final eventos = <(String, Map<String, dynamic>)>[];

  Future<Central> abrir() async {
    final c = await Central.abrir(carpeta, iteraciones: 1000);
    c.emitir = (evento, datos) => eventos.add((evento, datos));
    return c;
  }

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('central_test');
    eventos.clear();
    central = await abrir();
    await central.inicializar(admin: 'admin', password: 'secreto1', menu: menu);
  });

  tearDown(() async {
    await central.cerrar();
    await carpeta.delete(recursive: true);
  });

  Future<UsuarioCentral> usuario(String nombre, String rol) async {
    await central.crearUsuario({'username': nombre, 'password': 'clave123', 'role': rol});
    final login = await central.login(nombre, 'clave123');
    return central.autenticar(login['token'] as String)!;
  }

  Map<String, dynamic> pedidoDe(int productoId, {int cantidad = 1, String? nota, int mesa = 3}) => {
        'mesa': mesa,
        'tipo': 'aqui',
        'productos': [
          {'producto_id': productoId, 'cantidad': cantidad, 'nota': ?nota},
        ],
      };

  group('instalación y sesiones', () {
    test('crea el admin, el código de enlace y carga el menú', () async {
      expect(central.inicializada, isTrue);
      expect(central.codigoEnlace, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$')));
      expect(central.listarProductos(), hasLength(3));
      expect(central.enlaceValido(central.codigoEnlace.toLowerCase().replaceAll('-', ' ')), isTrue);
      await expectLater(
        central.inicializar(admin: 'otro', password: 'secreto1'),
        throwsA(isA<ErrorCentral>().having((e) => e.status, 'status', 409)),
      );
    });

    test('login correcto e incorrecto', () async {
      final login = await central.login('ADMIN', 'secreto1');
      expect(central.autenticar(login['token'] as String)?.rol, 'admin');
      await expectLater(central.login('admin', 'mala'), throwsA(isA<ErrorCentral>()));
    });

    test('cambiar la contraseña invalida los tokens anteriores', () async {
      await central.crearUsuario({'username': 'luis', 'password': 'clave123', 'role': 'mesero'});
      final token = (await central.login('luis', 'clave123'))['token'] as String;
      final id = central.autenticar(token)!.id;

      await central.actualizarUsuario(id, {'username': 'luis', 'role': 'mesero', 'password': 'nueva123'});
      expect(central.autenticar(token), isNull);
      expect(central.autenticar((await central.login('luis', 'nueva123'))['token'] as String), isNotNull);
    });

    test('siempre queda un administrador', () async {
      final admin = central.autenticar((await central.login('admin', 'secreto1'))['token'] as String)!;
      await expectLater(
        central.actualizarUsuario(admin.id, {'username': 'admin', 'role': 'mesero'}),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'LAST_ADMIN')),
      );
      await expectLater(central.eliminarUsuario(admin.id, actorId: admin.id), throwsA(isA<ErrorCentral>()));
    });
  });

  group('pedidos', () {
    test('crea el pedido con el precio del momento y avisa a cocina', () async {
      final mesero = await usuario('luis', 'mesero');
      final pedido = await central.crearPedido(pedidoDe(1, cantidad: 2, nota: 'sin cebolla'), usuario: mesero);

      expect(pedido['estado'], 'pendiente');
      expect(pedido['total'], 84.0);
      expect(pedido['mesero'], 'luis');
      expect(eventos.single.$1, 'nuevo_pedido');

      // Subir el precio no cambia la cuenta ya abierta.
      await central.actualizarProducto(1, {'nombre': 'Tacos de Pastor', 'precio': 50, 'categoria': 'Tacos'});
      expect(central.obtenerPedido(pedido['id'] as int)['total'], 84.0);
    });

    test('un reintento con la misma operación no duplica el pedido', () async {
      final mesero = await usuario('luis', 'mesero');
      final a = await central.crearPedido(pedidoDe(1), usuario: mesero, operacion: 'op-1');
      final b = await central.crearPedido(pedidoDe(1), usuario: mesero, operacion: 'op-1');
      expect(b['id'], a['id']);
      expect(central.listarPedidos(), hasLength(1));
    });

    test('rechaza productos inactivos, mesa inválida y pedidos vacíos', () async {
      final mesero = await usuario('luis', 'mesero');
      await expectLater(central.crearPedido(pedidoDe(3), usuario: mesero), throwsA(isA<ErrorCentral>()));
      await expectLater(central.crearPedido(pedidoDe(1, mesa: 0), usuario: mesero), throwsA(isA<ErrorCentral>()));
      await expectLater(
        central.crearPedido({'mesa': 1, 'productos': []}, usuario: mesero),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'EMPTY_ORDER')),
      );
    });

    test('agregar: suma iguales, separa notas distintas y avisa extras de pedidos listos', () async {
      final mesero = await usuario('luis', 'mesero');
      final cocina = await usuario('chef', 'cocina');
      final id = (await central.crearPedido(pedidoDe(1), usuario: mesero))['id'] as int;

      await central.agregarProductos(id, pedidoDe(1), usuario: mesero);
      await central.agregarProductos(id, pedidoDe(1, nota: 'dorados'), usuario: mesero);
      var items = central.obtenerPedido(id)['productos'] as List;
      expect(items.map((i) => (i['cantidad'], i['nota'])), [(2, null), (1, 'dorados')]);

      await central.cambiarEstado(id, 'listo', usuario: cocina);
      eventos.clear();
      await central.agregarProductos(id, pedidoDe(2), usuario: mesero);
      expect(eventos.map((e) => e.$1), ['extra_pedido', 'pedido_actualizado']);
      expect((eventos.first.$2['items'] as List).single['nombre'], 'Refresco');
      items = central.obtenerPedido(id)['productos'] as List;
      expect(items, hasLength(3));
    });

    test('un extra sobre un pedido listo queda pendiente hasta que cocina lo termina', () async {
      final mesero = await usuario('luis', 'mesero');
      final cocina = await usuario('chef', 'cocina');
      final id = (await central.crearPedido(pedidoDe(1), usuario: mesero))['id'] as int;
      await central.cambiarEstado(id, 'listo', usuario: cocina);

      // Mismo producto que ya se sirvió: va en renglón aparte, marcado como extra.
      await central.agregarProductos(id, pedidoDe(1), usuario: mesero);
      await central.agregarProductos(id, pedidoDe(1), usuario: mesero);
      var pedido = central.obtenerPedido(id);
      var items = pedido['productos'] as List;
      expect(pedido['estado'], 'listo');
      expect(items.map((i) => (i['cantidad'], i.containsKey('extra_desde'))), [(1, false), (2, true)]);

      // La marca sobrevive a un reinicio de la central.
      await central.cerrar();
      central = await abrir();
      expect((central.obtenerPedido(id)['productos'] as List).last['extra_desde'], isNotNull);

      eventos.clear();
      await central.cambiarEstado(id, 'listo', usuario: cocina);
      pedido = central.obtenerPedido(id);
      items = pedido['productos'] as List;
      expect(items.any((i) => i.containsKey('extra_desde')), isFalse);
      expect(eventos.single.$1, 'pedido_actualizado');
      expect(pedido['total'], 126.0, reason: 'el extra se cobra con la cuenta');
    });

    test('agregar a una cuenta pagada abre una cuenta nueva', () async {
      final mesero = await usuario('luis', 'mesero');
      final id = (await central.crearPedido(pedidoDe(1), usuario: mesero))['id'] as int;
      await central.cambiarEstado(id, 'pagado', usuario: mesero);

      final nueva = await central.agregarProductos(id, pedidoDe(2), usuario: mesero);
      expect(nueva['id'], isNot(id));
      expect(nueva['estado'], 'pendiente');
      expect(nueva['mesa'], 3);
      expect(central.obtenerPedido(id)['total'], 42.0, reason: 'la venta cobrada no cambia');
    });

    test('editar: quita renglones, cambia mesa y no deja el pedido vacío', () async {
      final mesero = await usuario('luis', 'mesero');
      final pedido = await central.crearPedido({
        'mesa': 2,
        'productos': [
          {'producto_id': 1, 'cantidad': 2},
          {'producto_id': 2, 'cantidad': 1},
        ],
      }, usuario: mesero);
      final id = pedido['id'] as int;
      final items = pedido['productos'] as List;

      final editado = await central.editarPedido(id, {
        'mesa': 7,
        'items': [
          {'detalle_id': items[1]['id'], 'cantidad': 0},
        ],
      });
      expect(editado['mesa'], 7);
      expect(editado['total'], 84.0);

      await expectLater(
        central.editarPedido(id, {
          'items': [
            {'detalle_id': items[0]['id'], 'cantidad': 0},
          ],
        }),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'EMPTY_ORDER')),
      );
    });

    test('cocina prepara y marca listo pero no cobra; cobrar registra la venta', () async {
      final mesero = await usuario('luis', 'mesero');
      final cocina = await usuario('chef', 'cocina');
      final id = (await central.crearPedido(pedidoDe(1, cantidad: 3), usuario: mesero))['id'] as int;

      await central.cambiarEstado(id, 'preparando', usuario: cocina);
      await central.cambiarEstado(id, 'listo', usuario: cocina);
      await expectLater(
        central.cambiarEstado(id, 'pagado', usuario: cocina),
        throwsA(isA<ErrorCentral>().having((e) => e.status, 'status', 403)),
      );
      await central.cambiarEstado(id, 'pagado', usuario: mesero);
      await expectLater(central.cambiarEstado(id, 'pendiente', usuario: mesero), throwsA(isA<ErrorCentral>()));

      final resumen = central.resumen();
      expect((resumen['dia'] as Map)['total_ventas'], 126.0);
      expect(central.ventasPorDia(7).single['total'], 126.0);
      expect((resumen['productosTop'] as List).first, {'nombre': 'Tacos de Pastor', 'total_pedido': 3});
    });
  });

  group('cobro y pago mixto', () {
    test('repartir un pago mixto entre varias cuentas cuadra al centavo', () {
      expect(repartirPago([100, 50.5, 30], 120.25), [
        (efectivo: 100.0, tarjeta: 0.0),
        (efectivo: 20.25, tarjeta: 30.25),
        (efectivo: 0.0, tarjeta: 30.0),
      ]);
      expect(repartirPago([42], 0), [(efectivo: 0.0, tarjeta: 42.0)]);
    });

    test('cobrar una cuenta lista en mixto la cierra y registra el desglose', () async {
      final mesero = await usuario('luis', 'mesero');
      final cocina = await usuario('chef', 'cocina');
      final id = (await central.crearPedido(pedidoDe(1, cantidad: 3), usuario: mesero))['id'] as int;
      await central.cambiarEstado(id, 'listo', usuario: cocina);

      final cobrados = await central.cobrar({
        'pedidos': [id],
        'efectivo': 26,
        'tarjeta': 100,
      });
      expect(cobrados.single['estado'], 'pagado');
      expect((cobrados.single['pago'] as Map)['tarjeta'], 100);

      final dia = central.resumen()['dia'] as Map;
      expect((dia['total_ventas'], dia['efectivo'], dia['tarjeta'], dia['sin_desglose']), (126.0, 26.0, 100.0, 0.0));
      final venta = central.ventasPorDia(7).single;
      expect((venta['total'], venta['efectivo'], venta['tarjeta']), (126.0, 26.0, 100.0));
    });

    test('efectivo y tarjeta deben sumar el total y no se cobra dos veces', () async {
      final mesero = await usuario('luis', 'mesero');
      final id = (await central.crearPedido(pedidoDe(1), usuario: mesero))['id'] as int;
      await expectLater(
        central.cobrar({'pedidos': [id], 'efectivo': 20, 'tarjeta': 20}),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'PAGO_INCOMPLETO')),
      );
      await expectLater(
        central.cobrar({'pedidos': [id], 'efectivo': -2, 'tarjeta': 44}),
        throwsA(isA<ErrorCentral>().having((e) => e.status, 'status', 400)),
      );
      await central.cobrar({'pedidos': [id], 'efectivo': 42});
      await expectLater(
        central.cobrar({'pedidos': [id], 'efectivo': 42}),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'ALREADY_PAID')),
      );
      expect(central.ventasPorDia(7).single['pedidos'], 1);
    });

    test('cobrar antes de que cocina termine: cocina lo sigue viendo y al marcarlo listo se cierra', () async {
      final mesero = await usuario('luis', 'mesero');
      final cocina = await usuario('chef', 'cocina');
      final a = (await central.crearPedido(pedidoDe(1), usuario: mesero))['id'] as int;
      final b = (await central.crearPedido(pedidoDe(2), usuario: mesero))['id'] as int;
      await central.cambiarEstado(b, 'preparando', usuario: cocina);

      // Mesa completa (42 + 22) en mixto: el efectivo cubre la primera cuenta y parte de la segunda.
      final cobrados = await central.cobrar({
        'pedidos': [a, b],
        'efectivo': 50,
        'tarjeta': 14,
      });
      expect(cobrados.map((p) => p['estado']), ['pendiente', 'preparando'], reason: 'siguen en cocina');
      expect(cobrados.map((p) => (p['pago'] as Map)['efectivo']), [42, 8]);
      expect((central.resumen()['dia'] as Map)['total_ventas'], 64.0, reason: 'la venta cuenta desde el cobro');

      // Ya cobrado: no se cancela ni se cambian sus productos; lo que se agregue va en cuenta nueva.
      await expectLater(
        central.cambiarEstado(a, 'cancelado', usuario: cocina),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'ALREADY_PAID')),
      );
      final items = central.obtenerPedido(a)['productos'] as List;
      await expectLater(
        central.editarPedido(a, {
          'items': [
            {'detalle_id': items.first['id'], 'cantidad': 5},
          ],
        }),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'ALREADY_PAID')),
      );
      final nueva = await central.agregarProductos(a, pedidoDe(2), usuario: mesero);
      expect(nueva['id'], isNot(a));
      expect(nueva['pago'], isNull);

      await central.cambiarEstado(a, 'preparando', usuario: cocina);
      expect(central.obtenerPedido(a)['pago'], isNotNull, reason: 'el pago se conserva al avanzar');
      eventos.clear();
      final listo = await central.cambiarEstado(a, 'listo', usuario: cocina);
      expect(listo['estado'], 'pagado');
      expect(eventos.single.$2['_accion'], 'listo_pagado');
      expect(central.ventasPorDia(7).single['pedidos'], 2, reason: 'no se registra otra venta');
    });

    test('una cuenta lista con un extra en cocina se cobra pero sigue abierta hasta terminarlo', () async {
      final mesero = await usuario('luis', 'mesero');
      final cocina = await usuario('chef', 'cocina');
      final id = (await central.crearPedido(pedidoDe(1), usuario: mesero))['id'] as int;
      await central.cambiarEstado(id, 'listo', usuario: cocina);
      await central.agregarProductos(id, pedidoDe(2), usuario: mesero);

      final cobrado = (await central.cobrar({'pedidos': [id], 'efectivo': 64})).single;
      expect(cobrado['estado'], 'listo', reason: 'cocina aún prepara el extra');
      expect(cobrado['pago'], isNotNull);

      eventos.clear();
      final terminado = await central.cambiarEstado(id, 'listo', usuario: cocina);
      expect(terminado['estado'], 'pagado');
      expect((terminado['productos'] as List).every((i) => i['extra_desde'] == null), isTrue);
      expect(eventos.single.$2['_accion'], 'listo_pagado');
      expect(central.ventasPorDia(7).single['pedidos'], 1);
    });

    test('no se mueven ni dividen productos de una cuenta cobrada por adelantado', () async {
      final mesero = await usuario('luis', 'mesero');
      final a = await central.crearPedido(pedidoDe(1), usuario: mesero);
      final b = (await central.crearPedido(pedidoDe(2), usuario: mesero))['id'] as int;
      await central.cobrar({
        'pedidos': [a['id']],
        'tarjeta': 42,
      });
      await expectLater(
        central.moverProducto(a['id'] as int, {'detalle_id': (a['productos'] as List).single['id'], 'destino': b}),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'ACCOUNT_PAID')),
      );
    });

    test('las ventas anteriores al pago mixto quedan sin desglose y sobreviven al reinicio', () async {
      final mesero = await usuario('luis', 'mesero');
      final viejo = (await central.crearPedido(pedidoDe(1), usuario: mesero))['id'] as int;
      final nuevo = (await central.crearPedido(pedidoDe(2), usuario: mesero))['id'] as int;
      // Cobro como lo hacían las versiones anteriores de la app.
      await central.cambiarEstado(viejo, 'pagado', usuario: mesero);
      await central.cobrar({'pedidos': [nuevo], 'tarjeta': 22});
      await central.cerrar();

      // Una venta escrita por una versión anterior no trae efectivo ni tarjeta.
      final archivo = File('${carpeta.path}${Platform.pathSeparator}central.jsonl');
      await archivo.writeAsString(
        '\n[{"t":"venta","v":{"id":90,"pedido_id":$viejo,"total":10.0,"fecha":"${DateTime.now().toUtc().toIso8601String()}"}}]\n',
        mode: FileMode.append,
      );

      central = await abrir();
      final dia = central.resumen()['dia'] as Map;
      expect((dia['total_ventas'], dia['efectivo'], dia['tarjeta'], dia['sin_desglose']), (74.0, 0.0, 22.0, 52.0));
      expect(central.obtenerPedido(viejo)['pago'], isNull);
      expect((central.obtenerPedido(nuevo)['pago'] as Map)['tarjeta'], 22);
    });
  });

  group('persistencia', () {
    test('todo sobrevive a un reinicio de la tablet', () async {
      final mesero = await usuario('luis', 'mesero');
      final id = (await central.crearPedido(pedidoDe(1), usuario: mesero, operacion: 'op-9'))['id'] as int;
      final enlace = central.codigoEnlace;
      await central.cerrar();

      central = await abrir();
      expect(central.codigoEnlace, enlace);
      expect(central.obtenerPedido(id)['mesero'], 'luis');
      // La operación también se recuerda: el reintento tras el reinicio no duplica.
      await central.crearPedido(pedidoDe(1), usuario: central.autenticar((await central.login('luis', 'clave123'))['token'] as String)!, operacion: 'op-9');
      expect(central.listarPedidos(), hasLength(1));
      // Los ids siguen avanzando sin repetirse.
      final otro = await central.crearPedido(pedidoDe(2), usuario: mesero);
      expect(otro['id'], greaterThan(id));
    });

    test('una línea cortada por un apagón se descarta sin perder lo anterior', () async {
      final mesero = await usuario('luis', 'mesero');
      await central.crearPedido(pedidoDe(1), usuario: mesero);
      await central.cerrar();

      final archivo = File('${carpeta.path}${Platform.pathSeparator}central.jsonl');
      await archivo.writeAsString('[{"t":"pedido","v":{"id":99', mode: FileMode.append);

      central = await abrir();
      expect(central.listarPedidos(), hasLength(1));
    });

    test('la compactación conserva el estado', () async {
      final mesero = await usuario('luis', 'mesero');
      for (var i = 0; i < 5; i++) {
        await central.crearPedido(pedidoDe(1), usuario: mesero);
      }
      final antes = jsonEncode(central.listarPedidos());
      await central.cerrar();

      // Forzamos la compactación reabriendo con un diario grande.
      final archivo = File('${carpeta.path}${Platform.pathSeparator}central.jsonl');
      final lineas = await archivo.readAsLines();
      await archivo.writeAsString([...lineas, for (var i = 0; i < 3001; i++) '[]'].join('\n'));

      central = await abrir();
      expect(jsonEncode(central.listarPedidos()), antes);
      expect(await archivo.readAsLines(), hasLength(1));
    });
  });

  group('servidor HTTP', () {
    late ServidorCentral servidor;
    late HttpClient http;
    late String base;

    setUp(() async {
      servidor = ServidorCentral(central, puerto: 0, anunciar: false);
      await servidor.iniciar();
      http = HttpClient();
      base = 'http://127.0.0.1:${servidor.puertoEnUso}';
    });

    tearDown(() async {
      http.close(force: true);
      await servidor.detener();
    });

    Future<(int, Map<String, dynamic>)> pedir(
      String metodo,
      String ruta, {
      Object? cuerpo,
      String? token,
      String? enlace,
      String? operacion,
    }) async {
      final req = await http.openUrl(metodo, Uri.parse('$base$ruta'));
      req.headers.set('X-Enlace', enlace ?? central.codigoEnlace);
      if (token != null) req.headers.set('Authorization', 'Bearer $token');
      if (operacion != null) req.headers.set('X-Operacion', operacion);
      if (cuerpo != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(cuerpo));
      }
      final res = await req.close();
      return (res.statusCode, jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>);
    }

    test('sin código de enlace no se puede ni iniciar sesión', () async {
      final (status, cuerpo) = await pedir('POST', '/api/auth/login',
          cuerpo: {'username': 'admin', 'password': 'secreto1'}, enlace: 'AAAA-BBBB');
      expect(status, 403);
      expect(cuerpo['code'], 'ENLACE');
    });

    test('flujo completo con tiempo real por WebSocket', () async {
      await central.crearUsuario({'username': 'luis', 'password': 'clave123', 'role': 'mesero'});
      final (_, login) = await pedir('POST', '/api/auth/login', cuerpo: {'username': 'luis', 'password': 'clave123'});
      final token = login['token'] as String;

      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${servidor.puertoEnUso}/ws?token=$token&enlace=${central.codigoEnlace}',
      );
      final recibido = ws.map((m) => jsonDecode(m as String) as Map<String, dynamic>).first;

      final (status, creado) = await pedir('POST', '/api/pedidos', token: token, operacion: 'op-http', cuerpo: pedidoDe(1));
      expect(status, 201);
      expect((creado['pedido'] as Map)['total'], 42.0);

      final evento = await recibido.timeout(const Duration(seconds: 5));
      expect(evento['evento'], 'nuevo_pedido');
      expect((evento['datos'] as Map)['id'], (creado['pedido'] as Map)['id']);
      await ws.close();

      // Un mesero no ve las métricas.
      final (statusMetricas, _) = await pedir('GET', '/api/metricas/resumen', token: token);
      expect(statusMetricas, 403);
    });

    test('POST /api/pedidos/cobrar cobra en mixto y cocina no puede cobrar', () async {
      final mesero = await usuario('luis', 'mesero');
      await usuario('chef', 'cocina');
      final id = (await central.crearPedido(pedidoDe(1), usuario: mesero))['id'] as int;
      final tokenCocina = (await central.login('chef', 'clave123'))['token'] as String;
      final tokenMesero = (await central.login('luis', 'clave123'))['token'] as String;
      final cuerpo = {
        'pedidos': [id],
        'efectivo': 12,
        'tarjeta': 30,
      };

      final (statusCocina, _) = await pedir('POST', '/api/pedidos/cobrar', token: tokenCocina, cuerpo: cuerpo);
      expect(statusCocina, 403);
      final (status, respuesta) = await pedir('POST', '/api/pedidos/cobrar', token: tokenMesero, cuerpo: cuerpo);
      expect(status, 200);
      final pedido = (respuesta['pedidos'] as List).single as Map;
      expect(pedido['estado'], 'pendiente', reason: 'sigue en cocina');
      expect(pedido['pago'], containsPair('tarjeta', 30));
    });

    test('bloquea el login tras varios intentos fallidos', () async {
      for (var i = 0; i < 5; i++) {
        await pedir('POST', '/api/auth/login', cuerpo: {'username': 'admin', 'password': 'mala'});
      }
      final (status, _) = await pedir('POST', '/api/auth/login', cuerpo: {'username': 'admin', 'password': 'secreto1'});
      expect(status, 429);
    });

    test('logins en paralelo no esquivan el límite de intentos', () async {
      var probadas = 0;
      for (var ronda = 0; ronda < 6; ronda++) {
        final respuestas = await Future.wait([
          for (var i = 0; i < 6; i++)
            pedir('POST', '/api/auth/login', cuerpo: {'username': i.isEven ? 'admin' : 'nadie', 'password': 'mala'}),
        ]);
        for (final (status, _) in respuestas) {
          expect(status, anyOf(401, 429));
          if (status == 401) probadas++;
        }
      }
      expect(probadas, lessThanOrEqualTo(ServidorCentral.maxFallosLogin));
      final (status, cuerpo) =
          await pedir('POST', '/api/auth/login', cuerpo: {'username': 'admin', 'password': 'secreto1'});
      expect(status, 429);
      expect(cuerpo['code'], 'TOO_MANY_ATTEMPTS');
    });

    test('limita los códigos de enlace incorrectos por IP', () async {
      for (var i = 0; i < ServidorCentral.maxFallosEnlace; i++) {
        final (status, _) = await pedir('GET', '/api/central/info', enlace: 'AAAA-BBBB');
        expect(status, 403);
      }
      // Ni con el código correcto mientras dure el bloqueo.
      final (status, _) = await pedir('GET', '/api/central/info');
      expect(status, 429);
    });

    test('con el código viejo y un token que ya no vale responde 401 (cerrar sesión)', () async {
      final token = (await central.login('admin', 'secreto1'))['token'] as String;
      final viejo = central.codigoEnlace;
      await central.renovarEnlace();
      final (status, _) = await pedir('GET', '/api/auth/me', token: token, enlace: viejo);
      expect(status, 401);
      final (sinToken, cuerpo) = await pedir('GET', '/api/auth/me', enlace: viejo);
      expect((sinToken, cuerpo['code']), (403, 'ENLACE'));
    });

    Future<WebSocket> abrirWs(String token) => WebSocket.connect(
          'ws://127.0.0.1:${servidor.puertoEnUso}/ws?token=$token&enlace=${central.codigoEnlace}',
        );

    /// Espera a que el servidor cierre el socket y devuelve el código de cierre.
    Future<int?> cierre(WebSocket ws) async {
      await ws.drain<void>().timeout(const Duration(seconds: 5));
      return ws.closeCode;
    }

    test('renovar el código de enlace cierra los WebSockets abiertos', () async {
      final ws = await abrirWs((await central.login('admin', 'secreto1'))['token'] as String);
      await hastaQue(() => servidor.clientesConectados == 1);
      expect(servidor.clientesConectados, 1);
      await central.renovarEnlace();
      expect(await cierre(ws), cierreSesionInvalida);
      expect(servidor.clientesConectados, 0);
    });

    test('cambiar contraseña o rol, o borrar al usuario, cierra solo sus WebSockets', () async {
      final luis = await usuario('luis', 'mesero');
      final ana = await usuario('ana', 'mesero');
      final wsLuis = await abrirWs((await central.login('luis', 'clave123'))['token'] as String);
      final wsAna = await abrirWs((await central.login('ana', 'clave123'))['token'] as String);
      final wsAdmin = await abrirWs((await central.login('admin', 'secreto1'))['token'] as String);
      await hastaQue(() => servidor.clientesConectados == 3);
      expect(servidor.clientesConectados, 3);

      await central.actualizarUsuario(luis.id, {'username': 'luis', 'role': 'cocina'});
      expect(await cierre(wsLuis), cierreSesionInvalida);
      expect(servidor.clientesConectados, 2);

      final admin = central.autenticar((await central.login('admin', 'secreto1'))['token'] as String)!;
      await central.eliminarUsuario(ana.id, actorId: admin.id);
      expect(await cierre(wsAna), cierreSesionInvalida);
      expect(servidor.clientesConectados, 1, reason: 'el admin sigue conectado');

      // Un token revocado ya no abre el WebSocket.
      final viejo = (await central.login('admin', 'secreto1'))['token'] as String;
      await central.actualizarUsuario(admin.id, {'username': 'admin', 'role': 'admin', 'password': 'nueva123'});
      expect(await cierre(wsAdmin), cierreSesionInvalida);
      await expectLater(
        abrirWs(viejo),
        throwsA(isA<WebSocketException>().having((e) => e.httpStatusCode, 'httpStatusCode', 401)),
      );
    });

    test('POST /api/auth/renovar da un token nuevo que conserva la revocación por versión', () async {
      final luis = await usuario('luis', 'mesero');
      final token = (await central.login('luis', 'clave123'))['token'] as String;

      final (status, cuerpo) = await pedir('POST', '/api/auth/renovar', token: token);
      expect(status, 200);
      final nuevo = cuerpo['token'] as String;
      expect(central.autenticar(nuevo)?.id, luis.id);
      expect((cuerpo['user'] as Map)['username'], 'luis');

      final (sinToken, _) = await pedir('POST', '/api/auth/renovar');
      expect(sinToken, 401);

      await central.actualizarUsuario(luis.id, {'username': 'luis', 'role': 'mesero', 'password': 'nueva123'});
      expect(central.autenticar(nuevo), isNull, reason: 'el token renovado también se revoca');
      final (revocado, _) = await pedir('POST', '/api/auth/renovar', token: nuevo);
      expect(revocado, 401);
    });
  });

  group('caducidad y renovación de sesiones', () {
    late Directory carpetaReloj;
    late Central conReloj;
    late ServidorCentral servidor;
    var ahora = DateTime.now();

    setUp(() async {
      ahora = DateTime.now();
      carpetaReloj = await Directory.systemTemp.createTemp('central_reloj');
      conReloj = await Central.abrir(carpetaReloj, iteraciones: 1000, reloj: () => ahora);
      await conReloj.inicializar(admin: 'admin', password: 'secreto1');
      servidor = ServidorCentral(conReloj, puerto: 0, anunciar: false);
      await servidor.iniciar();
    });

    tearDown(() async {
      await servidor.detener();
      await conReloj.cerrar();
      await carpetaReloj.delete(recursive: true);
    });

    test('renovar a mitad del turno alarga la sesión 12 h desde la renovación', () async {
      final token = (await conReloj.login('admin', 'secreto1'))['token'] as String;
      ahora = ahora.add(const Duration(hours: 7));
      final renovado = conReloj.renovarSesion(conReloj.autenticar(token)!)['token'] as String;

      ahora = ahora.add(const Duration(hours: 6)); // 13 h desde el login
      expect(conReloj.autenticar(token), isNull, reason: 'el token original caducó');
      expect(conReloj.autenticar(renovado), isNotNull, reason: 'el renovado sigue vigente');
    });

    test('un WebSocket con el token caducado se cierra al revisarlo', () async {
      final token = (await conReloj.login('admin', 'secreto1'))['token'] as String;
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${servidor.puertoEnUso}/ws?token=$token&enlace=${conReloj.codigoEnlace}',
      );
      await hastaQue(() => servidor.clientesConectados == 1);
      servidor.revisarSesiones();
      expect(servidor.clientesConectados, 1, reason: 'aún vigente');

      ahora = ahora.add(const Duration(hours: 13));
      servidor.revisarSesiones();
      await ws.drain<void>().timeout(const Duration(seconds: 5));
      expect(ws.closeCode, cierreSesionInvalida);
      expect(servidor.clientesConectados, 0);
    });
  });

  group('red local', () {
    test('clasifica IP privadas, locales y públicas', () {
      for (final ip in [
        '192.168.1.20',
        '10.0.0.5',
        '172.16.0.1',
        '172.31.255.254',
        '127.0.0.1',
        '169.254.10.1',
        '::1',
        'fd12:3456::1',
        'fe80::1',
        '::ffff:192.168.1.7',
      ]) {
        expect(esIpLocalTexto(ip), isTrue, reason: ip);
      }
      for (final ip in [
        '210.23.40.129', // datos móviles
        '8.8.8.8',
        '172.32.0.1',
        '172.15.255.255',
        '100.64.0.1', // CGNAT de la operadora
        '192.169.0.1',
        '11.0.0.1',
        '2001:4860::8888',
        '::ffff:8.8.8.8',
        'central.local',
        '',
      ]) {
        expect(esIpLocalTexto(ip), isFalse, reason: ip);
      }
    });

    test('ipsLocales nunca ofrece IP públicas ni loopback', () async {
      for (final ip in await ipsLocales()) {
        expect(esIpLocalTexto(ip), isTrue, reason: ip);
        expect(ip, isNot(startsWith('127.')));
      }
    });
  });

  test('PBKDF2 coincide con el vector de prueba RFC 6070 (adaptado a SHA-256)', () {
    // Vector conocido: PBKDF2-HMAC-SHA256("password", "salt", 1, 32).
    final hash = pbkdf2(utf8.encode('password'), utf8.encode('salt'), 1, 32);
    expect(
      hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
  });
}
