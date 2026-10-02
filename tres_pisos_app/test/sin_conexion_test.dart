import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tres_pisos_app/central/central.dart';
import 'package:tres_pisos_app/central/servidor_central.dart';
import 'package:tres_pisos_app/features/auth/almacen_sesion.dart';
import 'package:tres_pisos_app/features/auth/auth_controller.dart';
import 'package:tres_pisos_app/features/auth/sesion.dart';
import 'package:tres_pisos_app/features/pedidos/modelos.dart';
import 'package:tres_pisos_app/features/pedidos/pedidos_controller.dart';

/// Prueba de punta a punta con una central real en localhost: la tablet del
/// mesero pierde la conexión, guarda el pedido, y lo envía una sola vez al volver.
void main() {
  late Directory carpeta;
  late Central central;
  late ServidorCentral servidor;
  late int puerto;
  late ProviderContainer app;

  const tacos = Producto(id: 1, nombre: 'Tacos', precio: 42, categoria: 'Tacos', activo: true);

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('sin_conexion');
    central = await Central.abrir(carpeta, iteraciones: 1000);
    await central.inicializar(admin: 'admin', password: 'secreto1', menu: [
      {'nombre': 'Tacos', 'precio': 42, 'categoria': 'Tacos'},
    ]);
    await central.crearUsuario({'username': 'luis', 'password': 'clave123', 'role': 'mesero'});
    servidor = ServidorCentral(central, puerto: 0, anunciar: false);
    await servidor.iniciar();
    puerto = servidor.puertoEnUso;

    final login = await central.login('luis', 'clave123');
    final conexion = Conexion(modo: ModoConexion.enlazada, url: 'http://127.0.0.1:$puerto', enlace: central.codigoEnlace);
    SharedPreferences.setMockInitialValues({});
    app = ProviderContainer(overrides: [
      almacenSesionProvider.overrideWithValue(AlmacenSesion(await SharedPreferences.getInstance())),
      datosArranqueProvider.overrideWithValue(DatosArranque(
        conexion: conexion,
        sesion: Sesion(
          conexion: conexion,
          token: login['token'] as String,
          usuario: Usuario.fromJson(login['user'] as Map<String, dynamic>),
        ),
      )),
    ]);
    // Mantiene vivos los providers como lo haría la pantalla.
    app
      ..listen(pedidosActivosProvider, (_, _) {})
      ..listen(colaEnviosProvider, (_, _) {});
  });

  tearDown(() async {
    app.dispose();
    await servidor.detener();
    await central.cerrar();
    await carpeta.delete(recursive: true);
  });

  test('sin conexión el pedido queda en la cola y se envía una sola vez al volver', () async {
    await app.read(pedidosActivosProvider.future);
    await app.read(productosProvider.future);

    // Se cae la central (o el Wi-Fi).
    await servidor.detener();
    final resultado = await app.read(pedidosActivosProvider.notifier).crear(
          mesa: 3,
          tipo: TipoPedido.aqui,
          lineas: const [LineaCarrito(producto: tacos, cantidad: 2)],
        );
    expect(resultado, isA<EnCola>());
    expect(app.read(colaEnviosProvider), hasLength(1));
    expect(app.read(sinConexionProvider), isTrue);
    expect(central.listarPedidos(), isEmpty);

    // Mientras tanto, el menú y la lista salen de la copia guardada.
    app.invalidate(productosProvider);
    expect((await app.read(productosProvider.future)).single.nombre, 'Tacos');

    // Vuelve la central en el mismo puerto.
    servidor = ServidorCentral(central, puerto: puerto, anunciar: false);
    await servidor.iniciar();
    await app.read(colaEnviosProvider.notifier).procesar();

    expect(app.read(colaEnviosProvider), isEmpty);
    expect(central.listarPedidos(), hasLength(1));
    expect(central.listarPedidos().single['total'], 84.0);

    // Reintentar la misma operación (p. ej. se perdió la respuesta) no duplica.
    final envio = resultado as EnCola;
    await app.read(colaEnviosProvider.notifier).encolar(envio.envio);
    await app.read(colaEnviosProvider.notifier).procesar();
    expect(central.listarPedidos(), hasLength(1));
  });

  test('un rechazo de la central queda marcado y no bloquea la cola', () async {
    await app.read(pedidosActivosProvider.future);
    await servidor.detener();
    const desactivado = Producto(id: 1, nombre: 'Tacos', precio: 42, categoria: 'Tacos', activo: true);
    await app.read(pedidosActivosProvider.notifier).crear(
          mesa: 1,
          tipo: TipoPedido.aqui,
          lineas: const [LineaCarrito(producto: desactivado)],
        );

    // Mientras estaba sin conexión, el admin desactivó el producto.
    await central.actualizarProducto(1, {'nombre': 'Tacos', 'precio': 42, 'categoria': 'Tacos', 'activo': false});
    servidor = ServidorCentral(central, puerto: puerto, anunciar: false);
    await servidor.iniciar();
    await app.read(colaEnviosProvider.notifier).procesar();

    final cola = app.read(colaEnviosProvider);
    expect(cola.single.error, contains('inactivo'));
    expect(central.listarPedidos(), isEmpty);
  });
}
