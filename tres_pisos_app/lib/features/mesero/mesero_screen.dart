// lib/features/mesero/mesero_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/pedido.dart';
import '../../core/models/producto.dart';
import '../../core/services/api_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/providers/global_state.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/badge_estado.dart';

class MeseroScreen extends ConsumerStatefulWidget {
  const MeseroScreen({super.key});
  @override
  ConsumerState<MeseroScreen> createState() => _MeseroScreenState();
}

class _MeseroScreenState extends ConsumerState<MeseroScreen> {
  final _mesaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _listenSocket();
  }

  Future<void> _loadData() async {
    ref.read(loadingProvider.notifier).state = true;
    try {
      final prods = await ApiService.getProductos();
      final peds  = await ApiService.getPedidos();
      if (!mounted) return;
      ref.read(productosProvider.notifier).state = prods.map((p) => Producto.fromJson(p)).toList();
      ref.read(pedidosProvider.notifier).state   = peds.map((p) => Pedido.fromJson(p)).toList();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    } finally {
      if (mounted) ref.read(loadingProvider.notifier).state = false;
    }
  }

  void _listenSocket() {
    SocketService.on('nuevo_pedido', (data) {
      if (!mounted) return;
      final p = Pedido.fromJson(data);
      final current = List<Pedido>.from(ref.read(pedidosProvider));
      ref.read(pedidosProvider.notifier).state = [p, ...current];
    });
    SocketService.on('pedido_actualizado', (data) {
      if (!mounted) return;
      final p = Pedido.fromJson(data);
      final current = List<Pedido>.from(ref.read(pedidosProvider));
      final idx = current.indexWhere((x) => x.id == p.id);
      if (idx >= 0) { current[idx] = p; } else { current.insert(0, p); }
      ref.read(pedidosProvider.notifier).state = [...current];
      if (mounted) AppSnackbar.info(context, 'Pedido #${p.id} → ${p.estado}');
    });
  }

  Future<void> _enviarPedido() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      if (mounted) AppSnackbar.error(context, 'El carrito esta vacio');
      return;
    }
    final mesa = int.tryParse(_mesaCtrl.text);
    if (mesa == null || mesa < 1) {
      if (mounted) AppSnackbar.error(context, 'Ingresa un numero de mesa valido');
      return;
    }

    ref.read(loadingProvider.notifier).state = true;
    try {
      await ApiService.createPedido({
        'mesa': mesa,
        'productos': cart.map((i) => {
          'producto_id': i.productoId,
          'cantidad':    i.cantidad,
          'nota':        i.nota,
        }).toList(),
      });
      ref.read(cartProvider.notifier).clear();
      _mesaCtrl.clear();
      if (mounted) AppSnackbar.ok(context, 'Pedido enviado — Mesa $mesa');
      await _loadData();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    } finally {
      if (mounted) ref.read(loadingProvider.notifier).state = false;
    }
  }

  Future<void> _cobrar(int id) async {
    try {
      await ApiService.cambiarEstadoPedido(id, 'pagado');
      if (mounted) AppSnackbar.ok(context, 'Pedido cobrado');
      await _loadData();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    }
  }

  Future<void> _cancelar(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Cancelar pedido'),
        content: Text('¿Cancelar pedido #$id?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Si', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.cancelarPedido(id);
      if (mounted) AppSnackbar.ok(context, 'Pedido #$id cancelado');
      await _loadData();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    }
  }

  void _mostrarCarrito() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CarritoSheet(mesaCtrl: _mesaCtrl, onEnviar: _enviarPedido),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productos = ref.watch(productosProvider).where((p) => p.activo).toList();
    final pedidos   = ref.watch(pedidosProvider)
        .where((p) => p.estado != 'pagado' && p.estado != 'cancelado')
        .toList();
    final cartCount = ref.watch(cartProvider.select((c) => c.fold(0, (a, i) => a + i.cantidad)));
    final loading   = ref.watch(loadingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesero'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/menu'),
        ),
        actions: [
          Stack(children: [
            IconButton(
              icon: const Icon(Icons.shopping_cart_outlined),
              onPressed: _mostrarCarrito,
            ),
            if (cartCount > 0)
              Positioned(
                right: 6, top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.amber,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$cartCount',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ]),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
        : RefreshIndicator(
            color: AppColors.amber,
            onRefresh: _loadData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Catálogo ──
                const Text('Menu',
                  style: TextStyle(
                    color: AppColors.amber, fontSize: 13,
                    fontWeight: FontWeight.w700, letterSpacing: 1,
                  )),
                const SizedBox(height: 12),
                if (productos.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Sin productos disponibles',
                        style: TextStyle(color: AppColors.muted)),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.6,
                    ),
                    itemCount: productos.length,
                    itemBuilder: (_, i) {
                      final p = productos[i];
                      return GestureDetector(
                        onTap: () {
                          ref.read(cartProvider.notifier).add(p);
                          AppSnackbar.ok(context, '${p.nombre} agregado');
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(p.nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                              Text('\$${p.precio.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: AppColors.amber,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                )),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                // ── Pedidos activos ──
                const SizedBox(height: 28),
                const Text('Pedidos Activos',
                  style: TextStyle(
                    color: AppColors.amber, fontSize: 13,
                    fontWeight: FontWeight.w700, letterSpacing: 1,
                  )),
                const SizedBox(height: 12),
                if (pedidos.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Sin pedidos activos',
                        style: TextStyle(color: AppColors.muted)),
                    ),
                  )
                else
                  ...pedidos.map((p) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(children: [
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('Mesa ${p.mesa}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(width: 8),
                            BadgeEstado(p.estado),
                          ]),
                          const SizedBox(height: 4),
                          Text('#${p.id}',
                            style: const TextStyle(
                              color: AppColors.muted, fontSize: 12)),
                        ],
                      )),
                      Text('\$${p.total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.amber, fontWeight: FontWeight.w700)),
                      if (p.isListo) ...[
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _cobrar(p.id),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8)),
                          child: const Text('Cobrar',
                            style: TextStyle(fontSize: 12)),
                        ),
                      ],
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.close,
                          color: AppColors.danger, size: 18),
                        onPressed: () => _cancelar(p.id),
                      ),
                    ]),
                  )),
              ]),
            ),
          ),
    );
  }

  @override
  void dispose() {
    _mesaCtrl.dispose();
    SocketService.off('nuevo_pedido');
    SocketService.off('pedido_actualizado');
    super.dispose();
  }
}

