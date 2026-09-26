import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';
import 'ticket.dart';

/// Montos de billete con los que suele pagar el cliente, mayores que el total.
List<double> montosSugeridos(double total) {
  final sugeridos = <double>{};
  for (final billete in [20.0, 50.0, 100.0, 200.0, 500.0, 1000.0]) {
    final redondeado = (total / billete).ceil() * billete;
    if (redondeado > total) sugeridos.add(redondeado);
  }
  final lista = sugeridos.toList()..sort();
  return lista.take(4).toList();
}

/// Cobra una o varias cuentas (p. ej. la mesa completa). Al terminar ofrece compartir el ticket.
Future<void> mostrarCobro(BuildContext context, WidgetRef ref, List<Pedido> pedidos) async {
  if (pedidos.isEmpty) return;
  final resultado = await showModalBottomSheet<({double? pago, double? cambio})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HojaCobro(pedidos: pedidos),
  );
  if (resultado == null || !context.mounted) return;
  // La pantalla que abrió el cobro puede cerrarse (la cuenta deja de estar activa);
  // el ticket se abre desde el navegador, que sigue vivo.
  final contextoRaiz = Navigator.of(context, rootNavigator: true).context;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(pedidos.length == 1 ? '${pedidos.single.titulo} cobrada' : '${pedidos.length} cuentas cobradas'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Ticket',
        onPressed: () =>
            mostrarTicket(contextoRaiz, pedidos, pago: resultado.pago, cambio: resultado.cambio, pagado: true),
      ),
    ));
}

class _HojaCobro extends ConsumerStatefulWidget {
  const _HojaCobro({required this.pedidos});

  final List<Pedido> pedidos;

  @override
  ConsumerState<_HojaCobro> createState() => _HojaCobroState();
}

class _HojaCobroState extends ConsumerState<_HojaCobro> {
  final _pago = TextEditingController();
  bool _cobrando = false;
  String? _error;

  double get _total => widget.pedidos.fold(0, (s, p) => s + p.total);
  double? get _recibido => double.tryParse(_pago.text.replaceAll(',', '.'));

  @override
  void dispose() {
    _pago.dispose();
    super.dispose();
  }

  Future<void> _cobrar({required bool efectivo}) async {
    setState(() {
      _cobrando = true;
      _error = null;
    });
    try {
      await ref
          .read(pedidosActivosProvider.notifier)
          .cambiarEstadoVarios([for (final p in widget.pedidos) p.id], EstadoPedido.pagado);
      if (!mounted) return;
      final pago = efectivo ? _recibido : null;
      Navigator.pop(context, (pago: pago, cambio: pago == null ? null : pago - _total));
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cobrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final recibido = _recibido;
    final cambio = recibido == null ? null : recibido - _total;
    final alcanza = cambio != null && cambio >= -0.005;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.pedidos.length == 1 ? 'Cobrar ${widget.pedidos.single.titulo}' : 'Cobrar ${widget.pedidos.length} cuentas',
                style: texto.titleLarge,
              ),
              const SizedBox(height: 8),
              if (widget.pedidos.length > 1)
                for (final p in widget.pedidos)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(p.comensal ?? '#${p.id}', style: const TextStyle(color: Colores.apagado))),
                        Text(dinero(p.total)),
                      ],
                    ),
                  ),
              const Divider(height: 20),
              Row(
                children: [
                  Text('Total', style: texto.titleMedium),
                  const Spacer(),
                  Text(dinero(_total), style: texto.headlineSmall?.copyWith(color: Colores.dorado, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pago,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                textAlign: TextAlign.end,
                style: texto.headlineSmall,
                decoration: const InputDecoration(labelText: 'Con cuánto paga (efectivo)', prefixText: r'$ '),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Exacto'),
                    onPressed: () => setState(() => _pago.text = _total.toStringAsFixed(2)),
                  ),
                  for (final monto in montosSugeridos(_total))
                    ActionChip(
                      label: Text(dinero(monto)),
                      onPressed: () => setState(() => _pago.text = monto.toStringAsFixed(2)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (cambio != null)
                Row(
                  children: [
                    Text(alcanza ? 'Cambio' : 'Falta', style: texto.titleMedium),
                    const Spacer(),
                    Text(
                      dinero(cambio.abs()),
                      style: texto.headlineMedium?.copyWith(
                        color: alcanza ? Colores.exito : Colores.peligro,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colores.peligro)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _cobrando || !alcanza ? null : () => _cobrar(efectivo: true),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Cobrar en efectivo'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _cobrando ? null : () => _cobrar(efectivo: false),
                icon: const Icon(Icons.credit_card),
                label: const Text('Tarjeta o transferencia'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Atajo para una sola cuenta, con aviso si algo falla.
Future<void> cobrarPedido(BuildContext context, WidgetRef ref, Pedido pedido) async {
  try {
    await mostrarCobro(context, ref, [pedido]);
  } on Object catch (e) {
    if (context.mounted) mostrarMensaje(context, '$e', error: true);
  }
}
