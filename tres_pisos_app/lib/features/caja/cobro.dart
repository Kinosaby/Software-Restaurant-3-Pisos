import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../central/seguridad.dart' show idAleatorio;
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

enum FormaPago {
  efectivo('Efectivo', Icons.payments_outlined),
  tarjeta('Tarjeta', Icons.credit_card),
  mixto('Mixto', Icons.call_split);

  const FormaPago(this.etiqueta, this.icono);
  final String etiqueta;
  final IconData icono;
}

/// Cuánto va en efectivo y cuánto con tarjeta según lo que se capturó en la hoja de cobro.
class CalculoCobro {
  const CalculoCobro({required this.total, required this.efectivo, required this.tarjeta, this.recibido});

  final double total;
  final double efectivo;
  final double tarjeta;

  /// Billetes que entrega el cliente para la parte en efectivo.
  final double? recibido;

  /// El cambio sale solo de la parte en efectivo.
  double? get cambio => recibido == null ? null : aCentavos(recibido! - efectivo);

  bool get hayEfectivo => efectivo >= 0.005;

  /// La parte con tarjeta no puede pasar del total.
  bool get tarjetaValida => tarjeta >= 0 && efectivo >= 0;

  /// Se puede cobrar: las partes cuadran y, si hay efectivo, lo recibido alcanza.
  bool get valido => tarjetaValida && (!hayEfectivo || (cambio != null && cambio! >= 0));

  Pago get pago => Pago(efectivo: efectivo, tarjeta: tarjeta, recibido: hayEfectivo ? recibido : null);
}

/// Reparte el [total]: con tarjeta todo va a tarjeta; en efectivo, todo en
/// efectivo; en mixto, lo que no se paga con [tarjeta] se paga en efectivo.
CalculoCobro calcularCobro({required double total, required FormaPago forma, double? tarjeta, double? recibido}) {
  final total0 = aCentavos(total);
  final conTarjeta = switch (forma) {
    FormaPago.efectivo => 0.0,
    FormaPago.tarjeta => total0,
    // Sin capturar la parte con tarjeta, el mixto no cuadra todavía.
    FormaPago.mixto => tarjeta == null ? -1.0 : aCentavos(tarjeta),
  };
  return CalculoCobro(
    total: total0,
    tarjeta: conTarjeta,
    efectivo: aCentavos(total0 - (conTarjeta < 0 ? 0 : conTarjeta)),
    recibido: forma == FormaPago.tarjeta ? null : recibido,
  );
}

/// Confirmación al cancelar una cuenta ya cobrada: se devuelve el dinero y se
/// resta de las ventas del día.
String mensajeReembolso(Pedido pedido) {
  final pago = pedido.pago;
  final desglose = pago == null
      ? ''
      : ' (${[
          if (pago.efectivo >= 0.005) 'efectivo ${dinero(pago.efectivo)}',
          if (pago.tarjeta >= 0.005) 'tarjeta ${dinero(pago.tarjeta)}',
        ].join(' + ')})';
  return 'Esta cuenta ya se cobró. Al cancelarla se devuelven ${dinero(pedido.total)}$desglose al cliente '
      'y se restan de las ventas del día. Cocina deja de verla. No se puede deshacer.';
}

/// Advertencia si alguna de las cuentas sigue en cocina (sin terminar o con un
/// extra pendiente); `null` si todas se pueden servir ya.
String? avisoEnCocina(List<Pedido> pedidos) {
  final enCocina = pedidos.where((p) => !p.paraServir).length;
  if (enCocina == 0) return null;
  final inicio = pedidos.length == 1
      ? 'Este pedido aún está en cocina.'
      : enCocina == 1
          ? 'Una de las cuentas aún está en cocina.'
          : '$enCocina de las cuentas aún están en cocina.';
  return '$inicio Puedes cobrar ahora: cocina lo seguirá viendo y, cuando lo marque listo, '
      'la cuenta se cerrará sola y se avisará al mesero para entregarlo.';
}

