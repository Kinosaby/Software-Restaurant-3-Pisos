import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tres_pisos_app/core/tema.dart';
import 'package:tres_pisos_app/features/auth/almacen_sesion.dart';
import 'package:tres_pisos_app/features/auth/auth_controller.dart';
import 'package:tres_pisos_app/features/avisos/avisos.dart';
import 'package:tres_pisos_app/features/cocina/cocina_page.dart';
import 'package:tres_pisos_app/features/pedidos/modelos.dart';
import 'package:tres_pisos_app/features/pedidos/pedidos_controller.dart';
import 'package:tres_pisos_app/features/pedidos/tiempo_real.dart';

Pedido _pedido({required int id, int mesa = 3, String estado = 'preparando', Map<String, dynamic>? pago}) =>
    Pedido.fromJson({
      'id': id,
      'mesa': mesa,
      'estado': estado,
      'tipo': 'aqui',
      'total': '50.00',
      'creado_en': DateTime.now().toUtc().toIso8601String(),
      'pago': ?pago,
      'productos': [
        {'id': id * 10, 'producto_id': 1, 'nombre': 'Tacos', 'cantidad': 1, 'nota': null, 'precio': '50.00'},
      ],
    });

/// Pedidos en memoria: registra los cambios de estado que pide la pantalla.
class _PedidosFalsos extends PedidosActivos {
  _PedidosFalsos(this.iniciales);

  final List<Pedido> iniciales;
  static final cambios = <(int, EstadoPedido)>[];

  @override
  Future<List<Pedido>> build() async => iniciales;

  @override
  Future<Pedido> cambiarEstado(int pedidoId, EstadoPedido estado) async {
    cambios.add((pedidoId, estado));
    final actual = state.value!.firstWhere((p) => p.id == pedidoId);
    // Como la central: lo cobrado por adelantado se cierra al quedar listo.
    final nuevo = estado == EstadoPedido.listo && actual.pago != null ? EstadoPedido.pagado : estado;
    final pedido = Pedido.fromJson({...actual.toJson(), 'estado': nuevo.name});
    state = AsyncData(reemplazarPedido(state.value!, pedido));
    return pedido;
  }
}

void main() {
  setUp(_PedidosFalsos.cambios.clear);

  Future<ProviderContainer> abrir(WidgetTester tester, List<Pedido> pedidos, {Widget? pantalla}) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final almacen = AlmacenSesion(await SharedPreferences.getInstance());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        almacenSesionProvider.overrideWithValue(almacen),
        datosArranqueProvider.overrideWithValue(const DatosArranque()),
        pedidosActivosProvider.overrideWith(() => _PedidosFalsos(pedidos)),
        conexionTiempoRealProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: MaterialApp(theme: crearTema(), home: pantalla ?? const CocinaPage()),
    ));
    await tester.pump();
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(CocinaPage, skipOffstage: false)));
  }

  testWidgets('"Listo" pide confirmar: "Volver" no cambia nada', (tester) async {
    await abrir(tester, [_pedido(id: 1)]);
    expect(find.text('Mesa 3'), findsOneWidget);

    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();
    expect(find.text('¿Mesa 3 ya está lista?'), findsOneWidget);
    expect(find.textContaining('Falta 1 producto por marcar'), findsOneWidget);
    expect(_PedidosFalsos.cambios, isEmpty, reason: 'un toque no basta');

    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(_PedidosFalsos.cambios, isEmpty);
    expect(find.text('Mesa 3'), findsOneWidget);
  });

  testWidgets('tras confirmar se puede deshacer unos segundos y el pedido vuelve con sus casillas', (tester) async {
    final app = await abrir(tester, [_pedido(id: 1), _pedido(id: 2, estado: 'pendiente')]);
    // Cocina ya había marcado el producto de la primera cuenta.
    app.read(marcasCocinaProvider.notifier).alternar('p1', 10);
    await tester.pump();

    await tester.tap(find.text('Todo listo'));
    await tester.pumpAndSettle();
    expect(find.text('¿Mesa 3 ya está toda lista?'), findsOneWidget);
    await tester.tap(find.text('Sí, todo listo'));
    await tester.pumpAndSettle();

    expect(_PedidosFalsos.cambios, [(1, EstadoPedido.listo), (2, EstadoPedido.listo)]);
    expect(find.text('Sin pedidos por preparar'), findsOneWidget);
    expect(find.text('Mesa 3 se marcó como lista'), findsOneWidget);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(_PedidosFalsos.cambios.skip(2), [(1, EstadoPedido.preparando), (2, EstadoPedido.preparando)]);
    expect(find.text('Mesa 3'), findsOneWidget);
    expect(find.text('Deshacer'), findsNothing);
    expect(app.read(marcasCocinaProvider)['p1'], {10}, reason: 'no hay que volver a marcar lo hecho');

    // Deja pasar el aviso de "volvió a cocina".
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('"Deshacer" desaparece solo a los pocos segundos', (tester) async {
    await abrir(tester, [_pedido(id: 1)]);
    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, está listo'));
    await tester.pumpAndSettle();
    expect(find.text('Deshacer'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Deshacer'), findsNothing);
    expect(_PedidosFalsos.cambios, [(1, EstadoPedido.listo)]);
  });

  testWidgets('lo cobrado por adelantado se cierra al quedar listo: no se ofrece deshacer', (tester) async {
    await abrir(tester, [
      _pedido(id: 1, pago: {'efectivo': 50, 'tarjeta': 0, 'fecha': '2026-09-26T20:00:00Z'}),
    ]);
    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, está listo'));
    await tester.pumpAndSettle();

    expect(_PedidosFalsos.cambios, [(1, EstadoPedido.listo)]);
    expect(find.text('Deshacer'), findsNothing);
  });

  testWidgets('la pantalla de cocina solo cuenta como "a la vista" en su pestaña', (tester) async {
    final seccion = ValueNotifier(0);
    addTearDown(seccion.dispose);
    final app = await abrir(
      tester,
      [_pedido(id: 1)],
      // Como el inicio del administrador: cocina sigue montada en otra pestaña.
      pantalla: ValueListenableBuilder(
        valueListenable: seccion,
        builder: (_, indice, _) => IndexedStack(
          index: indice,
          children: const [Scaffold(body: Text('Salón')), CocinaPage()],
        ),
      ),
    );
    final pantalla = app.read(pantallaCocinaProvider);
    expect(pantalla.aLaVista, isFalse);

    seccion.value = 1;
    await tester.pump();
    expect(pantalla.aLaVista, isTrue);

    seccion.value = 0;
    await tester.pump();
    expect(pantalla.aLaVista, isFalse);
  });
}
