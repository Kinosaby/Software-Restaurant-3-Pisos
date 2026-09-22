// lib/features/cocina/cocina_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/pedido.dart';
import '../../core/services/api_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/providers/global_state.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/badge_estado.dart';

class CocinaScreen extends ConsumerStatefulWidget {
  const CocinaScreen({super.key});
  @override
  ConsumerState<CocinaScreen> createState() => _CocinaScreenState();
}

class _CocinaScreenState extends ConsumerState<CocinaScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await Future.wait([_loadData(), SocketService.connect()]);
    if (mounted) _listenSocket();
  }

  Future<void> _loadData() async {
    ref.read(loadingProvider.notifier).state = true;
    try {
      final peds = await ApiService.getPedidos();
      ref.read(pedidosProvider.notifier).state =
          peds.map((p) => Pedido.fromJson(p)).toList();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    } finally {
      if (mounted) ref.read(loadingProvider.notifier).state = false;
    }
  }

  void _listenSocket() {
    SocketService.on('nuevo_pedido', (data) {
      final p = Pedido.fromJson(data);
      final current = List<Pedido>.from(ref.read(pedidosProvider));
      ref.read(pedidosProvider.notifier).state = [...current, p];
      final destino = p.tipo == 'llevar' ? 'Para llevar' : 'Mesa ${p.mesa}';
      if (mounted) AppSnackbar.info(context, 'Nuevo pedido — $destino');
    });
    SocketService.on('pedido_actualizado', (data) {
      final p = Pedido.fromJson(data);
      final current = List<Pedido>.from(ref.read(pedidosProvider));
      final idx = current.indexWhere((x) => x.id == p.id);
      if (idx >= 0) {
        current[idx] = p;
      } else {
        current.insert(0, p);
      }
      ref.read(pedidosProvider.notifier).state = [...current];
    });
  }

  Future<void> _cambiarEstado(int id, String estado) async {
    try {
      await ApiService.cambiarEstadoPedido(id, estado);
      await _loadData();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    }
  }

  String _tiempoTranscurrido(DateTime dt) {
    final mins = DateTime.now().difference(dt).inMinutes;
    if (mins < 1) return 'Ahora';
    if (mins < 60) return '${mins}m';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(loadingProvider);
    final pedidos = ref
        .watch(pedidosProvider)
        .where((p) => p.estado == 'pendiente' || p.estado == 'preparando')
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cocina'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/menu')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('${pedidos.length} activos',
                    style: const TextStyle(
                        color: AppColors.amber,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
              ),
              const SizedBox(width: 4),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
            ]),
          ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.amber))
          : pedidos.isEmpty
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Icon(Icons.check_circle_outline,
                          size: 60,
                          color: AppColors.success.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      const Text('Sin pedidos pendientes',
                          style:
                              TextStyle(color: AppColors.muted, fontSize: 15)),
                    ]))
              : RefreshIndicator(
                  color: AppColors.amber,
                  onRefresh: _loadData,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 430,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            mainAxisExtent: 370),
                    itemCount: pedidos.length,
                    itemBuilder: (_, i) => _PedidoCard(
                      pedido: pedidos[i],
                      tiempo: _tiempoTranscurrido(pedidos[i].creadoEn),
                      onCambiar: _cambiarEstado,
                    ),
                  ),
                ),
    );
  }

  @override
  void dispose() {
    SocketService.off('nuevo_pedido');
    SocketService.off('pedido_actualizado');
    super.dispose();
  }
}

// ── Tarjeta de pedido ──────────────────────────────────────
class _PedidoCard extends StatelessWidget {
  final Pedido pedido;
  final String tiempo;
  final Future<void> Function(int, String) onCambiar;

  const _PedidoCard(
      {required this.pedido, required this.tiempo, required this.onCambiar});

  bool get _urgente =>
      DateTime.now().difference(pedido.creadoEn).inMinutes >= 15 &&
      pedido.isPendiente;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: _urgente ? AppColors.danger : AppColors.border,
            width: _urgente ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
          ),
          child: Row(children: [
            Expanded(
                child: Text(
                    pedido.tipo == 'llevar' ? 'Para llevar' : 'Mesa ${pedido.mesa}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15))),
            BadgeEstado(pedido.estado),
          ]),
        ),
        // Tiempo
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Icon(Icons.schedule,
                size: 13, color: _urgente ? AppColors.danger : AppColors.muted),
            const SizedBox(width: 4),
            Text(tiempo,
                style: TextStyle(
                    fontSize: 12,
                    color: _urgente ? AppColors.danger : AppColors.muted)),
            if (_urgente) ...[
              const SizedBox(width: 6),
              const Icon(Icons.warning_amber_rounded,
                  size: 14, color: AppColors.danger)
            ],
          ]),
        ),
        if (pedido.comensal != null && pedido.comensal!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              pedido.comensal!,
              style: const TextStyle(color: AppColors.amber, fontSize: 12),
            ),
          ),
        // Productos
        Expanded(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              children: [
                ...pedido.productos.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                              color: AppColors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(5)),
                          child: Center(
                              child: Text('${p.cantidad}',
                                  style: const TextStyle(
                                      color: AppColors.amber,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.nombre,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                              if (p.nota.isNotEmpty)
                                Text(p.nota,
                                  style: const TextStyle(
                                    color: AppColors.amber, fontSize: 10)),
                            ],
                          ),
                        ),
                      ]),
                    )),
              ]),
        ),
        // Botón acción
        Padding(
          padding: const EdgeInsets.all(10),
          child: pedido.isPendiente
              ? ElevatedButton.icon(
                  onPressed: () => onCambiar(pedido.id, 'preparando'),
                  icon: const Icon(Icons.local_fire_department, size: 16),
                  label: const Text('Preparar', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                )
              : ElevatedButton.icon(
                  onPressed: () => onCambiar(pedido.id, 'listo'),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Listo', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
        ),
      ]),
    );
  }
}
