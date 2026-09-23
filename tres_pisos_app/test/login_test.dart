import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tres_pisos_app/app.dart';
import 'package:tres_pisos_app/features/auth/almacen_sesion.dart';
import 'package:tres_pisos_app/features/auth/auth_controller.dart';
import 'package:tres_pisos_app/features/auth/sesion.dart';

void main() {
  Future<Widget> app({Conexion? conexion}) async {
    SharedPreferences.setMockInitialValues({});
    final almacen = AlmacenSesion(await SharedPreferences.getInstance());
    return ProviderScope(
      overrides: [
        almacenSesionProvider.overrideWithValue(almacen),
        datosArranqueProvider.overrideWithValue(DatosArranque(conexion: conexion)),
      ],
      child: const TresPisosApp(),
    );
  }

  const enlazada = Conexion(modo: ModoConexion.enlazada, url: 'http://192.168.1.20:8787', enlace: 'K7P2-9QXM');

  testWidgets('la primera vez pide elegir cómo se conecta la tablet', (tester) async {
    await tester.pumpWidget(await app());
    // La pantalla busca centrales en el Wi-Fi (E/S real): su indicador no se detiene en el reloj simulado.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Conexión de esta tablet'), findsOneWidget);
    expect(find.text('Central de cocina'), findsOneWidget);
    expect(find.text('Conectada a la central'), findsOneWidget);
    expect(find.textContaining('Servidor'), findsNothing, reason: 'solo red local, sin servidor en internet');
  });

  testWidgets('con la conexión configurada abre el login y la muestra', (tester) async {
    await tester.pumpWidget(await app(conexion: enlazada));
    await tester.pumpAndSettle();

    expect(find.text('Restaurante 3 Pisos'), findsOneWidget);
    expect(find.text('Conectada a la central'), findsOneWidget);
    expect(find.text('http://192.168.1.20:8787'), findsOneWidget);
  });

  testWidgets('pide usuario y contraseña antes de enviar', (tester) async {
    await tester.pumpWidget(await app(conexion: enlazada));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();

    expect(find.text('Escribe tu usuario'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
  });
}
