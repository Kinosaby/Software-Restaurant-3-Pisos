import 'package:intl/intl.dart';

final _moneda = NumberFormat.currency(locale: 'es_MX', symbol: r'$', decimalDigits: 2);
final _hora = DateFormat('HH:mm');

String dinero(double valor) => _moneda.format(valor);

String hora(DateTime fecha) => _hora.format(fecha);

final _fechaCorta = DateFormat('d MMM yyyy, HH:mm', 'es');

String fechaCorta(DateTime fecha) => _fechaCorta.format(fecha);

/// Mesa que la web asigna a los pedidos para llevar (el servidor exige un número).
const mesaParaLlevar = 99;

/// Cómo se muestra la mesa de un pedido: la interna para llevar nunca aparece como "Mesa 99".
/// Un pedido para llevar ligado a una mesa real conserva el número entre paréntesis.
String etiquetaMesa(int mesa, {bool llevar = false}) {
  if (mesa == mesaParaLlevar) return 'Para llevar';
  return llevar ? 'Para llevar (mesa $mesa)' : 'Mesa $mesa';
}

/// "hace 3 min", pensado para que cocina vea de un vistazo cuánto lleva esperando un pedido.
String tiempoTranscurrido(DateTime desde, {DateTime? ahora}) {
  final minutos = (ahora ?? DateTime.now()).difference(desde).inMinutes;
  if (minutos < 1) return 'ahora';
  if (minutos < 60) return 'hace $minutos min';
  final horas = minutos ~/ 60;
  final resto = minutos % 60;
  return resto == 0 ? 'hace $horas h' : 'hace $horas h $resto min';
}
