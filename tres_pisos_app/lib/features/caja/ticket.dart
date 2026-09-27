import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formato.dart';
import '../../core/plataforma.dart';
import '../../core/widgets.dart';
import '../conexion/central_local.dart';
import '../pedidos/modelos.dart';

/// Pago que muestra el ticket: el recién capturado o, si todas las cuentas lo
/// guardan, la suma de sus desgloses. Los cobros antiguos no tienen desglose.
Pago? pagoDelTicket(List<Pedido> pedidos, Pago? capturado) {
  if (capturado != null) return capturado;
  if (pedidos.isEmpty || pedidos.any((p) => p.pago == null)) return null;
  return Pago.sumar([for (final p in pedidos) p.pago!]);
}

/// Renglones de la forma de pago en el ticket: efectivo (con lo recibido y el cambio) y tarjeta.
List<(String, double)> lineasPago(Pago pago) => [
      if (pago.efectivo >= 0.005) ('Efectivo', pago.efectivo),
      if (pago.tarjeta >= 0.005) ('Tarjeta', pago.tarjeta),
      if (pago.efectivo >= 0.005 && pago.recibido != null) ...[
        ('Recibido en efectivo', pago.recibido!),
        ('Cambio', pago.cambio!),
      ],
    ];

/// Cuenta o ticket con estilo de recibo, sobre fondo blanco para verse bien al imprimir o en WhatsApp.
class TicketVista extends StatelessWidget {
  const TicketVista({super.key, required this.pedidos, required this.restaurante, this.pago, this.pagado = false});

  final List<Pedido> pedidos;
  final String restaurante;

  /// Forma de pago recién capturada; sin ella se usa la que guardan los pedidos.
  final Pago? pago;

  /// Recién cobrado (los pedidos que recibe pueden seguir marcados como listos).
  final bool pagado;

  static final _fecha = DateFormat("d 'de' MMMM yyyy, HH:mm", 'es');

  @override
  Widget build(BuildContext context) {
    const tinta = Color(0xFF1B1B1B);
    const gris = Color(0xFF6B6B6B);
    const base = TextStyle(color: tinta, fontSize: 14, height: 1.35);
    final total = pedidos.fold<double>(0, (s, p) => s + p.total);
    final primero = pedidos.first;
    final cobrado = pagado || pedidos.every((p) => p.cobrado);
    final formaPago = pagoDelTicket(pedidos, pago);

    Widget linea(String izquierda, String derecha, {TextStyle? estilo}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(izquierda, style: estilo ?? base)),
              const SizedBox(width: 12),
              Text(derecha, style: estilo ?? base),
            ],
          ),
        );

    return Container(
      width: 360,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: DefaultTextStyle(
        style: base,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset('assets/logo.jpg', height: 72),
              ),
            ),
            const SizedBox(height: 8),
            Text(restaurante,
                textAlign: TextAlign.center, style: base.copyWith(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(_fecha.format(DateTime.now()), textAlign: TextAlign.center, style: base.copyWith(color: gris)),
            const SizedBox(height: 6),
            Text(
              primero.tipo == TipoPedido.llevar ? 'Para llevar' : 'Mesa ${primero.mesa}',
              textAlign: TextAlign.center,
              style: base.copyWith(fontWeight: FontWeight.w600),
            ),
            const Divider(color: gris, height: 24),
            for (final p in pedidos) ...[
              if (pedidos.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Text('${p.comensal ?? 'Cuenta'} · #${p.id}', style: base.copyWith(fontWeight: FontWeight.w600)),
                ),
              for (final i in p.items) ...[
                linea(
                  '${i.cantidad} × ${i.nombre}${i.llevar ? ' (llevar)' : ''}'
                  '${i.compartido == null ? '' : ' (${i.compartido!.parte}/${i.compartido!.partes})'}',
                  dinero(i.subtotal),
                ),
                if (i.notaVisible != null)
                  Text('   ${i.notaVisible}', style: base.copyWith(color: gris, fontSize: 12)),
              ],
              if (pedidos.length > 1) linea('Subtotal', dinero(p.total), estilo: base.copyWith(color: gris)),
            ],
            const Divider(color: gris, height: 24),
            linea('TOTAL', dinero(total), estilo: base.copyWith(fontSize: 18, fontWeight: FontWeight.bold)),
            if (formaPago != null)
              for (final (etiqueta, importe) in lineasPago(formaPago)) linea(etiqueta, dinero(importe)),
            const SizedBox(height: 16),
            Text(
              cobrado ? '¡Gracias por su visita!' : 'Cuenta por pagar',
              textAlign: TextAlign.center,
              style: base.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vista previa del ticket con el botón para compartirlo como imagen (WhatsApp, impresora, correo...).
Future<void> mostrarTicket(BuildContext context, List<Pedido> pedidos, {Pago? pago, bool pagado = false}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _DialogoTicket(pedidos: pedidos, pago: pago, pagado: pagado),
  );
}

class _DialogoTicket extends ConsumerStatefulWidget {
  const _DialogoTicket({required this.pedidos, this.pago, this.pagado = false});

  final List<Pedido> pedidos;
  final Pago? pago;
  final bool pagado;

  @override
  ConsumerState<_DialogoTicket> createState() => _DialogoTicketState();
}

class _DialogoTicketState extends ConsumerState<_DialogoTicket> {
  final _captura = GlobalKey();
  bool _compartiendo = false;

  Future<void> _compartir() async {
    setState(() => _compartiendo = true);
    try {
      final limite = _captura.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await limite.toImage(pixelRatio: 3);
      final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
      imagen.dispose();
      final primero = widget.pedidos.first;
      final total = widget.pedidos.fold<double>(0, (s, p) => s + p.total);
      await Plataforma.compartirImagen(
        bytes!.buffer.asUint8List(),
        nombre: 'ticket-${primero.tipo == TipoPedido.llevar ? 'llevar-${primero.id}' : 'mesa-${primero.mesa}'}.png',
        texto: '${primero.tipo == TipoPedido.llevar ? 'Pedido para llevar' : 'Mesa ${primero.mesa}'}: ${dinero(total)}',
      );
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, 'No se pudo compartir: $e', error: true);
    } finally {
      if (mounted) setState(() => _compartiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurante = ref.watch(centralLocalProvider)?.central.nombre ?? 'Restaurante 3 Pisos';
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: _captura,
                child: TicketVista(
                  pedidos: widget.pedidos,
                  restaurante: restaurante,
                  pago: widget.pago,
                  pagado: widget.pagado,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _compartiendo ? null : _compartir,
                  icon: const Icon(Icons.share),
                  label: const Text('Compartir'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
