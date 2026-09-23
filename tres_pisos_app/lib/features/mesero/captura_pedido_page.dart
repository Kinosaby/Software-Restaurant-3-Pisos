import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';
import 'carrito.dart';

/// Captura de productos. Sin [pedidoId] crea pedidos nuevos (uno por comensal);
/// con él, agrega productos a ese pedido.
class CapturaPedidoPage extends ConsumerStatefulWidget {
  const CapturaPedidoPage({super.key, this.pedidoId});

  final int? pedidoId;

  @override
  ConsumerState<CapturaPedidoPage> createState() => _CapturaPedidoPageState();
}

class _CapturaPedidoPageState extends ConsumerState<CapturaPedidoPage> {
  final _mesa = TextEditingController();
  final _busqueda = TextEditingController();
  TipoPedido _tipo = TipoPedido.aqui;
  String? _categoria;
  bool _enviando = false;

  bool get _esNuevo => widget.pedidoId == null;

  @override
  void dispose() {
    _mesa.dispose();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final carrito = ref.read(carritoProvider.notifier);
    final estado = ref.read(carritoProvider);
    if (estado.vacio) return;

    final mesa = int.tryParse(_mesa.text.trim());
    if (_esNuevo && (mesa == null || mesa < 1)) {
      mostrarMensaje(context, 'Indica un número de mesa válido.', error: true);
      return;
    }

    setState(() => _enviando = true);
    final pedidos = ref.read(pedidosActivosProvider.notifier);
    try {
      if (_esNuevo) {
        final creados = <int>[];
        for (final comensal in estado.porEnviar) {
          final pedido = await pedidos.crear(
            mesa: mesa!,
            tipo: _tipo,
            comensal: estado.nombreParaEnvio(comensal),
            lineas: comensal.lineas,
          );
          creados.add(pedido.id);
          // Si falla el siguiente, un reintento no vuelve a mandar este.
          carrito.marcarEnviado(comensal);
        }
        if (!mounted) return;
        mostrarMensaje(
          context,
          creados.length == 1
              ? 'Pedido #${creados.single} enviado a cocina'
              : '${creados.length} pedidos enviados a cocina',
        );
      } else {
        await pedidos.agregar(widget.pedidoId!, estado.lineasActivas);
        if (!mounted) return;
        mostrarMensaje(context, 'Productos agregados');
      }
      context.pop();
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _verCarrito() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaCarrito(
        textoBoton: _esNuevo ? 'Enviar a cocina' : 'Agregar al pedido',
        onEnviar: () {
          Navigator.pop(context);
          _enviar();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productos = ref.watch(productosProvider);
    final todas = ref.watch(carritoProvider.select((e) => e.todasLasLineas));

    return Scaffold(
      appBar: AppBar(
        title: Text(_esNuevo ? 'Nuevo pedido' : 'Agregar al pedido #${widget.pedidoId}'),
      ),
      body: Column(
        children: [
          if (_esNuevo) _datosPedido(),
          if (_esNuevo) const _PestanasComensales(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _busqueda,
              decoration: InputDecoration(
                hintText: 'Buscar producto',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _busqueda.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_busqueda.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: productos.when(
              loading: () => const Cargando(),
              error: (e, _) => ErrorConReintento(
                error: e,
                alReintentar: () => ref.invalidate(productosProvider),
              ),
              data: _catalogo,
            ),
          ),
        ],
      ),
      bottomNavigationBar: todas.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _enviando ? null : _verCarrito,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  child: _enviando
                      ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Row(
                          children: [
                            Badge(
                              label: Text('${todas.piezas}'),
                              child: const Icon(Icons.receipt_long),
                            ),
                            const SizedBox(width: 16),
                            const Text('Ver pedido'),
                            const Spacer(),
                            Text(dinero(todas.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                ),
              ),
            ),
    );
  }

  Widget _datosPedido() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: TextField(
              controller: _mesa,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              decoration: const InputDecoration(labelText: 'Mesa', isDense: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SegmentedButton<TipoPedido>(
              segments: [
                for (final tipo in TipoPedido.values)
                  ButtonSegment(
                    value: tipo,
                    label: Text(tipo == TipoPedido.aqui ? 'Aquí' : 'Llevar'),
                    icon: Icon(tipo == TipoPedido.aqui ? Icons.table_restaurant : Icons.takeout_dining),
                  ),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() => _tipo = s.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _catalogo(List<Producto> productos) {
    final categorias = {for (final p in productos) p.categoria}.toList();
    final filtro = _busqueda.text.trim().toLowerCase();
    final visibles = productos.where((p) {
      if (_categoria != null && p.categoria != _categoria) return false;
      return filtro.isEmpty || p.nombre.toLowerCase().contains(filtro);
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final categoria in [null, ...categorias])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(categoria ?? 'Todo'),
                    selected: _categoria == categoria,
                    onSelected: (_) => setState(() => _categoria = categoria),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: visibles.isEmpty
              ? const Vacio(icono: Icons.search_off, mensaje: 'Sin productos')
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 104,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: visibles.length,
                  itemBuilder: (context, i) => _TarjetaProducto(producto: visibles[i]),
                ),
        ),
      ],
    );
  }
}

Future<String?> _pedirTexto(
  BuildContext context, {
  required String titulo,
  String? inicial,
  String? pista,
  int maximo = 200,
}) async {
  final controller = TextEditingController(text: inicial);
  final texto = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titulo),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maximo,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: pista),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Guardar')),
      ],
    ),
  );
  controller.dispose();
  return texto;
}

/// Pestañas C1, C2... Tocar la activa permite ponerle nombre (p. ej. el cliente para llevar).
class _PestanasComensales extends ConsumerWidget {
  const _PestanasComensales();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(carritoProvider);
    final carrito = ref.read(carritoProvider.notifier);

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          for (var i = 0; i < estado.comensales.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InputChip(
                avatar: const Icon(Icons.person_outline, size: 18),
                label: Text(
                  '${estado.comensales[i].nombre} (${estado.comensales[i].lineas.piezas})',
                ),
                selected: estado.activo == i,
                showCheckmark: false,
                tooltip: estado.activo == i ? 'Tocar para cambiar el nombre' : null,
                onPressed: () async {
                  if (estado.activo != i) {
                    carrito.seleccionarComensal(i);
                    return;
                  }
                  final nombre = await _pedirTexto(
                    context,
                    titulo: 'Nombre del comensal',
                    inicial: estado.comensales[i].nombreAutomatico ? '' : estado.comensales[i].nombre,
                    pista: 'Ej. Ana, niño, cliente para llevar',
                    maximo: 50,
                  );
                  if (nombre != null) carrito.renombrarComensal(i, nombre);
                },
                onDeleted: estado.comensales.length > 1 ? () => carrito.quitarComensal(i) : null,
                deleteButtonTooltipMessage: 'Quitar comensal',
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Comensal'),
            onPressed: carrito.agregarComensal,
          ),
        ],
      ),
    );
  }
}

