import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tres_pisos_app/core/tema.dart';
import 'package:tres_pisos_app/features/auth/almacen_sesion.dart';
import 'package:tres_pisos_app/features/auth/auth_controller.dart';
import 'package:tres_pisos_app/features/mesero/captura_pedido_page.dart';
import 'package:tres_pisos_app/features/pedidos/modelos.dart';
import 'package:tres_pisos_app/features/pedidos/pedidos_controller.dart';

void main() {
  const tacos = Producto(id: 1, nombre: 'Tacos de Pastor', precio: 25, categoria: 'Tacos', activo: true);

  Future<void> abrirCaptura(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final almacen = AlmacenSesion(await SharedPreferences.getInstance());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        almacenSesionProvider.overrideWithValue(almacen),
        datosArranqueProvider.overrideWithValue(const DatosArranque()),
        productosProvider.overrideWith((ref) async => const [tacos]),
      ],
      child: MaterialApp(
        theme: crearTema(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const CapturaPedidoPage(mesa: 3)),
                ),
                child: const Text('Inicio'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo pedido'), findsOneWidget);
  }

  testWidgets('con el carrito vacío "Atrás" sale sin preguntar', (tester) async {
    await abrirCaptura(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('¿Descartar el pedido?'), findsNothing);
    expect(find.text('Inicio'), findsOneWidget);
  });

  testWidgets('con productos "Atrás" pide confirmar antes de descartar', (tester) async {
    await abrirCaptura(tester);
    await tester.tap(find.text('Tacos de Pastor'));
    await tester.pump();

    // "Volver" se queda en la captura con el carrito intacto.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar el pedido?'), findsOneWidget);
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo pedido'), findsOneWidget);
    expect(find.text('Ver pedido'), findsOneWidget);

    // El botón atrás del sistema también pregunta; "Descartar" sale.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar el pedido?'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Nuevo pedido'), findsNothing);
  });
}
