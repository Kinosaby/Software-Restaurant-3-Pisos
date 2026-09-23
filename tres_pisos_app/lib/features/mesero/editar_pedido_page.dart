import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';

/// Cantidad y nota que el mesero deja en un renglón mientras edita.
typedef RenglonEditado = ({int cantidad, String? nota});

/// Renglones que cambiaron respecto al pedido original, listos para `PATCH /editar`.
List<CambioItem> calcularCambios(Pedido original, Map<int, RenglonEditado> editado) => [
      for (final item in original.items)
        if (editado[item.detalleId] case final e?
            when e.cantidad != item.cantidad || e.nota != item.nota)
          CambioItem(detalleId: item.detalleId, cantidad: e.cantidad, nota: e.nota),
    ];

/// Cambia cantidades, notas, mesa, tipo o comensal de un pedido que cocina aún no termina.
class EditarPedidoPage extends ConsumerStatefulWidget {
  const EditarPedidoPage({super.key, required this.pedidoId});

  final int pedidoId;

  @override
  ConsumerState<EditarPedidoPage> createState() => _EditarPedidoPageState();
}

class _EditarPedidoPageState extends ConsumerState<EditarPedidoPage> {
  Pedido? _original;
  final _renglones = <int, RenglonEditado>{};
  final _mesa = TextEditingController();
  final _comensal = TextEditingController();
  TipoPedido _tipo = TipoPedido.aqui;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final pedido = ref
        .read(pedidosActivosProvider)
        .value
        ?.where((p) => p.id == widget.pedidoId)
        .firstOrNull;
    if (pedido != null) {
      _original = pedido;
      _mesa.text = '${pedido.mesa}';
      _comensal.text = pedido.comensal ?? '';
      _tipo = pedido.tipo;
      for (final item in pedido.items) {
        _renglones[item.detalleId] = (cantidad: item.cantidad, nota: item.nota);
      }
    }
  }

  @override
  void dispose() {
    _mesa.dispose();
    _comensal.dispose();
    super.dispose();
  }

  double get _total => _original!.items.fold(
        0,
        (s, item) => s + item.precio * (_renglones[item.detalleId]?.cantidad ?? item.cantidad),
      );

  bool get _quedaAlgo => _renglones.values.any((r) => r.cantidad > 0);

  void _cambiarCantidad(int detalleId, int delta) {
    final actual = _renglones[detalleId]!;
    final nueva = (actual.cantidad + delta).clamp(0, 999);
    setState(() => _renglones[detalleId] = (cantidad: nueva, nota: actual.nota));
  }

  Future<void> _editarNota(PedidoItem item) async {
    final controller = TextEditingController(text: _renglones[item.detalleId]!.nota);
    final nota = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nota para ${item.nombre}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Guardar')),
        ],
      ),
    );
    controller.dispose();
    if (nota == null) return;
    final limpia = nota.trim();
    setState(() => _renglones[item.detalleId] = (
          cantidad: _renglones[item.detalleId]!.cantidad,
          nota: limpia.isEmpty ? null : limpia,
        ));
  }

  Future<void> _guardar() async {
    final original = _original!;
    final mesa = int.tryParse(_mesa.text.trim());
    if (mesa == null || mesa < 1) {
      mostrarMensaje(context, 'Indica un número de mesa válido.', error: true);
      return;
    }
    final comensal = _comensal.text.trim().isEmpty ? null : _comensal.text.trim();
    final items = calcularCambios(original, _renglones);
    final cambiaMesa = mesa != original.mesa;
    final cambiaTipo = _tipo != original.tipo;
    final cambiaComensal = comensal != original.comensal;

    if (items.isEmpty && !cambiaMesa && !cambiaTipo && !cambiaComensal) {
      context.pop();
      return;
    }

    setState(() => _guardando = true);
    try {
      await ref.read(pedidosActivosProvider.notifier).editar(
            original.id,
            items: items,
            mesa: cambiaMesa ? mesa : null,
            tipo: cambiaTipo ? _tipo : null,
            comensal: cambiaComensal ? Opcional(comensal) : null,
          );
      if (!mounted) return;
      mostrarMensaje(context, 'Pedido #${original.id} actualizado');
      context.pop();
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final original = _original;
    if (original == null || !original.estado.modificable) {
      return Scaffold(
        appBar: AppBar(title: Text('Editar pedido #${widget.pedidoId}')),
        body: const Vacio(
          icono: Icons.lock_outline,
          mensaje: 'Solo se editan pedidos pendientes o en preparación',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Editar pedido #${original.id}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<TipoPedido>(
            segments: [
              for (final tipo in TipoPedido.values) ButtonSegment(value: tipo, label: Text(tipo.etiqueta)),
            ],
            selected: {_tipo},
            onSelectionChanged: (s) => setState(() => _tipo = s.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _mesa,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  decoration: const InputDecoration(labelText: 'Mesa', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _comensal,
                  maxLength: 50,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Comensal', isDense: true, counterText: ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                for (final item in original.items) _renglon(item),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Nuevo total', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text(
                dinero(_total),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colores.dorado,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          if (!_quedaAlgo)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'El pedido no puede quedar vacío. Para quitarlo todo, cancélalo.',
                style: TextStyle(color: Colores.peligro),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _guardando || !_quedaAlgo ? null : _guardar,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: _guardando
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.save_outlined),
            label: const Text('Guardar cambios'),
          ),
        ),
      ),
    );
  }

  Widget _renglon(PedidoItem item) {
    final editado = _renglones[item.detalleId]!;
    final quitado = editado.cantidad == 0;
    return ListTile(
      title: Text(
        item.nombre,
        style: quitado
            ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colores.apagado)
            : null,
      ),
      subtitle: GestureDetector(
        onTap: quitado ? null : () => _editarNota(item),
        child: Text(
          editado.nota ?? (quitado ? 'Se quitará del pedido' : '+ Agregar nota'),
          style: TextStyle(
            color: editado.nota == null ? Colores.apagado : Colores.dorado,
            fontStyle: editado.nota == null ? null : FontStyle.italic,
          ),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Quitar uno',
            icon: Icon(editado.cantidad <= 1 ? Icons.delete_outline : Icons.remove),
            onPressed: quitado ? null : () => _cambiarCantidad(item.detalleId, -1),
          ),
          Text('${editado.cantidad}', style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            tooltip: 'Agregar uno',
            icon: const Icon(Icons.add),
            onPressed: () => _cambiarCantidad(item.detalleId, 1),
          ),
        ],
      ),
    );
  }
}
