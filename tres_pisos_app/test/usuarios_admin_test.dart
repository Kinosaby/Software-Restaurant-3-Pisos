import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tres_pisos_app/core/tema.dart';
import 'package:tres_pisos_app/features/admin/usuarios_admin_page.dart';
import 'package:tres_pisos_app/features/auth/almacen_sesion.dart';
import 'package:tres_pisos_app/features/auth/auth_controller.dart';

void main() {
  testWidgets('"Nuevo usuario" cabe en horizontal con el teclado abierto', (tester) async {
    // Teléfono en horizontal (800×400 lógicos) con el teclado ocupando la mitad.
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 2;
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        almacenSesionProvider.overrideWithValue(AlmacenSesion(await SharedPreferences.getInstance())),
        datosArranqueProvider.overrideWithValue(const DatosArranque()),
        usuariosAdminProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(theme: crearTema(), home: const UsuariosAdminPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'sin desbordes con poco alto');
    expect(find.text('Nuevo usuario'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    final zona = tester.getSize(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(Scrollable)).first,
    );
    // Antes el título y los botones se comían todo el alto y los campos quedaban en 0 px.
    expect(zona.height, greaterThan(100));

    // Los campos se desplazan hasta el último (Rol) sin salirse del diálogo.
    await tester.dragUntilVisible(
      find.text('Rol'),
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(Scrollable)).first,
      const Offset(0, -40),
    );
    expect(find.text('Rol'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
