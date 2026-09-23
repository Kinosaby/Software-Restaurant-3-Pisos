import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';
import 'admin_repository.dart';

/// Todos los productos, incluidos los inactivos.
final productosAdminProvider = FutureProvider.autoDispose<List<Producto>>(
  (ref) => ref.watch(adminRepositoryProvider).productos(),
);

class ProductosAdminPage extends ConsumerWidget {
  const ProductosAdminPage({super.key});

  void _refrescar(WidgetRef ref) {
    ref
      ..invalidate(productosAdminProvider)
      // El catálogo del mesero también debe reflejar el cambio.
      ..invalidate(productosProvider);
  }

  Future<void> _cambiarActivo(BuildContext context, WidgetRef ref, Producto p, bool activo) async {
    try {
      await ref.read(adminRepositoryProvider).guardarProducto(
            id: p.id,
            nombre: p.nombre,
            precio: p.precio,
            categoria: p.categoria,
            activo: activo,
          );
      _refrescar(ref);
    } on Object catch (e) {
      if (context.mounted) mostrarMensaje(context, '$e', error: true);
    }
  }

  Future<void> _abrirFormulario(BuildContext context, WidgetRef ref, List<Producto> todos, [Producto? producto]) async {
    final categorias = {for (final p in todos) p.categoria}.toList()..sort();
    final cambio = await showDialog<bool>(
      context: context,
      builder: (_) => _FormularioProducto(producto: producto, categorias: categorias),
    );
    if (cambio ?? false) _refrescar(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productos = ref.watch(productosAdminProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Productos')),
      floatingActionButton: productos.hasValue
          ? FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(context, ref, productos.value!),
              icon: const Icon(Icons.add),
              label: const Text('Producto'),
            )
          : null,
      body: productos.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorConReintento(error: e, alReintentar: () => ref.invalidate(productosAdminProvider)),
        data: (todos) {
          if (todos.isEmpty) {
            return const Vacio(icono: Icons.restaurant_menu, mensaje: 'Aún no hay productos');
          }
          final porCategoria = <String, List<Producto>>{};
          for (final p in todos) {
            porCategoria.putIfAbsent(p.categoria, () => []).add(p);
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(productosAdminProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final MapEntry(key: categoria, value: lista) in porCategoria.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                    child: Text(
                      categoria,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colores.acento),
                    ),
                  ),
                  Card(
                    child: Column(
                      children: [
                        for (final p in lista)
                          ListTile(
                            title: Text(
                              p.nombre,
                              style: p.activo ? null : const TextStyle(color: Colores.apagado),
                            ),
                            subtitle: Text(
                              p.activo ? dinero(p.precio) : '${dinero(p.precio)} · inactivo',
                              style: TextStyle(color: p.activo ? Colores.dorado : Colores.apagado),
                            ),
                            trailing: Switch(
                              value: p.activo,
                              onChanged: (v) => _cambiarActivo(context, ref, p, v),
                            ),
                            onTap: () => _abrirFormulario(context, ref, todos, p),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FormularioProducto extends ConsumerStatefulWidget {
  const _FormularioProducto({this.producto, required this.categorias});

  final Producto? producto;
  final List<String> categorias;

  @override
  ConsumerState<_FormularioProducto> createState() => _FormularioProductoState();
}

class _FormularioProductoState extends ConsumerState<_FormularioProducto> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.producto?.nombre);
  late final _precio = TextEditingController(text: widget.producto?.precio.toStringAsFixed(2));
  late final _categoria = TextEditingController(text: widget.producto?.categoria);
  late bool _activo = widget.producto?.activo ?? true;
  bool _ocupado = false;

  @override
  void dispose() {
    _nombre.dispose();
    _precio.dispose();
    _categoria.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(adminRepositoryProvider).guardarProducto(
            id: widget.producto?.id,
            nombre: _nombre.text.trim(),
            precio: double.parse(_precio.text.replaceAll(',', '.')),
            categoria: _categoria.text.trim().isEmpty ? 'General' : _categoria.text.trim(),
            activo: _activo,
          );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _eliminar() async {
    final producto = widget.producto!;
    final ok = await confirmar(
      context,
      titulo: 'Eliminar ${producto.nombre}',
      mensaje: 'Si el producto ya aparece en pedidos no se podrá eliminar; en ese caso desactívalo.',
      accion: 'Eliminar',
      destructiva: true,
    );
    if (!ok || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(adminRepositoryProvider).eliminarProducto(producto.id);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      // El backend responde 500 cuando la clave foránea de pedido_detalle lo impide.
      mostrarMensaje(
        context,
        (e.status ?? 0) >= 500 ? 'No se puede eliminar porque ya está en pedidos. Desactívalo.' : e.mensaje,
        error: true,
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.producto != null;
    return AlertDialog(
      title: Text(editando ? 'Editar producto' : 'Nuevo producto'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nombre,
                autofocus: !editando,
                maxLength: 100,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el nombre' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _precio,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(labelText: 'Precio', prefixText: r'$ '),
                validator: (v) {
                  final precio = double.tryParse((v ?? '').replaceAll(',', '.'));
                  return (precio == null || precio <= 0) ? 'Precio mayor que cero' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _categoria,
                maxLength: 50,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Categoría', hintText: 'General'),
              ),
              if (widget.categorias.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in widget.categorias)
                      ActionChip(label: Text(c), onPressed: () => setState(() => _categoria.text = c)),
                  ],
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Disponible en el menú'),
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (editando)
          TextButton(
            onPressed: _ocupado ? null : _eliminar,
            style: TextButton.styleFrom(foregroundColor: Colores.peligro),
            child: const Text('Eliminar'),
          ),
        TextButton(onPressed: _ocupado ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _ocupado ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
