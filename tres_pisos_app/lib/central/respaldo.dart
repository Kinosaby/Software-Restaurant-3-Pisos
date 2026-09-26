import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'seguridad.dart';

/// Formato del archivo `.3pisos`: un JSON con los parámetros y los datos cifrados.
const formatoRespaldo = '3pisos-respaldo-v1';

class RespaldoInvalido implements Exception {
  RespaldoInvalido(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Resumen visible sin la contraseña (para confirmar antes de restaurar).
class InfoRespaldo {
  const InfoRespaldo({required this.restaurante, required this.creado});

  final String restaurante;
  final DateTime creado;
}

/// Cifra el estado completo de la central.
///
/// La clave se deriva de la contraseña con PBKDF2-HMAC-SHA256 y sal aleatoria;
/// los datos (JSON comprimido con gzip) se cifran con AES-256-GCM, que además
/// detecta cualquier alteración del archivo o una contraseña incorrecta.
Uint8List cifrarRespaldo(
  List<Map<String, dynamic>> registros,
  String password, {
  required String restaurante,
  DateTime? creado,
  int iteraciones = 200000,
}) {
  final sal = Uint8List.fromList(bytesAleatorios(16));
  final nonce = Uint8List.fromList(bytesAleatorios(12));
  final clave = pbkdf2(utf8.encode(password), sal, iteraciones, 32);
  final cabecera = {
    'formato': formatoRespaldo,
    'restaurante': restaurante,
    'creado': (creado ?? DateTime.now()).toUtc().toIso8601String(),
  };
  final plano = Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(registros))));
  final cifrado = _gcm(forEncryption: true, clave: clave, nonce: nonce, cabecera: cabecera).process(plano);

  return Uint8List.fromList(utf8.encode(jsonEncode({
    ...cabecera,
    'kdf': {'alg': 'pbkdf2-sha256', 'iteraciones': iteraciones, 'sal': base64Encode(sal)},
    'cifrado': {'alg': 'aes-256-gcm', 'nonce': base64Encode(nonce)},
    'datos': base64Encode(cifrado),
  })));
}

InfoRespaldo leerInfoRespaldo(Uint8List archivo) {
  final sobre = _sobre(archivo);
  return InfoRespaldo(
    restaurante: sobre['restaurante']?.toString() ?? '',
    creado: DateTime.tryParse(sobre['creado']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
  );
}

/// Devuelve los registros de la central o lanza [RespaldoInvalido].
List<Map<String, dynamic>> descifrarRespaldo(Uint8List archivo, String password) {
  final sobre = _sobre(archivo);
  try {
    final kdf = sobre['kdf'] as Map<String, dynamic>;
    final cifrado = sobre['cifrado'] as Map<String, dynamic>;
    final clave = pbkdf2(utf8.encode(password), base64Decode(kdf['sal'] as String), kdf['iteraciones'] as int, 32);
    final cabecera = {
      'formato': sobre['formato'],
      'restaurante': sobre['restaurante'],
      'creado': sobre['creado'],
    };
    final Uint8List plano;
    try {
      plano = _gcm(
        forEncryption: false,
        clave: clave,
        nonce: base64Decode(cifrado['nonce'] as String),
        cabecera: cabecera,
      ).process(base64Decode(sobre['datos'] as String));
    } on InvalidCipherTextException {
      throw RespaldoInvalido('Contraseña incorrecta o archivo dañado.');
    }
    return (jsonDecode(utf8.decode(gzip.decode(plano))) as List).cast<Map<String, dynamic>>();
  } on RespaldoInvalido {
    rethrow;
  } on Object {
    throw RespaldoInvalido('El archivo de respaldo está dañado.');
  }
}

Map<String, dynamic> _sobre(Uint8List archivo) {
  try {
    final sobre = jsonDecode(utf8.decode(archivo)) as Map<String, dynamic>;
    if (sobre['formato'] == formatoRespaldo) return sobre;
  } on Object {
    // cae al error de abajo
  }
  throw RespaldoInvalido('No es un respaldo de Tres Pisos.');
}

/// La cabecera (restaurante y fecha) va autenticada: si alguien la cambia, el descifrado falla.
GCMBlockCipher _gcm({
  required bool forEncryption,
  required Uint8List clave,
  required Uint8List nonce,
  required Map<String, dynamic> cabecera,
}) =>
    GCMBlockCipher(AESEngine())
      ..init(
        forEncryption,
        AEADParameters(KeyParameter(clave), 128, nonce, Uint8List.fromList(utf8.encode(jsonEncode(cabecera)))),
      );
