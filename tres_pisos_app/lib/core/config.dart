/// Quita espacios y la barra final para poder concatenar rutas como `/api/...`,
/// y añade `http://` si solo se escribió la IP y el puerto de la central.
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
