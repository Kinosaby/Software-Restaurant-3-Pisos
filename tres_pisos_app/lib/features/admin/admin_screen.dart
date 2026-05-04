// lib/features/admin/admin_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/pedido.dart';
import '../../core/models/producto.dart';
import '../../core/models/user.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/providers/global_state.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/badge_estado.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});
  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map<String, dynamic> _metricas = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadAll();
  }

  Future<void> _loadAll() async {
    ref.read(loadingProvider.notifier).state = true;
    try {
      final results = await Future.wait([
        ApiService.getMetricas(),
        ApiService.getUsuarios(),
        ApiService.getProductos(),
        ApiService.getPedidos(),
      ]);
      setState(() => _metricas = results[0] as Map<String, dynamic>);
      ref.read(usuariosProvider.notifier).state =
          (results[1] as List).map((u) => UserModel.fromJson(u)).toList();
      ref.read(productosProvider.notifier).state =
          (results[2] as List).map((p) => Producto.fromJson(p)).toList();
      ref.read(pedidosProvider.notifier).state =
          (results[3] as List).map((p) => Pedido.fromJson(p)).toList();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    } finally {
      ref.read(loadingProvider.notifier).state = false;
    }
  }

  Widget _statCard(String label, String value) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: AppColors.amber,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
        ]),
      );

  String _currency(dynamic n) =>
      '\$${double.tryParse(n.toString())?.toStringAsFixed(2) ?? '0.00'}';

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(loadingProvider);
    final usuarios = ref.watch(usuariosProvider);
    final productos = ref.watch(productosProvider);
    final pedidos = ref.watch(pedidosProvider);

    final dia = _metricas['dia'] as Map? ?? {};
    final semana = _metricas['semana'] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administrador'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/menu')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll)
        ],
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(text: 'Usuarios'),
          Tab(text: 'Productos'),
          Tab(text: 'Pedidos'),
        ]),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.amber))
          : Column(children: [
              // Stats
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _statCard('Pedidos hoy', '${dia['total_pedidos'] ?? 0}'),
                    const SizedBox(width: 10),
                    _statCard(
                        'Ventas del dia', _currency(dia['total_ventas'] ?? 0)),
                    const SizedBox(width: 10),
                    _statCard('Ventas semana', _currency(semana)),
                    const SizedBox(width: 10),
                    _statCard('Productos', '${productos.length}'),
                    const SizedBox(width: 10),
                    _statCard('Usuarios', '${usuarios.length}'),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(controller: _tabs, children: [
                  _UsuariosTab(usuarios: usuarios, onRefresh: _loadAll),
                  _ProductosTab(productos: productos, onRefresh: _loadAll),
                  _PedidosTab(pedidos: pedidos, onRefresh: _loadAll),
                ]),
              ),
            ]),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }
}

// ── Tab Usuarios ──────────────────────────────────────────
class _UsuariosTab extends ConsumerWidget {
  final List<UserModel> usuarios;
  final VoidCallback onRefresh;
  const _UsuariosTab({required this.usuarios, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: usuarios.isEmpty
          ? const Center(
              child: Text('Sin usuarios',
                  style: TextStyle(color: AppColors.muted)))
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: usuarios.length,
              itemBuilder: (_, i) {
                final u = usuarios[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    CircleAvatar(
                        backgroundColor: AppColors.amber,
                        radius: 18,
                        child: Text(u.username[0].toUpperCase(),
                            style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w700))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(u.username,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text(u.role,
                              style: const TextStyle(
                                  color: AppColors.muted, fontSize: 12)),
                        ])),
                    IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            color: AppColors.amber, size: 20),
                        onPressed: () => _showUserDialog(context, ref,
                            user: u, onSaved: onRefresh)),
                    IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.danger, size: 20),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                      backgroundColor: AppColors.surface,
                                      title: Text('Eliminar ${u.username}'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Cancelar')),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Eliminar',
                                                style: TextStyle(
                                                    color: AppColors.danger))),
                                      ]));
                          if (ok == true) {
                            await ApiService.deleteUsuario(u.id);
                            onRefresh();
                          }
                        }),
                  ]),
                );
              }),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.amber,
        foregroundColor: Colors.black,
        onPressed: () => _showUserDialog(context, ref, onSaved: onRefresh),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showUserDialog(BuildContext context, WidgetRef ref,
      {UserModel? user, required VoidCallback onSaved}) {
    final nameCtrl = TextEditingController(text: user?.username ?? '');
    final passCtrl = TextEditingController();
    String role = user?.role ?? 'mesero';
    bool showPass = false;

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
              builder: (ctx, setLocal) => AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text(user == null ? 'Nuevo Usuario' : 'Editar Usuario'),
                content: SizedBox(
                    width: 300,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Nombre de usuario')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: passCtrl,
                          obscureText: !showPass,
                          decoration: InputDecoration(
                              labelText: user != null
                                  ? 'Nueva contrasena (opcional)'
                                  : 'Contrasena',
                              suffixIcon: IconButton(
                                  icon: Icon(
                                      showPass
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      size: 18),
                                  onPressed: () =>
                                      setLocal(() => showPass = !showPass)))),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          initialValue: role,
                          dropdownColor: AppColors.surfaceAlt,
                          decoration: const InputDecoration(labelText: 'Rol'),
                          items: ['admin', 'mesero', 'cocina']
                              .map((r) =>
                                  DropdownMenuItem(value: r, child: Text(r)))
                              .toList(),
                          onChanged: (v) => setLocal(() => role = v!)),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar')),
                  ElevatedButton(
                    onPressed: () async {
                      final body = <String, dynamic>{
                        'username': nameCtrl.text.trim(),
                        'role': role
                      };
                      if (passCtrl.text.isNotEmpty)
                        body['password'] = passCtrl.text;
                      try {
                        if (user == null) {
                          body['password'] = passCtrl.text;
                          await ApiService.createUsuario(body);
                        } else {
                          await ApiService.updateUsuario(user.id, body);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        onSaved();
                      } catch (e) {
                        if (ctx.mounted) AppSnackbar.error(ctx, e.toString());
                      }
                    },
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ));
  }
}

