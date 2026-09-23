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

    test('bloquea el login tras varios intentos fallidos', () async {
      for (var i = 0; i < 5; i++) {
        await pedir('POST', '/api/auth/login', cuerpo: {'username': 'admin', 'password': 'mala'});
      }
      final (status, _) = await pedir('POST', '/api/auth/login', cuerpo: {'username': 'admin', 'password': 'secreto1'});
      expect(status, 429);
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
