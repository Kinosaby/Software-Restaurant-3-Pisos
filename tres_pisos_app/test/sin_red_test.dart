import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tres_pisos_app/central/central.dart';
import 'package:tres_pisos_app/central/servidor_central.dart';
import 'package:tres_pisos_app/core/almacen_local.dart';
import 'package:tres_pisos_app/core/api_client.dart';
import 'package:tres_pisos_app/features/auth/almacen_sesion.dart';
import 'package:tres_pisos_app/features/auth/auth_controller.dart';
import 'package:tres_pisos_app/features/auth/sesion.dart';
import 'package:tres_pisos_app/features/conexion/central_local.dart';
import 'package:tres_pisos_app/features/pedidos/modelos.dart';
import 'package:tres_pisos_app/features/pedidos/pedidos_controller.dart';
import 'package:tres_pisos_app/features/pedidos/tiempo_real.dart';

/// Uso sin internet y con el Wi-Fi cortándose: central real en localhost y la
/// tablet del mesero perdiendo la conexión a ratos.
void main() {
  late Directory carpeta;
  late Central central;
  late ServidorCentral servidor;
  late int puerto;
  late SharedPreferences prefs;
  late Conexion conexion;
  late Map<String, dynamic> login;
  final contenedores = <ProviderContainer>[];

  const tacos = Producto(id: 1, nombre: 'Tacos', precio: 42, categoria: 'Tacos', activo: true);

  /// Abre "la app" del mesero; varias veces sobre las mismas preferencias simula cerrarla y abrirla.
  ProviderContainer abrirApp({List overrides = const []}) {
    final app = ProviderContainer(overrides: [
      almacenSesionProvider.overrideWithValue(AlmacenSesion(prefs)),
      datosArranqueProvider.overrideWithValue(DatosArranque(
        conexion: conexion,
        sesion: Sesion(
          conexion: conexion,
          token: login['token'] as String,
          usuario: Usuario.fromJson(login['user'] as Map<String, dynamic>),
        ),
      )),
      ...overrides.cast(),
    ]);
    app
      ..listen(pedidosActivosProvider, (_, _) {})
      ..listen(colaEnviosProvider, (_, _) {});
    contenedores.add(app);
    return app;
  }

  Future<void> apagarCentral() => servidor.detener();

  Future<void> encenderCentral() async {
    servidor = ServidorCentral(central, puerto: puerto, anunciar: false);
    await servidor.iniciar();
  }

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('sin_red');
    central = await Central.abrir(carpeta, iteraciones: 1000);
    await central.inicializar(admin: 'admin', password: 'secreto1', menu: [
      {'nombre': 'Tacos', 'precio': 42, 'categoria': 'Tacos'},
    ]);
    await central.crearUsuario({'username': 'luis', 'password': 'clave123', 'role': 'mesero'});
    servidor = ServidorCentral(central, puerto: 0, anunciar: false);
    await servidor.iniciar();
    puerto = servidor.puertoEnUso;
    login = await central.login('luis', 'clave123');
    conexion = Conexion(modo: ModoConexion.enlazada, url: 'http://127.0.0.1:$puerto', enlace: central.codigoEnlace);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    for (final app in contenedores) {
      app.dispose();
    }
    contenedores.clear();
    await servidor.detener();
    await central.cerrar();
    await carpeta.delete(recursive: true);
  });

  UsuarioCentral mesero() => central.autenticar(login['token'] as String)!;

  test('la central se usa a sí misma por loopback, no por la IP del Wi-Fi', () async {
    final local = CentralLocal(central, servidor);
    expect(local.urlLocal, 'http://127.0.0.1:$puerto');
    expect(local.conexion.modo, ModoConexion.central);

    // Responde por 127.0.0.1 aunque la tablet no tenga ninguna red.
    final api = ApiClient(servidor: local.urlLocal, enlace: central.codigoEnlace);
    expect((await api.get('/api/central/info'))['nombre'], central.nombre);
  });

  test('la cola sobrevive a cerrar la app y se envía una sola vez al volver a abrirla', () async {
    var app = abrirApp();
    await app.read(pedidosActivosProvider.future);
    await apagarCentral();

    final resultado = await app.read(pedidosActivosProvider.notifier).crear(
          mesa: 4,
          tipo: TipoPedido.aqui,
          lineas: const [LineaCarrito(producto: tacos, cantidad: 3)],
        );
    expect(resultado, isA<EnCola>());

    // Se cierra la app sin haber enviado nada.
    app.dispose();
    contenedores.remove(app);

    await encenderCentral();
    app = abrirApp();
    final cola = app.read(colaEnviosProvider);
    expect(cola, hasLength(1));
    expect(cola.single.operacion, (resultado as EnCola).envio.operacion);

    await app.read(colaEnviosProvider.notifier).procesar();
    await app.read(colaEnviosProvider.notifier).procesar();
    expect(app.read(colaEnviosProvider), isEmpty);
    expect(central.listarPedidos(), hasLength(1));
    expect(central.listarPedidos().single['total'], 126.0);

    // Y tras otro reinicio no queda nada por reenviar.
    app.dispose();
    contenedores.remove(app);
    expect(abrirApp().read(colaEnviosProvider), isEmpty);
  });

  test('agregar en cola a un pedido que se canceló mientras tanto queda rechazado con el motivo', () async {
    final app = abrirApp();
    await app.read(pedidosActivosProvider.notifier).crear(
          mesa: 2,
          tipo: TipoPedido.aqui,
          lineas: const [LineaCarrito(producto: tacos)],
        );
    final pedido = (await app.read(pedidosActivosProvider.future)).single;

    await apagarCentral();
    final resultado = await app.read(pedidosActivosProvider.notifier).agregar(
          pedido,
          const [LineaCarrito(producto: tacos, cantidad: 2)],
        );
    expect(resultado, isA<EnCola>());

    // Cocina lo canceló mientras el mesero estaba sin conexión.
    await central.cambiarEstado(pedido.id, 'cancelado', usuario: mesero());
    await encenderCentral();
    await app.read(colaEnviosProvider.notifier).procesar();

    final envio = app.read(colaEnviosProvider).single;
    expect(envio.error, contains('cancelado'));
    final guardado = central.obtenerPedido(pedido.id);
    expect(guardado['estado'], 'cancelado');
    expect((guardado['productos'] as List).single['cantidad'], 1);

    // Se puede descartar y no vuelve a intentarse.
    app.read(colaEnviosProvider.notifier).descartar(envio);
    expect(app.read(colaEnviosProvider), isEmpty);
  });

  test('agregar en cola a una cuenta que se cobró mientras tanto abre una cuenta nueva', () async {
    final app = abrirApp();
    await app.read(pedidosActivosProvider.notifier).crear(
          mesa: 6,
          tipo: TipoPedido.aqui,
          lineas: const [LineaCarrito(producto: tacos)],
        );
    final pedido = (await app.read(pedidosActivosProvider.future)).single;

    await apagarCentral();
    await app.read(pedidosActivosProvider.notifier).agregar(pedido, const [LineaCarrito(producto: tacos)]);
    await central.cobrar({
      'pedidos': [pedido.id],
      'efectivo': 42,
    });
    await encenderCentral();
    await app.read(colaEnviosProvider.notifier).procesar();

    expect(app.read(colaEnviosProvider), isEmpty);
    final pedidos = central.listarPedidos();
    expect(pedidos, hasLength(2));
    // La cuenta cobrada no cambió de total; lo agregado va en otra cuenta de la misma mesa.
    expect(central.obtenerPedido(pedido.id)['total'], 42.0);
    expect(pedidos.where((p) => p['id'] != pedido.id).single['mesa'], 6);
  });

  test('lo que no se encola falla con un aviso claro y sin dejar nada a medias', () async {
    final app = abrirApp();
    final notifier = app.read(pedidosActivosProvider.notifier);
    for (final mesa in [1, 1]) {
      await notifier.crear(mesa: mesa, tipo: TipoPedido.aqui, lineas: const [LineaCarrito(producto: tacos, cantidad: 2)]);
    }
    final pedidos = await app.read(pedidosActivosProvider.future);
    final antes = jsonEncode(central.listarPedidos());

    await apagarCentral();
    final acciones = <String, Future<Object?> Function()>{
      'registrar el cobro': () => notifier.cobrar([pedidos.first.id], const Pago(efectivo: 84)),
      'cancelar el pedido': () => notifier.cancelar(pedidos.first.id),
      'cambiar el estado': () => notifier.cambiarEstado(pedidos.first.id, EstadoPedido.preparando),
      'guardar los cambios': () => notifier.editar(pedidos.first.id, mesa: 9),
      'mover o dividir': () => notifier.moverProducto(pedidos.first, pedidos.first.items.first,
          cantidad: 1, destino: pedidos.last),
    };
    for (final MapEntry(key: que, value: accion) in acciones.entries) {
      await expectLater(
        accion(),
        throwsA(isA<ApiException>()
            .having((e) => e.sinConexion, 'sinConexion', isTrue)
            .having((e) => e.mensaje, 'mensaje', allOf(contains('Sin conexión con la central'), contains(que)))),
        reason: que,
      );
    }
    // Nada de eso se guardó para después ni cambió en la central.
    expect(app.read(colaEnviosProvider), isEmpty);
    await encenderCentral();
    expect(jsonEncode(central.listarPedidos()), antes);
    expect(app.read(pedidosActivosProvider).value, hasLength(2));
  });

  test('si la central no contesta a tiempo el aviso dice que puede haberse registrado', () async {
    // Una "central" que acepta la conexión y nunca responde (colgada).
    final colgada = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    colgada.listen(sockets.add);
    addTearDown(() async {
      for (final s in sockets) {
        s.destroy();
      }
      await colgada.close();
    });

    final url = 'http://127.0.0.1:${colgada.port}';
    final dio = Dio(BaseOptions(
      baseUrl: url,
      connectTimeout: const Duration(seconds: 1),
      receiveTimeout: const Duration(seconds: 1),
    ));
    final app = abrirApp(overrides: [
      apiClientProvider.overrideWithValue(ApiClient(servidor: url, dio: dio)),
    ]);
    // Arranca con la lista guardada (la central no contesta).
    await app.read(almacenLocalProvider).guardarLista('pedidos', const []);

    final reloj = Stopwatch()..start();
    await expectLater(
      app.read(pedidosActivosProvider.notifier).cobrar([1], const Pago(efectivo: 10)),
      throwsA(isA<ApiException>()
          .having((e) => e.entregaIncierta, 'entregaIncierta', isTrue)
          .having((e) => e.mensaje, 'mensaje', contains('no se sabe si'))),
    );
    expect(reloj.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('cambiar varios pedidos y perder la conexión a la mitad dice cuántos sí cambiaron', () async {
    final app = abrirApp();
    final notifier = app.read(pedidosActivosProvider.notifier);
    await notifier.crear(mesa: 3, tipo: TipoPedido.aqui, lineas: const [LineaCarrito(producto: tacos)]);
    final pedido = (await app.read(pedidosActivosProvider.future)).single;

    // El primero existe; el segundo no: la central lo rechaza y se informa el avance.
    await expectLater(
      notifier.cambiarEstadoVarios([pedido.id, 999], EstadoPedido.preparando),
      throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('De 2 pedidos, 1 sí se cambiaron'))),
    );
    expect(central.obtenerPedido(pedido.id)['estado'], 'preparando');
  });

  test('el tiempo real se reconecta solo cuando vuelve la central', () async {
    final tiempoReal = TiempoRealCentral(
      conexion.url,
      token: () => login['token'] as String,
      enlace: central.codigoEnlace,
    );
    addTearDown(tiempoReal.cerrar);
    final eventos = <EventoTiempoReal>[];
    tiempoReal.eventos.listen(eventos.add);

    Future<void> esperar(bool Function() condicion) async {
      final limite = DateTime.now().add(const Duration(seconds: 15));
      while (!condicion()) {
        if (DateTime.now().isAfter(limite)) fail('tiempo agotado');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    await esperar(() => tiempoReal.estaConectado);
    await apagarCentral();
    await esperar(() => !tiempoReal.estaConectado);

    await encenderCentral();
    await esperar(() => tiempoReal.estaConectado);
    expect(eventos.whereType<Conectado>(), hasLength(2));

    // Y vuelve a recibir avisos.
    await central.crearPedido({
      'mesa': 1,
      'tipo': 'aqui',
      'productos': [
        {'producto_id': 1, 'cantidad': 1},
      ],
    }, usuario: mesero());
    await esperar(() => eventos.whereType<PedidoCambiado>().isNotEmpty);
  });

  group('si la central cambia de IP y la tablet se vuelve a enlazar', () {
    Future<List<EnvioPendiente>> colaTras(Conexion nueva) async {
      final app = abrirApp();
      await app.read(pedidosActivosProvider.future);
      await apagarCentral();
      await app.read(pedidosActivosProvider.notifier).crear(
            mesa: 5,
            tipo: TipoPedido.aqui,
            lineas: const [LineaCarrito(producto: tacos)],
          );
      app.read(favoritosProvider.notifier).registrar({
        'productos': [
          {'producto_id': 1, 'cantidad': 1},
        ],
      });
      await app.read(conexionProvider.notifier).usar(nueva);
      return [
        for (final e in AlmacenLocal(prefs, nueva.url).lista('cola') ?? const <Map<String, dynamic>>[])
          EnvioPendiente.fromJson(e),
      ];
    }

    test('los envíos pendientes pasan a la dirección nueva', () async {
      const nuevaUrl = 'http://192.168.1.77:8787';
      final cola = await colaTras(Conexion(modo: ModoConexion.enlazada, url: nuevaUrl, enlace: central.codigoEnlace));
      expect(cola, hasLength(1));
      expect(cola.single.resumen, contains('Mesa 5'));
      expect(AlmacenLocal(prefs, conexion.url).lista('cola'), isNull);
      expect(AlmacenLocal(prefs, nuevaUrl).mapa('favoritos'), isNotEmpty);
    });

    test('con otra central (otro código) no se mezclan', () async {
      final cola = await colaTras(
          const Conexion(modo: ModoConexion.enlazada, url: 'http://192.168.1.77:8787', enlace: 'ZZZZ-ZZZZ'));
      expect(cola, isEmpty);
      expect(AlmacenLocal(prefs, conexion.url).lista('cola'), hasLength(1));
    });
  });
}