/// Cobra una o varias cuentas (p. ej. la mesa completa). Al terminar ofrece compartir el ticket.
Future<void> mostrarCobro(BuildContext context, WidgetRef ref, List<Pedido> pedidos) async {
  if (pedidos.isEmpty) return;
  final aviso = avisoEnCocina(pedidos);
  if (aviso != null) {
    final seguir = await confirmar(context, titulo: 'Aún en cocina', mensaje: aviso, accion: 'Cobrar de todos modos');
    if (!seguir || !context.mounted) return;
  }
  final resultado = await showModalBottomSheet<({Pago pago, List<Pedido> cobrados})>(
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
      persist: false, // con botón, Flutter lo deja fijo por defecto
      action: SnackBarAction(
        label: 'Ticket',
        onPressed: () => mostrarTicket(
          contextoRaiz,
          resultado.cobrados.isEmpty ? pedidos : resultado.cobrados,
          pago: resultado.pago,
          pagado: true,
        ),
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
  final _recibido = TextEditingController();
  final _tarjeta = TextEditingController();
  final _operacion = idAleatorio(8);
  final _focoRecibido = FocusNode();
  final _focoTarjeta = FocusNode();
  FormaPago _forma = FormaPago.efectivo;
  bool _cobrando = false;
  String? _error;

  double get _total => widget.pedidos.fold(0, (s, p) => s + p.total);

  static double? _leer(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.'));

  CalculoCobro get _calculo =>
      calcularCobro(total: _total, forma: _forma, tarjeta: _leer(_tarjeta), recibido: _leer(_recibido));

  @override
  void dispose() {
    _recibido.dispose();
    _tarjeta.dispose();
    _focoRecibido.dispose();
    _focoTarjeta.dispose();
    super.dispose();
  }

  /// Al cambiar la forma de pago el teclado pasa al campo que toca llenar; sin
  /// esto seguía conectado al campo anterior y lo que se escribía no aparecía.
  void _cambiarForma(FormaPago forma) {
    setState(() => _forma = forma);
    final foco = switch (forma) {
      FormaPago.efectivo => _focoRecibido,
      FormaPago.mixto => _focoTarjeta,
      FormaPago.tarjeta => null,
    };
    if (foco == null) {
      FocusScope.of(context).unfocus();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) foco.requestFocus();
      });
    }
  }

  Future<void> _cobrar(CalculoCobro calculo) async {
    setState(() {
      _cobrando = true;
      _error = null;
    });
    try {
      final pago = calculo.pago;
      final cobrados = await ref
          .read(pedidosActivosProvider.notifier)
          .cobrar([for (final p in widget.pedidos) p.id], pago,
              // Reintentar el mismo cobro tras un error de red no lo repite.
              operacion: '$_operacion-${pago.efectivo.toStringAsFixed(2)}-${pago.tarjeta.toStringAsFixed(2)}');
      if (!mounted) return;
      Navigator.pop(context, (pago: pago, cobrados: cobrados));
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cobrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final calculo = _calculo;
    final cambio = calculo.cambio;
    final pideEfectivo = _forma != FormaPago.tarjeta && calculo.tarjetaValida && calculo.hayEfectivo;

    Widget campoDinero(TextEditingController c, FocusNode foco, String etiqueta, {bool enfocar = false}) => TextField(
          key: ObjectKey(c), // cada campo con su propio estado aunque cambie de lugar
          controller: c,
          focusNode: foco,
          autofocus: enfocar,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          textAlign: TextAlign.end,
          style: texto.headlineSmall,
          decoration: InputDecoration(labelText: etiqueta, prefixText: r'$ '),
          onChanged: (_) => setState(() {}),
        );

    Widget renglon(String etiqueta, double valor, {Color? color, TextStyle? estilo}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Text(etiqueta, style: texto.titleMedium),
              const Spacer(),
              Text(dinero(valor), style: (estilo ?? texto.titleMedium)?.copyWith(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
        );

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
              SegmentedButton<FormaPago>(
                segments: [
                  for (final f in FormaPago.values) ButtonSegment(value: f, label: Text(f.etiqueta), icon: Icon(f.icono)),
                ],
                selected: {_forma},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _cambiarForma(s.first),
              ),
              const SizedBox(height: 16),
              if (_forma == FormaPago.mixto) ...[
                campoDinero(_tarjeta, _focoTarjeta, 'Con tarjeta o transferencia', enfocar: true),
                const SizedBox(height: 8),
                if (!calculo.tarjetaValida && _tarjeta.text.isNotEmpty)
                  Text(
                    _leer(_tarjeta) == null
                        ? 'Escribe un monto válido, p. ej. 150 o 150.50.'
                        : 'La parte con tarjeta no puede pasar del total.',
                    style: const TextStyle(color: Colores.peligro),
                  )
                else if (calculo.tarjeta >= 0)
                  renglon('En efectivo', calculo.efectivo),
                const SizedBox(height: 12),
              ],
              if (_forma == FormaPago.tarjeta)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Todo con tarjeta o transferencia.', style: TextStyle(color: Colores.apagado)),
                ),
              if (pideEfectivo) ...[
                campoDinero(
                  _recibido,
                  _focoRecibido,
                  _forma == FormaPago.mixto ? 'Con cuánto paga lo de efectivo' : 'Con cuánto paga (efectivo)',
                  enfocar: _forma == FormaPago.efectivo,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Exacto'),
                      onPressed: () => setState(() => _recibido.text = calculo.efectivo.toStringAsFixed(2)),
                    ),
                    for (final monto in montosSugeridos(calculo.efectivo))
                      ActionChip(
                        label: Text(dinero(monto)),
                        onPressed: () => setState(() => _recibido.text = monto.toStringAsFixed(2)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (cambio != null)
                  renglon(
                    cambio >= 0 ? 'Cambio' : 'Falta',
                    cambio.abs(),
                    color: cambio >= 0 ? Colores.exito : Colores.peligro,
                    estilo: texto.headlineMedium,
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colores.peligro)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _cobrando || !calculo.valido ? null : () => _cobrar(calculo),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: Icon(_forma.icono),
                label: Text(switch (_forma) {
                  FormaPago.efectivo => 'Cobrar en efectivo',
                  FormaPago.tarjeta => 'Cobrar con tarjeta',
                  FormaPago.mixto => 'Cobrar mixto',
                }),
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