// ── Tab Productos ─────────────────────────────────────────
class _ProductosTab extends ConsumerWidget {
  final List<Producto> productos;
  final VoidCallback onRefresh;
  const _ProductosTab({required this.productos, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: productos.isEmpty
          ? const Center(
              child: Text('Sin productos',
                  style: TextStyle(color: AppColors.muted)))
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: productos.length,
              itemBuilder: (_, i) {
                final p = productos[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.activo
                                ? AppColors.success
                                : AppColors.danger)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(p.nombre,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text('\$${p.precio.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: AppColors.amber,
                                  fontWeight: FontWeight.w700)),
                        ])),
                    IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            color: AppColors.amber, size: 20),
                        onPressed: () => _showProductDialog(context,
                            producto: p, onSaved: onRefresh)),
                    IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.danger, size: 20),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                      backgroundColor: AppColors.surface,
                                      title: const Text('Eliminar producto'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Cancelar')),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Eliminar',
                                                style: TextStyle(
                                                    color: AppColors.danger))),
                                      ]));
                          if (ok == true) {
                            await ApiService.deleteProducto(p.id);
                            onRefresh();
                          }
                        }),
                  ]),
                );
              }),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.amber,
        foregroundColor: Colors.black,
        onPressed: () => _showProductDialog(context, onSaved: onRefresh),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showProductDialog(BuildContext context,
      {Producto? producto, required VoidCallback onSaved}) {
    final nameCtrl = TextEditingController(text: producto?.nombre ?? '');
    final priceCtrl =
        TextEditingController(text: producto?.precio.toString() ?? '');
    bool activo = producto?.activo ?? true;

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
              builder: (ctx, setLocal) => AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text(
                    producto == null ? 'Nuevo Producto' : 'Editar Producto'),
                content: SizedBox(
                    width: 300,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: nameCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Nombre')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Precio', prefixText: '\$')),
                      const SizedBox(height: 12),
                      Row(children: [
                        Switch(
                            value: activo,
                            activeThumbColor: AppColors.amber,
                            onChanged: (v) => setLocal(() => activo = v)),
                        Text(activo ? 'Activo' : 'Inactivo',
                            style: TextStyle(
                                color: activo
                                    ? AppColors.success
                                    : AppColors.muted)),
                      ]),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar')),
                  ElevatedButton(
                    onPressed: () async {
                      final body = {
                        'nombre': nameCtrl.text.trim(),
                        'precio': double.tryParse(priceCtrl.text) ?? 0,
                        'activo': activo
                      };
                      try {
                        if (producto == null) {
                          await ApiService.createProducto(
                              body as Map<String, dynamic>);
                        } else {
                          await ApiService.updateProducto(
                              producto.id, body as Map<String, dynamic>);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        onSaved();
                      } catch (e) {
                        if (ctx.mounted) AppSnackbar.error(ctx, e.toString());
                      }
                    },
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ));
  }
}

// ── Tab Pedidos ────────────────────────────────────────────
class _PedidosTab extends StatelessWidget {
  final List<Pedido> pedidos;
  final VoidCallback onRefresh;
  const _PedidosTab({required this.pedidos, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return pedidos.isEmpty
        ? const Center(
            child:
                Text('Sin pedidos', style: TextStyle(color: AppColors.muted)))
        : ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: pedidos.length,
            itemBuilder: (_, i) {
              final p = pedidos[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Text('#${p.id} · Mesa ${p.mesa}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          BadgeEstado(p.estado),
                        ]),
                        const SizedBox(height: 4),
                        Text('\$${p.total.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: AppColors.amber,
                                fontWeight: FontWeight.w700)),
                      ])),
                  IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.danger, size: 20),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                                    backgroundColor: AppColors.surface,
                                    title: Text('Eliminar pedido #${p.id}'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Cancelar')),
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Eliminar',
                                              style: TextStyle(
                                                  color: AppColors.danger))),
                                    ]));
                        if (ok == true) {
                          await ApiService.deletePedido(p.id);
                          onRefresh();
                        }
                      }),
                ]),
              );
            });
  }
}
