import 'package:intl/intl.dart';

final _moneda = NumberFormat.currency(locale: 'es_MX', symbol: r'$', decimalDigits: 2);
final _hora = DateFormat('HH:mm');

String dinero(double valor) => _moneda.format(valor);

String hora(DateTime fecha) => _hora.format(fecha);

/// "hace 3 min", pensado para que cocina vea de un vistazo cuánto lleva esperando un pedido.
String tiempoTranscurrido(DateTime desde, {DateTime? ahora}) {
  final minutos = (ahora ?? DateTime.now()).difference(desde).inMinutes;
  if (minutos < 1) return 'ahora';
  if (minutos < 60) return 'hace $minutos min';
  final horas = minutos ~/ 60;
  final resto = minutos % 60;
  return resto == 0 ? 'hace $horas h' : 'hace $horas h $resto min';
}
