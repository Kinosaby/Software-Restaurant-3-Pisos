import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';
import '../pedidos/widgets_pedido.dart';

/// Tablero de cocina: pedidos pendientes y en preparación, del más antiguo al más nuevo.
class CocinaPage extends ConsumerStatefulWidget {
  const CocinaPage({super.key});

  @override
  ConsumerState<CocinaPage> createState() => _CocinaPageState();
}

class _CocinaPageState extends ConsumerState<CocinaPage> {
  late final Timer _reloj;
  final _enCurso = <int>{};

  @override
  void initState() {
    super.initState();
    // Refresca los "hace X min" de las tarjetas.
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _reloj.cancel();
    super.dispose();
  }

  Future<void> _avanzar(Pedido pedido) async {
    final siguiente = switch (pedido.estado) {
      EstadoPedido.pendiente => EstadoPedido.preparando,
      EstadoPedido.preparando => EstadoPedido.listo,
      _ => null,
    };
    if (siguiente == null) return;

    setState(() => _enCurso.add(pedido.id));
    try {
      await ref.read(pedidosActivosProvider.notifier).cambiarEstado(pedido.id, siguiente);
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _enCurso.remove(pedido.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pedidos = ref.watch(pedidosActivosProvider);
    final extras = ref.watch(extrasCocinaProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cocina'),
        actions: const [IndicadorConexion(), MenuUsuario()],
      ),
      body: pedidos.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorConReintento(
          error: e,
          alReintentar: () => ref.invalidate(pedidosActivosProvider),
        ),
        data: (todos) {
          final enCocina = todos.where((p) => p.estado.modificable).toList();
          if (enCocina.isEmpty && extras.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.read(pedidosActivosProvider.notifier).recargar(),
              child: ListView(
                children: const [
                  SizedBox(height: 160),
                  Vacio(icono: Icons.soup_kitchen_outlined, mensaje: 'Sin pedidos por preparar'),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(pedidosActivosProvider.notifier).recargar(),
            child: CustomScrollView(
              slivers: [
                if (extras.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    sliver: SliverList.separated(
                      itemCount: extras.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _TarjetaExtra(
                        extra: extras[i],
                        onHecho: () => ref.read(extrasCocinaProvider.notifier).marcarHecho(extras[i]),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 420,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 320,
                    ),
                    itemCount: enCocina.length,
                    itemBuilder: (context, i) => _TarjetaCocina(
                      pedido: enCocina[i],
                      ocupado: _enCurso.contains(enCocina[i].id),
                      onAvanzar: () => _avanzar(enCocina[i]),
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

class _TarjetaCocina extends StatelessWidget {
  const _TarjetaCocina({required this.pedido, required this.ocupado, required this.onAvanzar});

  final Pedido pedido;
  final bool ocupado;
  final VoidCallback onAvanzar;

  @override
  Widget build(BuildContext context) {
    final pendiente = pedido.estado == EstadoPedido.pendiente;
    final color = Colores.deEstado(pedido.estado);
    final minutos = DateTime.now().difference(pedido.creadoEn).inMinutes;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  pedido.tipo == TipoPedido.llevar ? Icons.takeout_dining : Icons.table_restaurant,
                  color: Colores.acento,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pedido.titulo,
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ChipEstado(pedido.estado),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '#${pedido.id} · ${hora(pedido.creadoEn)} · ${tiempoTranscurrido(pedido.creadoEn)}',
              style: TextStyle(color: minutos >= 20 ? Colores.peligro : Colores.apagado),
            ),
            const Divider(height: 20),
            Expanded(
              child: ListView(
                children: [for (final item in pedido.items) RenglonItem(item, grande: true)],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: ocupado ? null : onAvanzar,
              style: FilledButton.styleFrom(
                backgroundColor: pendiente ? Colores.azul : Colores.exito,
                foregroundColor: Colores.fondo,
              ),
              icon: Icon(pendiente ? Icons.local_fire_department : Icons.check),
              label: Text(pendiente ? 'Empezar a preparar' : 'Marcar listo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaExtra extends StatelessWidget {
  const _TarjetaExtra({required this.extra, required this.onHecho});

  final ExtraPedido extra;
  final VoidCallback onHecho;

  @override
  Widget build(BuildContext context) {
    final titulo = extra.tipo == TipoPedido.llevar ? 'Para llevar (mesa ${extra.mesa})' : 'Mesa ${extra.mesa}';
    return Card(
      color: Colores.dorado.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colores.dorado, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.add_alert, color: Colores.dorado),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Extra · $titulo · pedido #${extra.pedidoId}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colores.dorado),
                  ),
                  const SizedBox(height: 6),
                  for (final item in extra.items) RenglonItem(item, grande: true),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: onHecho, child: const Text('Hecho')),
          ],
        ),
      ),
    );
  }
}
