import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../caja/cobro.dart';
import '../caja/ticket.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';
import '../pedidos/widgets_pedido.dart';
import 'pedidos_page.dart';

class PedidoDetallePage extends ConsumerStatefulWidget {
  const PedidoDetallePage({super.key, required this.pedidoId});

  final int pedidoId;

  @override
  ConsumerState<PedidoDetallePage> createState() => _PedidoDetallePageState();
}

class _PedidoDetallePageState extends ConsumerState<PedidoDetallePage> {
  bool _ocupado = false;

  /// Ejecuta la acción y, si sale bien, vuelve a la lista (el pedido deja de estar activo).
  Future<void> _accionYSalir(Future<void> Function() accion, String exito) async {
    setState(() => _ocupado = true);
    try {
      await accion();
      if (!mounted) return;
      mostrarMensaje(context, exito);
      context.pop();
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _cobrar(Pedido pedido) async {
    await mostrarCobro(context, ref, [pedido]);
    if (!mounted) return;
    final sigueActivo = ref.read(pedidosActivosProvider).value?.any((p) => p.id == pedido.id) ?? false;
    if (!sigueActivo) context.pop();
  }

  Future<void> _cancelar(Pedido pedido) async {
    final ok = await confirmar(
      context,
      titulo: 'Cancelar pedido #${pedido.id}',
      mensaje: 'Cocina dejará de verlo. Esta acción no se puede deshacer.',
      accion: 'Cancelar pedido',
      destructiva: true,
    );
    if (!ok || !mounted) return;
    await _accionYSalir(
      () => ref.read(pedidosActivosProvider.notifier).cancelar(pedido.id),
      'Pedido #${pedido.id} cancelado',
    );
  }

  @override
  Widget build(BuildContext context) {
    final pedidos = ref.watch(pedidosActivosProvider);
    final rol = ref.watch(authControllerProvider)?.usuario.rol;
    final pedido = pedidos.value?.where((p) => p.id == widget.pedidoId).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text('Pedido #${widget.pedidoId}')),
      body: switch (pedido) {
        null when !pedidos.hasValue && pedidos.hasError => ErrorConReintento(
            error: pedidos.error!,
            alReintentar: () => ref.invalidate(pedidosActivosProvider),
          ),
        null when !pedidos.hasValue => const Cargando(),
        null => const Vacio(
            icono: Icons.check_circle_outline,
            mensaje: 'Este pedido ya no está activo',
          ),
        final pedido => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: Text(pedido.titulo, style: Theme.of(context).textTheme.headlineSmall)),
                  ChipEstado(pedido.estado),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${pedido.tipo.etiqueta} · ${hora(pedido.creadoEn)} (${tiempoTranscurrido(pedido.creadoEn)})',
                style: const TextStyle(color: Colores.apagado),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (final item in pedido.items) RenglonItem(item, mostrarPrecio: true),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Text('Total', style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          Text(
                            dinero(pedido.total),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colores.dorado,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (rol?.tomaPedidos ?? false)
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : () => context.push('/pedido/${pedido.id}/agregar'),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar productos'),
                ),
              if ((rol?.tomaPedidos ?? false) && pedido.estado.modificable) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : () => context.push('/pedido/${pedido.id}/editar'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar pedido o cambiar mesa'),
                ),
              ],
              if ((rol?.cobra ?? false) && pedido.estado == EstadoPedido.listo) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _ocupado ? null : () => _cobrar(pedido),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text('Cobrar ${dinero(pedido.total)}'),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => mostrarTicket(context, [pedido]),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Compartir cuenta'),
                    ),
                  ),
                  if (rol?.tomaPedidos ?? false) ...[
                    const SizedBox(width: 10),
                    Expanded(child: BotonRepetir(pedido: pedido)),
                  ],
                ],
              ),
              if ((rol?.tomaPedidos ?? false) && pedido.estado.modificable) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _ocupado ? null : () => _cancelar(pedido),
                  style: TextButton.styleFrom(foregroundColor: Colores.peligro),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelar pedido'),
                ),
              ],
            ],
          ),
      },
    );
  }
}
