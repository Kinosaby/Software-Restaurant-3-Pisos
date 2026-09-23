import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../pedidos/modelos.dart';
import '../pedidos/widgets_pedido.dart';
import 'admin_repository.dart';

final resumenMetricasProvider = FutureProvider.autoDispose<ResumenMetricas>(
  (ref) => ref.watch(adminRepositoryProvider).resumen(),
);

final ventasPorDiaProvider = FutureProvider.autoDispose.family<List<VentaDia>, int>(
  (ref, dias) => ref.watch(adminRepositoryProvider).ventas(dias: dias),
);

/// El backend solo devuelve los días con ventas; rellenamos los demás con cero
/// para que la gráfica muestre el hueco en vez de juntar días no consecutivos.
List<VentaDia> completarDias(List<VentaDia> ventas, {required int dias, required DateTime hoy}) {
  final porFecha = {for (final v in ventas) DateUtils.dateOnly(v.fecha): v};
  final fin = DateUtils.dateOnly(hoy);
  return [
    for (var i = dias; i >= 0; i--)
      porFecha[DateTime(fin.year, fin.month, fin.day - i)] ??
          VentaDia(fecha: DateTime(fin.year, fin.month, fin.day - i), pedidos: 0, total: 0),
  ];
}

class MetricasPage extends ConsumerStatefulWidget {
  const MetricasPage({super.key});

  @override
  ConsumerState<MetricasPage> createState() => _MetricasPageState();
}

class _MetricasPageState extends ConsumerState<MetricasPage> {
  int _dias = 7;
  bool _verTabla = false;

  Future<void> _refrescar() async {
    ref
      ..invalidate(resumenMetricasProvider)
      ..invalidate(ventasPorDiaProvider(_dias));
    await ref.read(resumenMetricasProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final resumen = ref.watch(resumenMetricasProvider);
    final ventas = ref.watch(ventasPorDiaProvider(_dias));
    final texto = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Métricas')),
      body: resumen.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorConReintento(error: e, alReintentar: _refrescar),
        data: (r) => RefreshIndicator(
          onRefresh: _refrescar,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Cifra(titulo: 'Ventas de hoy', valor: dinero(r.ventasHoy)),
                  _Cifra(titulo: 'Pedidos de hoy', valor: '${r.pedidosHoy}'),
                  _Cifra(titulo: 'Ventas de la semana', valor: dinero(r.ventasSemana)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Text('Ventas por día', style: texto.titleMedium)),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 7, label: Text('7 días')),
                      ButtonSegment(value: 30, label: Text('30 días')),
                    ],
                    selected: {_dias},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _dias = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                  child: ventas.when(
                    loading: () => const SizedBox(height: 200, child: Cargando()),
                    error: (e, _) => SizedBox(
                      height: 200,
                      child: ErrorConReintento(
                        error: e,
                        alReintentar: () => ref.invalidate(ventasPorDiaProvider(_dias)),
                      ),
                    ),
                    data: (lista) {
                      final dias = completarDias(lista, dias: _dias, hoy: DateTime.now());
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_verTabla) _TablaVentas(dias: dias) else _GraficaVentas(dias: dias),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => setState(() => _verTabla = !_verTabla),
                              icon: Icon(_verTabla ? Icons.bar_chart : Icons.table_rows_outlined),
                              label: Text(_verTabla ? 'Ver gráfica' : 'Ver tabla'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Más pedidos', style: texto.titleMedium),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: r.productosTop.isEmpty
                      ? const Text('Sin datos todavía', style: TextStyle(color: Colores.apagado))
                      : _RankingProductos(productos: r.productosTop),
                ),
              ),
              const SizedBox(height: 24),
              Text('Pedidos por estado (histórico)', style: texto.titleMedium),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    for (final estado in EstadoPedido.values)
                      ListTile(
                        dense: true,
                        leading: ChipEstado(estado),
                        trailing: Text('${r.porEstado[estado] ?? 0}', style: texto.titleMedium),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cifra destacada: una sola magnitud no necesita gráfica.
class _Cifra extends StatelessWidget {
  const _Cifra({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(color: Colores.apagado)),
              const SizedBox(height: 6),
              Text(
                valor,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colores.crema,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barras de una sola serie: un tono, barras finas con 2 px de separación,
/// esquinas superiores de 4 px y la base anclada al eje. Tocar una barra muestra su valor.
class _GraficaVentas extends StatelessWidget {
  const _GraficaVentas({required this.dias});

  final List<VentaDia> dias;

  static final _dia = DateFormat('d MMM', 'es');
  static final _diaSemana = DateFormat('E d', 'es');

  @override
  Widget build(BuildContext context) {
    final maximo = dias.fold<double>(0, (m, d) => d.total > m ? d.total : m);
    final pocos = dias.length <= 10;
    const alto = 180.0;
    const apagado = TextStyle(color: Colores.apagado, fontSize: 11);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(maximo == 0 ? 'Sin ventas en el periodo' : 'Máximo ${dinero(maximo)}', style: apagado),
        const SizedBox(height: 8),
        SizedBox(
          height: alto,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in dias)
                Expanded(
                  child: Tooltip(
                    triggerMode: TooltipTriggerMode.tap,
                    message: '${_dia.format(d.fecha)}\n${dinero(d.total)} · ${d.pedidos} pedidos',
                    // El área táctil es toda la columna, no solo la barra.
                    child: Container(
                      color: Colors.transparent,
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 28),
                        child: Container(
                          height: maximo == 0 ? 0 : (d.total / maximo * alto).clamp(d.total > 0 ? 2 : 0, alto),
                          decoration: const BoxDecoration(
                            color: Colores.acento,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: Colores.apagado.withValues(alpha: 0.4)),
        const SizedBox(height: 4),
        if (pocos)
          // Una etiqueta por barra, encogida si no cabe en su columna.
          Row(
            children: [
              for (final d in dias)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_diaSemana.format(d.fecha), style: apagado),
                  ),
                ),
            ],
          )
        else
          // Con muchas barras solo marcamos inicio, mitad y fin, pegados a los bordes.
          Row(
            children: [
              Text(_dia.format(dias.first.fecha), style: apagado),
              const Spacer(),
              Text(_dia.format(dias[dias.length ~/ 2].fecha), style: apagado),
              const Spacer(),
              Text(_dia.format(dias.last.fecha), style: apagado),
            ],
          ),
      ],
    );
  }
}

class _TablaVentas extends StatelessWidget {
  const _TablaVentas({required this.dias});

  final List<VentaDia> dias;

  static final _fecha = DateFormat('EEE d MMM', 'es');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final d in dias.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(_fecha.format(d.fecha))),
                SizedBox(
                  width: 80,
                  child: Text('${d.pedidos} ped.', textAlign: TextAlign.end, style: const TextStyle(color: Colores.apagado)),
                ),
                SizedBox(width: 110, child: Text(dinero(d.total), textAlign: TextAlign.end)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ranking horizontal: la longitud de la barra es la cantidad; el número va en texto.
class _RankingProductos extends StatelessWidget {
  const _RankingProductos({required this.productos});

  final List<({String nombre, int cantidad})> productos;

  @override
  Widget build(BuildContext context) {
    final maximo = productos.map((p) => p.cantidad).fold(1, (a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final p in productos)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(p.nombre, overflow: TextOverflow.ellipsis)),
                    Text('${p.cantidad}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, c) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 8,
                      width: c.maxWidth * p.cantidad / maximo,
                      decoration: BoxDecoration(
                        color: Colores.acento,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
