import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/app.dart';
import 'package:tres_pisos_app/features/auth/almacen_sesion.dart';
import 'package:tres_pisos_app/features/auth/auth_controller.dart';

void main() {
  Widget app() => ProviderScope(
        overrides: [
          datosArranqueProvider.overrideWithValue(
            const DatosArranque(servidor: 'http://192.168.1.50:3000'),
          ),
        ],
        child: const TresPisosApp(),
      );

  testWidgets('sin sesión abre el login con el último servidor', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Restaurante 3 Pisos'), findsOneWidget);
    expect(find.text('http://192.168.1.50:3000'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
  });

  testWidgets('pide usuario y contraseña antes de enviar', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();

    expect(find.text('Escribe tu usuario'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
  });
}
