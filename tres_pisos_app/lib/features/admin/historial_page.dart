import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../caja/ticket.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_repository.dart';
import '../pedidos/widgets_pedido.dart';

/// Todos los pedidos, del más reciente al más antiguo.
final historialProvider = FutureProvider.autoDispose<List<Pedido>>((ref) async {
  final pedidos = await ref.watch(pedidosRepositoryProvider).pedidos();
  return pedidos.reversed.toList();
});

/// Historial para el administrador: hoy o todo, filtro por estado y borrado.
class HistorialPage extends ConsumerStatefulWidget {
  const HistorialPage({super.key});

  @override
  ConsumerState<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends ConsumerState<HistorialPage> {
  bool _soloHoy = true;
  EstadoPedido? _estado;
  int _mostrar = 100;

  Future<void> _eliminar(Pedido pedido) async {
    final ok = await confirmar(
      context,
      titulo: 'Eliminar pedido #${pedido.id}',
      mensaje: pedido.estado == EstadoPedido.pagado
          ? 'El pedido desaparece del historial, pero la venta cobrada se conserva en las métricas. No es un reembolso.'
          : 'El pedido desaparece para todos. No se puede deshacer.',
      accion: 'Eliminar',
      destructiva: true,
    );
    if (!ok) return;
    try {
      await ref.read(pedidosRepositoryProvider).eliminar(pedido.id);
      ref.invalidate(historialProvider);
      if (mounted) mostrarMensaje(context, 'Pedido #${pedido.id} eliminado');
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final historial = ref.watch(historialProvider);
    final hoy = DateTime.now();
    bool esHoy(Pedido p) => p.creadoEn.year == hoy.year && p.creadoEn.month == hoy.month && p.creadoEn.day == hoy.day;

    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos e historial')),
      body: historial.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorConReintento(error: e, alReintentar: () => ref.invalidate(historialProvider)),
        data: (todos) {
          final filtrados = todos.where((p) => (!_soloHoy || esHoy(p)) && (_estado == null || p.estado == _estado)).toList();
          final cobrado = filtrados.where((p) => p.estado == EstadoPedido.pagado).fold<double>(0, (s, p) => s + p.total);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(historialProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Hoy'), icon: Icon(Icons.today)),
                    ButtonSegment(value: false, label: Text('Todo'), icon: Icon(Icons.history)),
                  ],
                  selected: {_soloHoy},
                  onSelectionChanged: (s) => setState(() {
                    _soloHoy = s.first;
                    _mostrar = 100;
                  }),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final estado in [null, ...EstadoPedido.values])
                      ChoiceChip(
                        label: Text(estado?.etiqueta ?? 'Todos'),
                        selected: _estado == estado,
                        onSelected: (_) => setState(() => _estado = estado),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${filtrados.length} pedidos · cobrado ${dinero(cobrado)}', style: const TextStyle(color: Colores.apagado)),
                const SizedBox(height: 12),
                if (filtrados.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Vacio(icono: Icons.inbox_outlined, mensaje: 'Sin pedidos'),
                  ),
                for (final p in filtrados.take(_mostrar))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TarjetaPedido(
                      pedido: p,
                      accion: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!_soloHoy) Text(fechaCorta(p.creadoEn), style: const TextStyle(color: Colores.apagado)),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Ver ticket',
                            icon: const Icon(Icons.receipt_outlined),
                            onPressed: () => mostrarTicket(context, [p]),
                          ),
                          IconButton(
                            tooltip: 'Eliminar',
                            icon: const Icon(Icons.delete_outline, color: Colores.peligro),
                            onPressed: () => _eliminar(p),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (filtrados.length > _mostrar)
                  OutlinedButton(
                    onPressed: () => setState(() => _mostrar += 100),
                    child: Text('Mostrar más (${filtrados.length - _mostrar} restantes)'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
