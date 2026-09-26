import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';
import '../pedidos/widgets_pedido.dart';
import 'cobro.dart';

/// Cuentas que cocina ya terminó, agrupadas por mesa para cobrarlas juntas o por separado.
class CajaPage extends ConsumerWidget {
  const CajaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidos = ref.watch(pedidosActivosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Caja'),
        actions: const [IndicadorConexion(), MenuUsuario()],
      ),
      body: Column(
        children: [
          const AvisoSinConexion(),
          Expanded(
            child: pedidos.when(
              loading: () => const Cargando(),
              error: (e, _) => ErrorConReintento(
                error: e,
                alReintentar: () => ref.invalidate(pedidosActivosProvider),
              ),
              data: (todos) {
                final porCobrar = todos.where((p) => p.estado == EstadoPedido.listo).toList();
                final totalPorCobrar = porCobrar.fold<double>(0, (s, p) => s + p.total);
                final grupos = <String, List<Pedido>>{};
                for (final p in porCobrar) {
                  grupos.putIfAbsent(p.tipo == TipoPedido.llevar ? 'Para llevar #${p.id}' : 'Mesa ${p.mesa}', () => []).add(p);
                }

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
                                child: Text('${porCobrar.length} por cobrar', style: Theme.of(context).textTheme.titleMedium),
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
                      for (final MapEntry(key: titulo, value: cuentas) in grupos.entries) ...[
                        Row(
                          children: [
                            Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleMedium)),
                            if (cuentas.length > 1)
                              FilledButton.tonalIcon(
                                onPressed: () => mostrarCobro(context, ref, cuentas),
                                icon: const Icon(Icons.payments_outlined, size: 18),
                                label: Text('Todo · ${dinero(cuentas.fold(0, (s, p) => s + p.total))}'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final pedido in cuentas)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: TarjetaPedido(
                              pedido: pedido,
                              onTap: () => context.push('/pedido/${pedido.id}'),
                              accion: FilledButton.icon(
                                onPressed: () => mostrarCobro(context, ref, [pedido]),
                                icon: const Icon(Icons.payments_outlined),
                                label: Text('Cobrar ${dinero(pedido.total)}'),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
