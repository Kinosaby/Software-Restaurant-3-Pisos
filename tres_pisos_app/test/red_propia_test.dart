import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tres_pisos_app/app.dart';
import 'package:tres_pisos_app/core/plataforma.dart';
import 'package:tres_pisos_app/features/auth/almacen_sesion.dart';
import 'package:tres_pisos_app/features/auth/auth_controller.dart';
import 'package:tres_pisos_app/features/auth/sesion.dart';
import 'package:tres_pisos_app/features/conexion/aviso_red.dart';
import 'package:tres_pisos_app/features/conexion/enlace_qr.dart';
import 'package:tres_pisos_app/features/conexion/red_propia.dart';

const _canal = MethodChannel('tres_pisos/plataforma');

/// Lo que respondería Android (`MainActivity`) a cada llamada del canal.
typedef _Android = Future<Object?> Function(MethodCall llamada);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final llamadas = <String>[];

  void android(_Android responder) {
    llamadas.clear();
    mensajero.setMockMethodCallHandler(_canal, (llamada) {
      llamadas.add(llamada.method);
      return responder(llamada);
    });
    addTearDown(() => mensajero.setMockMethodCallHandler(_canal, null));
  }

  /// Aviso que Android manda por su cuenta (la red se cayó, se volvió a crear...).
  Future<void> avisar(String metodo, Map<String, Object?> estado) async {
    await mensajero.handlePlatformMessage(
      _canal.name,
      _canal.codec.encodeMethodCall(MethodCall(metodo, estado)),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<(ProviderContainer, SharedPreferences)> contenedor({Conexion? conexion}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      almacenSesionProvider.overrideWithValue(AlmacenSesion(prefs)),
      datosArranqueProvider.overrideWithValue(DatosArranque(conexion: conexion)),
    ]);
    addTearDown(container.dispose);
    return (container, prefs);
  }

  const red1 = {'fase': 'activa', 'ssid': 'AndroidShare_1111', 'clave': 'clave-uno-1', 'seguridad': 'wpa2'};
  const red2 = {'fase': 'activa', 'ssid': 'AndroidShare_2222', 'clave': 'clave-dos-2', 'seguridad': 'wpa3'};
  const caida = {
    'fase': 'caida',
    'error': 'Android apagó la red Wi-Fi de la central.',
    'codigo': 'RED',
    'reintentando': true,
  };

  test('el estado que manda Android se lee bien, también si llega incompleto', () {
    expect(EstadoRedPropia.desde(null), const EstadoRedPropia());
    final activa = EstadoRedPropia.desde(red2);
    expect(activa.fase, FaseRedPropia.activa);
    expect(activa.red, (ssid: 'AndroidShare_2222', clave: 'clave-dos-2', seguridad: 'wpa3'));
    expect(activa.pedida, isTrue);

    final sinRed = EstadoRedPropia.desde(caida);
    expect(sinRed.fase, FaseRedPropia.caida);
    expect(sinRed.red, isNull);
    expect(sinRed.error, 'Android apagó la red Wi-Fi de la central.');
    expect(sinRed.reintentando, isTrue);
    expect(sinRed.pedida, isTrue);

    // "Activa" sin nombre ni clave no sirve para el QR: cuenta como caída.
    expect(EstadoRedPropia.desde({'fase': 'activa'}).fase, FaseRedPropia.caida);
    // Una fase desconocida (app más nueva en Android) no rompe nada.
    expect(EstadoRedPropia.desde({'fase': 'otra'}).fase, FaseRedPropia.apagada);
    // Una red caída no arrastra los datos de la anterior.
    expect(EstadoRedPropia.desde({...red1, 'fase': 'caida'}).red, isNull);

    expect(EstadoRedMesero.desde({'fase': 'perdida', 'ssid': 'X', 'error': 'Sin red'}),
        const EstadoRedMesero(fase: FaseRedMesero.perdida, ssid: 'X', error: 'Sin red'));
    expect(EstadoRedMesero.desde({'fase': 'rara'}).fase, FaseRedMesero.ninguna);

    expect(ajustesParaRed('UBICACION'), 'ubicacion');
    expect(ajustesParaRed('PERMISO'), 'app');
    expect(ajustesParaRed('RED'), isNull);
  });

  test('la central enciende su red; si Android la apaga y la recrea, se ve la nueva y se pide reescanear', () async {
    android((llamada) async => switch (llamada.method) {
          'redPropia' => (llamada.arguments as Map)['activa'] == true ? red1 : null,
          'redPropiaEstado' => {'fase': 'apagada'},
          _ => null,
        });
    final (container, prefs) = await contenedor();
    final estados = <EstadoRedPropia>[];
    container.listen(redPropiaProvider, (_, e) => estados.add(e));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(redPropiaProvider).fase, FaseRedPropia.apagada);

    expect(await container.read(redPropiaProvider.notifier).encender(), isNull);
    var estado = container.read(redPropiaProvider);
    expect(estado.fase, FaseRedPropia.activa);
    expect(estado.red?.ssid, 'AndroidShare_1111');
    expect(estado.qrNuevo, isFalse, reason: 'el administrador la acaba de encender: ya está viendo el QR');
    expect(estados.any((e) => e.fase == FaseRedPropia.creando), isTrue);
    expect(prefs.getBool('red_propia'), isTrue);

    // Android apaga la red por su cuenta: la central deja de creer que la tiene.
    await avisar('redPropiaCambio', caida);
    estado = container.read(redPropiaProvider);
    expect(estado.fase, FaseRedPropia.caida);
    expect(estado.red, isNull);
    expect(estado.error, contains('apagó'));
    expect(estado.reintentando, isTrue);
    expect(estado.pedida, isTrue, reason: 'el interruptor sigue encendido: se sigue queriendo red propia');

    // Se vuelve a crear sola, con otro nombre y contraseña.
    await avisar('redPropiaCambio', red2);
    estado = container.read(redPropiaProvider);
    expect(estado.red, (ssid: 'AndroidShare_2222', clave: 'clave-dos-2', seguridad: 'wpa3'));
    expect(estado.qrNuevo, isTrue);

    await container.read(redPropiaProvider.notifier).qrAvisado();
    expect(container.read(redPropiaProvider).qrNuevo, isFalse);
    // El mismo aviso repetido (p. ej. al reabrir la pantalla) ya no vuelve a pedirlo.
    await avisar('redPropiaCambio', red2);
    expect(container.read(redPropiaProvider).qrNuevo, isFalse);

    await container.read(redPropiaProvider.notifier).apagar();
    expect(container.read(redPropiaProvider), const EstadoRedPropia());
    expect(prefs.getBool('red_propia'), isFalse);
    expect(llamadas.where((m) => m == 'redPropia').length, 2);
  });

  test('si falta la ubicación la central lo dice y sigue queriendo su red', () async {
    const sinUbicacion = {'fase': 'caida', 'error': 'Enciende la "Ubicación" de la tablet.', 'codigo': 'UBICACION'};
    android((llamada) async => switch (llamada.method) {
          'redPropia' => throw PlatformException(code: 'UBICACION', message: 'Enciende la "Ubicación" de la tablet.'),
          'redPropiaEstado' => sinUbicacion,
          _ => null,
        });
    final (container, prefs) = await contenedor();
    container.listen(redPropiaProvider, (_, _) {});

    final error = await container.read(redPropiaProvider.notifier).encender();
    expect(error, contains('Ubicación'));
    final estado = container.read(redPropiaProvider);
    expect(estado.fase, FaseRedPropia.caida);
    expect(estado.reintentando, isFalse);
    expect(ajustesParaRed(estado.codigo), 'ubicacion');
    expect(prefs.getBool('red_propia'), isTrue, reason: 'al volver a abrir la app se intenta otra vez');
  });

  test('en una tablet que no puede crear redes (Android 7) no queda nada encendido', () async {
    android((llamada) async => switch (llamada.method) {
          'redPropia' => throw PlatformException(code: 'NO_COMPATIBLE', message: 'Esta tablet no puede crear su red.'),
          'redPropiaEstado' => {'fase': 'apagada'},
          'redCapacidades' => {'crear': false, 'unir': false},
          _ => null,
        });
    final (container, prefs) = await contenedor();
    container.listen(redPropiaProvider, (_, _) {});

    expect(await Plataforma.capacidadesRed(), (crearRed: false, unirseSola: false));
    expect(await container.read(redPropiaProvider.notifier).encender(), contains('no puede'));
    expect(container.read(redPropiaProvider).pedida, isFalse);
    expect(prefs.getBool('red_propia'), isFalse);
  });

  test('al arrancar, recrear la red no detiene la app aunque Android tarde o falle', () async {
    final nunca = Completer<Object?>();
    android((llamada) => llamada.method == 'redPropia' ? nunca.future : Future.value());
    SharedPreferences.setMockInitialValues({'red_propia': true});
    final prefs = await SharedPreferences.getInstance();
    expect(await reanudarRedPropia(prefs).timeout(const Duration(seconds: 1)), isNull);
    expect(llamadas, ['redPropia']);

    // Un fallo tampoco se escapa como error sin atender.
    android((llamada) async => throw PlatformException(code: 'RED', message: 'No se pudo'));
    expect(await reanudarRedPropia(prefs), isNull);
    await Future<void>.delayed(Duration.zero);

    // Sin la preferencia ni se intenta.
    SharedPreferences.setMockInitialValues({});
    android((llamada) async => null);
    expect(await reanudarRedPropia(await SharedPreferences.getInstance()), isNull);
    expect(llamadas, isEmpty);
  });

  test('sin el canal de Android (pruebas) se supone una tablet moderna y sin red propia', () async {
    expect(await Plataforma.capacidadesRed(), (crearRed: true, unirseSola: true));
    expect(await Plataforma.estadoRedPropia(), const EstadoRedPropia());
    expect(await Plataforma.estadoRedMesero(), const EstadoRedMesero());
  });

  const redMesero = (ssid: 'AndroidShare_1111', clave: 'clave-uno-1', seguridad: 'wpa2');
  const enlazada = Conexion(modo: ModoConexion.enlazada, url: 'http://192.168.49.1:8787', enlace: 'K7P2-9QXM', red: redMesero);

  testWidgets('el mesero ve que perdió la red de la central y puede volver a escanear el QR', (tester) async {
    android((llamada) async => switch (llamada.method) {
          'redMeseroEstado' => {'fase': 'unida', 'ssid': 'AndroidShare_1111'},
          _ => null,
        });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var escanear = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        almacenSesionProvider.overrideWithValue(AlmacenSesion(prefs)),
        datosArranqueProvider.overrideWithValue(const DatosArranque(conexion: enlazada)),
      ],
      child: MaterialApp(
        home: AvisoRed(alAbrirConexion: () => escanear++, child: const Scaffold(body: Text('Mesas'))),
      ),
    ));
    await tester.pump();
    expect(find.text('Mesas'), findsOneWidget);
    expect(find.textContaining('red Wi-Fi de la central'), findsNothing);

    await tester.runAsync(() => avisar('redMeseroCambio', {'fase': 'reintentando', 'ssid': 'AndroidShare_1111'}));
    await tester.pump();
    expect(find.textContaining('Reconectando'), findsOneWidget);
    expect(find.text('Mesas'), findsOneWidget, reason: 'la pantalla sigue ahí: la app no se queda colgada');

    await tester.runAsync(() => avisar('redMeseroCambio', {
          'fase': 'perdida',
          'ssid': 'AndroidShare_1111',
          'error': 'Se perdió la red Wi-Fi de la central. Vuelve a escanear el QR de la central.',
        }));
    await tester.pump();
    expect(find.textContaining('Vuelve a escanear el QR de la central'), findsOneWidget);

    await tester.tap(find.text('Escanear QR'));
    expect(escanear, 1);
    llamadas.clear();
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(llamadas, contains('conectarRed'));

    await tester.runAsync(() => avisar('redMeseroCambio', {'fase': 'unida', 'ssid': 'AndroidShare_1111'}));
    await tester.pump();
    expect(find.textContaining('red Wi-Fi de la central'), findsNothing);
  });

  testWidgets('con router (sin red propia) nunca aparece el aviso de red', (tester) async {
    android((llamada) async => switch (llamada.method) {
          'redMeseroEstado' => {'fase': 'perdida', 'error': 'Vuelve a escanear el QR de la central.'},
          _ => null,
        });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const conRouter = Conexion(modo: ModoConexion.enlazada, url: 'http://192.168.1.20:8787', enlace: 'K7P2-9QXM');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        almacenSesionProvider.overrideWithValue(AlmacenSesion(prefs)),
        datosArranqueProvider.overrideWithValue(const DatosArranque(conexion: conRouter)),
      ],
      child: MaterialApp(home: AvisoRed(alAbrirConexion: () {}, child: const Scaffold(body: Text('Mesas')))),
    ));
    await tester.pump();
    expect(find.text('Mesas'), findsOneWidget);
    expect(find.textContaining('escanear'), findsNothing);
  });

  testWidgets('una tablet con Android 9 muestra el nombre y la clave de la red para unirse a mano', (tester) async {
    android((llamada) async => switch (llamada.method) {
          'redCapacidades' => {'crear': true, 'unir': false},
          _ => null,
        });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        almacenSesionProvider.overrideWithValue(AlmacenSesion(await SharedPreferences.getInstance())),
        datosArranqueProvider.overrideWithValue(const DatosArranque()),
        enlaceInicialProvider.overrideWithValue(const DatosEnlace(
          ips: ['192.168.49.1'],
          puerto: 8787,
          codigo: 'K7P2-9QXM',
          red: redMesero,
        )),
      ],
      child: const TresPisosApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.widgetWithText(FilledButton, 'Conectar'));
    // El botón de escanear gira mientras tanto: no se puede esperar a que todo se detenga.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Conecta esta tablet al Wi-Fi de la central'), findsOneWidget);
    expect(find.text('AndroidShare_1111'), findsOneWidget);
    expect(find.text('clave-uno-1'), findsOneWidget);
    expect(llamadas, isNot(contains('conectarRed')), reason: 'en Android 9 no existe la unión automática');

    await tester.tap(find.text('Abrir Wi-Fi'));
    await tester.pump();
    expect(llamadas, contains('abrirAjustes'));

    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Conexión de esta tablet'), findsOneWidget);
  });
}
