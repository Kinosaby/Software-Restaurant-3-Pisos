import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final _aleatorio = Random.secure();

List<int> bytesAleatorios(int n) => List<int>.generate(n, (_) => _aleatorio.nextInt(256));

/// Identificador aleatorio en hexadecimal (operaciones, secretos).
String idAleatorio([int bytes = 16]) =>
    bytesAleatorios(bytes).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Código de enlace legible, sin caracteres que se confundan (0/O, 1/I/L).
String nuevoCodigoEnlace() {
  const alfabeto = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  String bloque() => List.generate(4, (_) => alfabeto[_aleatorio.nextInt(alfabeto.length)]).join();
  return '${bloque()}-${bloque()}';
}

/// Normaliza lo que teclea el usuario ("k7p2 9qxm" → "K7P2-9QXM").
String normalizarCodigo(String codigo) {
  final limpio = codigo.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  return limpio.length == 8 ? '${limpio.substring(0, 4)}-${limpio.substring(4)}' : limpio;
}

// ── Contraseñas ─────────────────────────────────────────────

/// PBKDF2-HMAC-SHA256 (RFC 8018).
Uint8List pbkdf2(List<int> password, List<int> sal, int iteraciones, int longitud) {
  final hmac = Hmac(sha256, password);
  final salida = BytesBuilder();
  for (var bloque = 1; salida.length < longitud; bloque++) {
    final indice = ByteData(4)..setUint32(0, bloque);
    var u = hmac.convert([...sal, ...indice.buffer.asUint8List()]).bytes;
    final t = List<int>.of(u);
    for (var i = 1; i < iteraciones; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    salida.add(t);
  }
  return Uint8List.sublistView(salida.toBytes(), 0, longitud);
}

/// Formato guardado: `pbkdf2$<iteraciones>$<sal b64>$<hash b64>`.
String hashPassword(String password, {int iteraciones = 60000}) {
  final sal = bytesAleatorios(16);
  final hash = pbkdf2(utf8.encode(password), sal, iteraciones, 32);
  return 'pbkdf2\$$iteraciones\$${base64Encode(sal)}\$${base64Encode(hash)}';
}

bool verificarPassword(String password, String guardado) {
  final partes = guardado.split(r'$');
  if (partes.length != 4 || partes[0] != 'pbkdf2') return false;
  final iteraciones = int.tryParse(partes[1]);
  if (iteraciones == null) return false;
  final sal = base64Decode(partes[2]);
  final esperado = base64Decode(partes[3]);
  final calculado = pbkdf2(utf8.encode(password), sal, iteraciones, esperado.length);
  return _igualesEnTiempoConstante(calculado, esperado);
}

bool _igualesEnTiempoConstante(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diferencia = 0;
  for (var i = 0; i < a.length; i++) {
    diferencia |= a[i] ^ b[i];
  }
  return diferencia == 0;
}

// ── Tokens de sesión (JWT HS256) ────────────────────────────

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

String firmarToken(Map<String, dynamic> datos, String secreto, {Duration vigencia = const Duration(hours: 12)}) {
  final ahora = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final cabecera = _b64(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
  final cuerpo = _b64(utf8.encode(jsonEncode({...datos, 'iat': ahora, 'exp': ahora + vigencia.inSeconds})));
  final firma = _b64(Hmac(sha256, utf8.encode(secreto)).convert(utf8.encode('$cabecera.$cuerpo')).bytes);
  return '$cabecera.$cuerpo.$firma';
}

/// Devuelve el contenido del token si la firma es válida y no ha caducado.
Map<String, dynamic>? verificarToken(String token, String secreto, {DateTime? ahora}) {
  final partes = token.split('.');
  if (partes.length != 3) return null;
  final firma = _b64(Hmac(sha256, utf8.encode(secreto)).convert(utf8.encode('${partes[0]}.${partes[1]}')).bytes);
  if (!_igualesEnTiempoConstante(utf8.encode(firma), utf8.encode(partes[2]))) return null;
  try {
    final datos = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1])))) as Map<String, dynamic>;
    final exp = datos['exp'];
    final segundos = (ahora ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    if (exp is! int || exp <= segundos) return null;
    return datos;
  } on FormatException {
    return null;
  }
}
