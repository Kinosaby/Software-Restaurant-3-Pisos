import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';
import '../pedidos/widgets_pedido.dart';

/// Pedidos que cocina ya terminó y están pendientes de cobro.
class CajaPage extends ConsumerStatefulWidget {
  const CajaPage({super.key});

  @override
  ConsumerState<CajaPage> createState() => _CajaPageState();
}

class _CajaPageState extends ConsumerState<CajaPage> {
  final _cobrando = <int>{};

  Future<void> _cobrar(Pedido pedido) async {
    final ok = await confirmar(
      context,
      titulo: 'Cobrar ${pedido.titulo}',
      mensaje: 'Total a cobrar: ${dinero(pedido.total)}',
      accion: 'Cobrado',
    );
    if (!ok || !mounted) return;

    setState(() => _cobrando.add(pedido.id));
    try {
      await ref.read(pedidosActivosProvider.notifier).cambiarEstado(pedido.id, EstadoPedido.pagado);
      if (mounted) mostrarMensaje(context, 'Pedido #${pedido.id} cobrado');
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _cobrando.remove(pedido.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pedidos = ref.watch(pedidosActivosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Caja'),
        actions: const [IndicadorConexion(), MenuUsuario()],
      ),
      body: pedidos.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorConReintento(
          error: e,
          alReintentar: () => ref.invalidate(pedidosActivosProvider),
        ),
        data: (todos) {
          final porCobrar = todos.where((p) => p.estado == EstadoPedido.listo).toList();
          final totalPorCobrar = porCobrar.fold<double>(0, (s, p) => s + p.total);
          return RefreshIndicator(
            onRefresh: () => ref.read(pedidosActivosProvider.notifier).recargar(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.point_of_sale, color: Colores.acento, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            '${porCobrar.length} por cobrar',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          dinero(totalPorCobrar),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colores.dorado,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (porCobrar.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Vacio(icono: Icons.payments_outlined, mensaje: 'Nada pendiente de cobro'),
                  ),
                for (final pedido in porCobrar)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TarjetaPedido(
                      pedido: pedido,
                      onTap: () => context.push('/pedido/${pedido.id}'),
                      accion: FilledButton.icon(
                        onPressed: _cobrando.contains(pedido.id) ? null : () => _cobrar(pedido),
                        icon: const Icon(Icons.payments_outlined),
                        label: Text('Cobrar ${dinero(pedido.total)}'),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
