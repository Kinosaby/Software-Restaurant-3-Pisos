import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:tres_pisos_app/core/tema.dart';
import 'package:tres_pisos_app/features/caja/cobro.dart';
import 'package:tres_pisos_app/features/caja/ticket.dart';
import 'package:tres_pisos_app/features/pedidos/modelos.dart';
import 'package:tres_pisos_app/features/pedidos/pedidos_controller.dart';

/// Hora a la que la central registró el cobro (días antes de "hoy").
const fechaCobro = '2026-09-20T19:30:00Z';

Pedido pedido({int id = 7, String estado = 'listo', String creadoEn = '2026-09-20T18:00:00Z', String? cobradoEn}) =>
    Pedido.fromJson({
      'id': id,
      'mesa': 4,
      'estado': estado,
      'tipo': 'aqui',
      'total': '50.00',
      'creado_en': creadoEn,
      'productos': [
        {'id': id * 10, 'producto_id': 1, 'nombre': 'Tacos', 'cantidad': 1, 'nota': null, 'precio': '50.00'},
      ],
      if (cobradoEn != null) 'pago': {'efectivo': 0, 'tarjeta': 50, 'fecha': cobradoEn},
    });

/// Central de mentira: cobra y devuelve la cuenta con la fecha que ella registró.
class PedidosFalsos extends PedidosActivos {
  @override
  Future<List<Pedido>> build() async => [pedido()];

  @override
  Future<List<Pedido>> cobrar(Iterable<int> ids, Pago pago, {String? operacion}) async =>
      [for (final id in ids) pedido(id: id, estado: 'pagado', cobradoEn: fechaCobro)];
}

void main() {
  late final formato = DateFormat("d 'de' MMMM yyyy, HH:mm", 'es');
  late final textoCobro = formato.format(DateTime.parse(fechaCobro).toLocal());

  setUpAll(() => initializeDateFormatting('es'));

  test('la fecha del ticket es la del cobro que registró la central', () {
    final hoy = DateTime(2026, 10, 2, 13);
    final cobro = DateTime.parse(fechaCobro).toLocal();

    expect(fechaDelTicket([pedido(estado: 'pagado', cobradoEn: fechaCobro)], ahora: hoy), cobro);
    // Cobrado por adelantado: sigue en cocina pero ya tiene su hora de cobro.
    expect(fechaDelTicket([pedido(estado: 'preparando', cobradoEn: fechaCobro)], ahora: hoy), cobro);
    // Varias cuentas cobradas juntas o por separado: la del último cobro.
    expect(
      fechaDelTicket([
        pedido(id: 1, estado: 'pagado', cobradoEn: '2026-09-20T19:10:00Z'),
        pedido(id: 2, estado: 'pagado', cobradoEn: fechaCobro),
      ], ahora: hoy),
      cobro,
    );
    // Cobro antiguo sin fecha guardada: la del pedido, nunca la de hoy.
    expect(fechaDelTicket([pedido(estado: 'pagado')], ahora: hoy), DateTime.parse('2026-09-20T18:00:00Z').toLocal());
    // Cuenta por pagar: se enseña con la hora del momento.
    expect(fechaDelTicket([pedido()], ahora: hoy), hoy);
  });

  testWidgets('al reabrir el ticket de una venta anterior sale la fecha del cobro, no la de hoy', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TicketVista(
            pedidos: [pedido(estado: 'pagado', cobradoEn: fechaCobro)],
            restaurante: 'Restaurante 3 Pisos',
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text(textoCobro), findsOneWidget);
    expect(find.text(formato.format(DateTime.now())), findsNothing);
  });

  testWidgets('al cobrar, el ticket se abre solo y se queda hasta que alguien lo cierra', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    var terminado = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [pedidosActivosProvider.overrideWith(PedidosFalsos.new)],
      child: MaterialApp(
        theme: crearTema(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: FilledButton(
                onPressed: () async {
                  await mostrarCobro(context, ref, [pedido()]);
                  terminado = true;
                },
                child: const Text('Abrir cobro'),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Abrir cobro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tarjeta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cobrar con tarjeta'));
    await tester.pumpAndSettle();

    // Sin tocar nada más ya está el ticket, con la hora que registró la central.
    expect(find.byType(TicketVista), findsOneWidget);
    expect(find.text('¡Gracias por su visita!'), findsOneWidget);
    expect(find.text(textoCobro), findsOneWidget);

    // No se cierra solo...
    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();
    expect(find.byType(TicketVista), findsOneWidget);
    // ...ni al tocar fuera por accidente.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(TicketVista), findsOneWidget);
    expect(terminado, isFalse);

    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(TicketVista), findsNothing);
    expect(terminado, isTrue);
  });
}
