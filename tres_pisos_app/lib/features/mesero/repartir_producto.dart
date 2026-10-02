import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../central/central.dart' show repartirCentavos;
import '../../central/seguridad.dart' show idAleatorio;
import '../../core/formato.dart';
import '../../core/tema.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';
import '../pedidos/widgets_pedido.dart';

/// Nombre corto de una cuenta para elegirla como destino.
String nombreCuenta(Pedido p) => p.comensal ?? 'Cuenta #${p.id}';

/// Hoja para pasar un producto (o parte de sus piezas) a otra cuenta de la mesa.
Future<Reparto?> mostrarMoverProducto(BuildContext context, Pedido pedido, PedidoItem item) =>
    showModalBottomSheet<Reparto>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaReparto(pedido: pedido, item: item, dividir: false),
    );

/// Hoja para dividir una pieza en partes iguales entre esta cuenta y otras de la mesa.
Future<Reparto?> mostrarDividirProducto(BuildContext context, Pedido pedido, PedidoItem item) =>
    showModalBottomSheet<Reparto>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaReparto(pedido: pedido, item: item, dividir: true),
    );

class _HojaReparto extends ConsumerStatefulWidget {
  const _HojaReparto({required this.pedido, required this.item, required this.dividir});

  final Pedido pedido;
  final PedidoItem item;
  final bool dividir;

  @override
  ConsumerState<_HojaReparto> createState() => _HojaRepartoState();
}

class _HojaRepartoState extends ConsumerState<_HojaReparto> {
  late int _cantidad = widget.item.cantidad;
  final _elegidas = <int>{};
  bool _enviando = false;
  String? _error;

  /// Base del id de operación de esta hoja: reintentar lo mismo tras un error
  /// de red no mueve ni divide dos veces; si se cambia la elección, es otra operación.
  final _base = idAleatorio(8);

  Future<void> _confirmar(List<Pedido> cuentas) async {
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final destinos = [for (final c in cuentas) if (_elegidas.contains(c.id)) c];
      final operacion = '$_base-${widget.item.detalleId}-$_cantidad-${[for (final d in destinos) d.id].join('.')}';
      final notifier = ref.read(pedidosActivosProvider.notifier);
      final reparto = widget.dividir
          ? await notifier.dividirProducto(widget.pedido, widget.item, destinos, operacion: operacion)
          : await notifier.moverProducto(widget.pedido, widget.item,
              cantidad: _cantidad, destino: destinos.single, operacion: operacion);
      if (mounted) Navigator.pop(context, reparto);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _alternar(int id) => setState(() {
        if (widget.dividir) {
          _elegidas.contains(id) ? _elegidas.remove(id) : _elegidas.add(id);
        } else {
          _elegidas
            ..clear()
            ..add(id);
        }
      });

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final item = widget.item;
    final cuentas = cuentasHermanas(ref.watch(pedidosActivosProvider).value ?? const [], widget.pedido);
    _elegidas.removeWhere((id) => !cuentas.any((c) => c.id == id));
    final partes = _elegidas.length + 1;
    final montos = repartirCentavos(item.precio, partes);
    final listo = _elegidas.isNotEmpty && !_enviando;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.dividir ? 'Dividir entre cuentas' : 'Mover a otra cuenta', style: texto.titleLarge),
              const SizedBox(height: 4),
              RenglonItem(item, mostrarPrecio: true),
              Text('De: ${nombreCuenta(widget.pedido)} · #${widget.pedido.id}',
                  style: const TextStyle(color: Colores.apagado)),
              if (!widget.dividir && item.cantidad > 1) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: Text('Piezas a mover')),
                    IconButton(
                      onPressed: _cantidad > 1 ? () => setState(() => _cantidad--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$_cantidad de ${item.cantidad}', style: texto.titleMedium),
                    IconButton(
                      onPressed: _cantidad < item.cantidad ? () => setState(() => _cantidad++) : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
              if (widget.dividir && item.cantidad > 1)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Se divide una pieza; las demás se quedan en esta cuenta.',
                      style: TextStyle(color: Colores.apagado)),
                ),
              const Divider(height: 24),
              Text(widget.dividir ? 'Compartir con' : 'Pasar a', style: texto.titleSmall),
              if (cuentas.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No hay otras cuentas abiertas en esta mesa. Agrega un comensal para poder repartir.',
                    style: TextStyle(color: Colores.apagado),
                  ),
                ),
              for (final c in cuentas)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: _enviando ? null : () => _alternar(c.id),
                  leading: Icon(
                    widget.dividir
                        ? (_elegidas.contains(c.id) ? Icons.check_box : Icons.check_box_outline_blank)
                        : (_elegidas.contains(c.id) ? Icons.radio_button_checked : Icons.radio_button_off),
                    color: Colores.acento,
                  ),
                  title: Text(nombreCuenta(c)),
                  subtitle: Text('#${c.id} · ${c.estado.etiqueta} · ${dinero(c.total)}'),
                ),
              if (widget.dividir && _elegidas.isNotEmpty) ...[
                const Divider(height: 24),
                Text(
                  montos.toSet().length == 1
                      ? '$partes partes de ${dinero(montos.first)}'
                      : '$partes partes: ${montos.map(dinero).join(' + ')}',
                  style: texto.titleMedium?.copyWith(color: Colores.dorado),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colores.peligro)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: listo ? () => _confirmar(cuentas) : null,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: Icon(widget.dividir ? Icons.call_split : Icons.move_down),
                label: Text(widget.dividir ? 'Dividir entre $partes' : 'Mover'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