// ── Carrito BottomSheet ──────────────────────────────────────
class _CarritoSheet extends ConsumerWidget {
  final TextEditingController mesaCtrl;
  final VoidCallback          onEnviar;
  const _CarritoSheet({required this.mesaCtrl, required this.onEnviar});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart  = ref.watch(cartProvider);
    final total = cart.fold(0.0, (sum, i) => sum + i.subtotal);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, ctrl) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Icon(Icons.shopping_cart_outlined, color: AppColors.amber),
              const SizedBox(width: 10),
              const Text('Carrito',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(
                onPressed: () => ref.read(cartProvider.notifier).clear(),
                child: const Text('Limpiar',
                  style: TextStyle(color: AppColors.muted)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: mesaCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Mesa #',
                prefixIcon: Icon(Icons.table_restaurant_outlined, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: cart.isEmpty
              ? const Center(
                  child: Text('El carrito esta vacio',
                    style: TextStyle(color: AppColors.muted)),
                )
              : ListView.builder(
                  controller: ctrl,
                  itemCount: cart.length,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemBuilder: (_, i) {
                    final item = cart[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(child: Text(item.nombre,
                              style: const TextStyle(fontWeight: FontWeight.w600))),
                            Text('\$${item.subtotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: AppColors.amber,
                                fontWeight: FontWeight.w700,
                              )),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            IconButton(
                              onPressed: () => ref.read(cartProvider.notifier)
                                  .changeQty(item.productoId, -1),
                              icon: const Icon(Icons.remove_circle_outline,
                                size: 22, color: AppColors.amber),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 12),
                            Text('${item.cantidad}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(width: 12),
                            IconButton(
                              onPressed: () => ref.read(cartProvider.notifier)
                                  .changeQty(item.productoId, 1),
                              icon: const Icon(Icons.add_circle_outline,
                                size: 22, color: AppColors.amber),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 130,
                              child: TextField(
                                onChanged: (v) => ref.read(cartProvider.notifier)
                                    .setNota(item.productoId, v),
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: 'Nota...',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                ),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    );
                  },
                ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total', style: TextStyle(color: AppColors.muted)),
                Text('\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppColors.amber,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  )),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onEnviar();
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('Enviar Pedido a Cocina'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
