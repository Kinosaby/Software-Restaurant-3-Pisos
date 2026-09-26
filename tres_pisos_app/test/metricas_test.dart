import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tres_pisos_app/core/tema.dart';
import 'package:tres_pisos_app/features/admin/admin_repository.dart';
import 'package:tres_pisos_app/features/admin/metricas_page.dart';
import 'package:tres_pisos_app/features/pedidos/modelos.dart';

/// Forma de GET /api/metricas/resumen (metricas.service.js).
const resumenJson = {
  'success': true,
  'dia': {'total_ventas': '1250.50', 'total_pedidos': 14},
  'semana': '8420.00',
  'estados': [
    {'estado': 'pagado', 'cantidad': 120},
    {'estado': 'pendiente', 'cantidad': 3},
  ],
  'productosTop': [
    {'nombre': 'Tacos de Pastor', 'total_pedido': 58},
    {'nombre': 'Refresco', 'total_pedido': 41},
  ],
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('ResumenMetricas lee importes como texto', () {
    final r = ResumenMetricas.fromJson(resumenJson);
    expect(r.ventasHoy, 1250.5);
    expect(r.pedidosHoy, 14);
    expect(r.ventasSemana, 8420);
    expect(r.porEstado[EstadoPedido.pagado], 120);
    expect(r.porEstado[EstadoPedido.listo], isNull);
    expect(r.productosTop.first, (nombre: 'Tacos de Pastor', cantidad: 58));
  });

  test('VentaDia no se corre al día anterior por la zona horaria', () {
    // Una fecha con hora UTC no debe moverse al día anterior en México.
    final v = VentaDia.fromJson({'fecha': '2026-09-21T00:00:00.000Z', 'pedidos': 9, 'total': '980.00'});
    expect(v.fecha, DateTime(2026, 9, 21));
    expect(v.total, 980);
  });

  test('completarDias rellena con cero los días sin ventas', () {
    final ventas = [
      VentaDia(fecha: DateTime(2026, 9, 20), pedidos: 3, total: 300),
      VentaDia(fecha: DateTime(2026, 9, 22), pedidos: 1, total: 90),
    ];
    final dias = completarDias(ventas, dias: 3, hoy: DateTime(2026, 9, 22, 18, 30));

    expect(dias.map((d) => d.fecha.day), [19, 20, 21, 22]);
    expect(dias.map((d) => d.total), [0, 300, 0, 90]);
  });

  testWidgets('la pantalla de métricas muestra cifras, gráfica y tabla', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final hoy = DateTime.now();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        resumenMetricasProvider.overrideWith((ref) async => ResumenMetricas.fromJson(resumenJson)),
        ventasPorDiaProvider.overrideWith(
          (ref, dias) async => [VentaDia(fecha: hoy, pedidos: 14, total: 1250.5)],
        ),
      ],
      child: MaterialApp(theme: crearTema(), home: const MetricasPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ventas de hoy'), findsOneWidget);
    expect(find.textContaining('1,250.50'), findsWidgets);
    expect(find.text('Tacos de Pastor'), findsOneWidget);

    await tester.tap(find.text('Ver tabla'));
    await tester.pumpAndSettle();
    expect(find.text('14 ped.'), findsOneWidget);

    await tester.tap(find.text('30 días'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