class _TarjetaProducto extends ConsumerWidget {
  const _TarjetaProducto({required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cantidad = ref.watch(carritoProvider.select(
      (e) => e.lineasActivas.where((l) => l.producto.id == producto.id).fold(0, (s, l) => s + l.cantidad),
    ));
    final seleccionado = cantidad > 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: seleccionado
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Colores.acento, width: 2),
            )
          : null,
      child: InkWell(
        onTap: () => ref.read(carritoProvider.notifier).agregar(producto),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  producto.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Row(
                children: [
                  Text(dinero(producto.precio), style: const TextStyle(color: Colores.dorado)),
                  const Spacer(),
                  if (seleccionado)
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: Colores.acento,
                      child: Text(
                        '$cantidad',
                        style: const TextStyle(color: Colores.fondo, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resumen antes de enviar, agrupado por comensal cuando hay varios.
class _HojaCarrito extends ConsumerWidget {
  const _HojaCarrito({required this.textoBoton, required this.onEnviar});

  final String textoBoton;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(carritoProvider);
    final carrito = ref.read(carritoProvider.notifier);
    final varios = estado.comensales.length > 1;

    if (estado.vacio) {
      return const SizedBox(height: 200, child: Vacio(icono: Icons.receipt_long, mensaje: 'Pedido vacío'));
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (var i = 0; i < estado.comensales.length; i++)
                    if (estado.comensales[i].lineas.isNotEmpty) ...[
                      if (varios)
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 4),
                          child: Row(
                            children: [
                              Text(
                                estado.comensales[i].nombre,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colores.acento),
                              ),
                              const Spacer(),
                              Text(dinero(estado.comensales[i].lineas.total)),
                            ],
                          ),
                        ),
                      for (final linea in estado.comensales[i].lineas)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(linea.producto.nombre),
                          subtitle: GestureDetector(
                            onTap: () async {
                              final nota = await _pedirTexto(
                                context,
                                titulo: 'Nota para ${linea.producto.nombre}',
                                inicial: linea.nota,
                                pista: 'Ej. sin cebolla, bien dorado',
                              );
                              if (nota != null) carrito.fijarNota(linea.producto.id, nota, en: i);
                            },
                            child: Text(
                              linea.nota ?? '+ Agregar nota',
                              style: TextStyle(
                                color: linea.nota == null ? Colores.apagado : Colores.dorado,
                                fontStyle: linea.nota == null ? null : FontStyle.italic,
                              ),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Quitar uno',
                                icon: Icon(linea.cantidad == 1 ? Icons.delete_outline : Icons.remove),
                                onPressed: () => carrito.cambiarCantidad(linea.producto.id, -1, en: i),
                              ),
                              Text('${linea.cantidad}', style: Theme.of(context).textTheme.titleMedium),
                              IconButton(
                                tooltip: 'Agregar uno',
                                icon: const Icon(Icons.add),
                                onPressed: () => carrito.cambiarCantidad(linea.producto.id, 1, en: i),
                              ),
                            ],
                          ),
                        ),
                    ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: onEnviar,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                child: Row(
                  children: [
                    const Icon(Icons.send),
                    const SizedBox(width: 12),
                    Text(
                      estado.porEnviar.length > 1 ? '$textoBoton (${estado.porEnviar.length} pedidos)' : textoBoton,
                    ),
                    const Spacer(),
                    Text(
                      dinero(estado.todasLasLineas.total),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
