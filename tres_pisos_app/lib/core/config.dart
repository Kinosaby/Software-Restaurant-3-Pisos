/// Servidor sugerido en la pantalla de login la primera vez que se abre la app.
///
/// Se puede fijar al compilar:
///   flutter run --dart-define=API_URL=http://192.168.1.50:3000
/// 10.0.2.2 es la IP con la que el emulador de Android ve el `localhost` del PC.
const servidorPorDefecto = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:3000',
);

/// Quita espacios y la barra final para poder concatenar rutas como `/api/...`.
String normalizarServidor(String url) {
  var limpio = url.trim();
  while (limpio.endsWith('/')) {
    limpio = limpio.substring(0, limpio.length - 1);
  }
  if (limpio.isNotEmpty && !limpio.contains('://')) {
    limpio = 'http://$limpio';
  }
  return limpio;
}
