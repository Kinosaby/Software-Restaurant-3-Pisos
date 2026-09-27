import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tres_pisos_app/app.dart';
import 'package:tres_pisos_app/central/central.dart';
import 'package:tres_pisos_app/central/servidor_central.dart';
import 'package:tres_pisos_app/features/auth/almacen_sesion.dart';
import 'package:tres_pisos_app/features/auth/auth_controller.dart';
import 'package:tres_pisos_app/features/auth/sesion.dart';
import 'package:tres_pisos_app/features/conexion/enlace_qr.dart';

void main() {
  const datos = DatosEnlace(
    ips: ['192.168.1.20', '10.0.0.5'],
    puerto: 8787,
    codigo: 'K7P2-9QXM',
    nombre: 'Restaurante 3 Pisos',
  );

  test('el QR lleva IPs, puerto, código y nombre, y se vuelve a leer igual', () {
    final texto = datos.uri.toString();
    expect(texto, startsWith('trespisos://enlace?'));
    final leido = DatosEnlace.leer(texto)!;
    expect(leido.ips, datos.ips);
    expect(leido.puerto, 8787);
    expect(leido.codigo, 'K7P2-9QXM');
    expect(leido.nombre, 'Restaurante 3 Pisos');
    expect(leido.urls, ['http://192.168.1.20:8787', 'http://10.0.0.5:8787']);

    // Cabe de sobra en un QR que cualquier cámara lee.
    expect(QrCode(payload: QrPayload.fromString(texto)).moduleCount, lessThanOrEqualTo(49));
  });

  test('rechaza QR ajenos o manipulados', () {
    expect(DatosEnlace.leer('https://ejemplo.com'), isNull);
    expect(DatosEnlace.leer('trespisos://enlace?ip=192.168.1.20&c=corto'), isNull);
    expect(DatosEnlace.leer('trespisos://enlace?ip=999.1.1.1&c=K7P2-9QXM'), isNull);
    expect(DatosEnlace.leer('trespisos://enlace?ip=central.local&c=K7P2-9QXM'), isNull);
    expect(DatosEnlace.leer('trespisos://otra?ip=192.168.1.20&c=K7P2-9QXM'), isNull);
    // Código en minúsculas o sin guion: se normaliza.
    expect(DatosEnlace.leer('trespisos://enlace?ip=192.168.1.20&c=k7p29qxm')?.codigo, 'K7P2-9QXM');
  });

  test('la IP del Wi-Fi va primero', () {
    expect(ordenarIps(['100.64.0.1', '172.20.1.4', '10.1.1.1', '192.168.0.9']),
        ['192.168.0.9', '10.1.1.1', '172.20.1.4', '100.64.0.1']);
  });

  testWidgets('abrir la app con el QR de una central pide confirmar la conexión', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const actual = Conexion(modo: ModoConexion.enlazada, url: 'http://192.168.1.99:8787', enlace: 'AAAA-BBBB');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        almacenSesionProvider.overrideWithValue(AlmacenSesion(await SharedPreferences.getInstance())),
        datosArranqueProvider.overrideWithValue(const DatosArranque(conexion: actual)),
        enlaceInicialProvider.overrideWithValue(datos),
      ],
      child: const TresPisosApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Conexión de esta tablet'), findsOneWidget);
    expect(find.widgetWithText(AlertDialog, 'Conectar a la central'), findsOneWidget);
    expect(find.textContaining('192.168.1.20 · 10.0.0.5'), findsOneWidget);

    // Cancelar no cambia nada.
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('una tablet nueva se enlaza con el QR y pasa al inicio de sesión', (tester) async {
    // Central real en localhost; las pruebas de widgets bloquean HTTP por defecto.
    HttpOverrides.global = null;
    final (carpeta, central, servidor) = (await tester.runAsync(() async {
      final carpeta = await Directory.systemTemp.createTemp('enlace_qr');
      final central = await Central.abrir(carpeta, iteraciones: 1000);
      await central.inicializar(admin: 'admin', password: 'secreto1', menu: const []);
      final servidor = ServidorCentral(central, puerto: 0, anunciar: false);
      await servidor.iniciar();
      return (carpeta, central, servidor);
    }))!;
    addTearDown(() => tester.runAsync(() async {
          await servidor.detener();
          await central.cerrar();
          await carpeta.delete(recursive: true);
        }));

    SharedPreferences.setMockInitialValues({});
    final almacen = AlmacenSesion(await SharedPreferences.getInstance());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        almacenSesionProvider.overrideWithValue(almacen),
        datosArranqueProvider.overrideWithValue(const DatosArranque()),
        enlaceInicialProvider.overrideWithValue(DatosEnlace(
          ips: const ['127.0.0.1'],
          puerto: servidor.puertoEnUso,
          codigo: central.codigoEnlace,
          nombre: 'Restaurante 3 Pisos',
        )),
      ],
      child: const TresPisosApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.widgetWithText(FilledButton, 'Conectar'));
    // La petición a la central es E/S real: se le da tiempo fuera del reloj falso.
    for (var i = 0; i < 20 && find.text('Entrar').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Entrar'), findsOneWidget);
    expect(almacen.cargar().conexion?.modo, ModoConexion.enlazada);

    // Deja vencer la conexión HTTP reutilizable antes de cerrar la prueba.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
  });
}
