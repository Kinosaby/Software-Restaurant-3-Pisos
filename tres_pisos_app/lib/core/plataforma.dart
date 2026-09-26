import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Funciones de Android expuestas por `MainActivity` (canal "tres_pisos/plataforma").
/// Todas fallan en silencio: un aviso que no suena no debe romper el flujo del pedido.
abstract final class Plataforma {
  static const _canal = MethodChannel('tres_pisos/plataforma');

  static Future<void> _llamar(String metodo, [Map<String, Object?>? args]) async {
    try {
      await _canal.invokeMethod<void>(metodo, args);
    } on MissingPluginException {
      // Pruebas o plataformas sin el canal.
    } on PlatformException catch (e) {
      debugPrint('Plataforma.$metodo: ${e.message}');
    }
  }

  /// "pedido": entra trabajo a cocina. "listo": un pedido está para servir.
  static Future<void> sonar(String tipo) => _llamar('sonar', {'tipo': tipo});

  static Future<void> vibrar(List<int> patron) => _llamar('vibrar', {'patron': patron});

  static Future<void> pantallaEncendida(bool activa) => _llamar('pantallaEncendida', {'activa': activa});

  static Future<void> compartirImagen(Uint8List png, {required String nombre, String? texto}) =>
      _llamar('compartirImagen', {'bytes': png, 'nombre': nombre, 'texto': texto});

  static Future<void> compartirArchivo(Uint8List bytes, {required String nombre, String tipo = 'application/octet-stream', String? texto}) =>
      _llamar('compartirArchivo', {'bytes': bytes, 'nombre': nombre, 'tipo': tipo, 'texto': texto});

  /// Abre el selector de Android para guardar el archivo. `false` si el usuario cancela.
  /// A diferencia de los avisos, aquí los errores sí se propagan: el usuario debe saber si no se guardó.
  static Future<bool> guardarArchivo(Uint8List bytes, {required String nombre, String tipo = 'application/octet-stream'}) async =>
      await _canal.invokeMethod<bool>('guardarArchivo', {'bytes': bytes, 'nombre': nombre, 'tipo': tipo}) ?? false;

  /// Abre el selector de Android para elegir un archivo. `null` si el usuario cancela.
  static Future<Uint8List?> abrirArchivo() => _canal.invokeMethod<Uint8List>('abrirArchivo');

  static Future<void> multicast(bool activo) => _llamar('multicast', {'activo': activo});

  /// Escanea un QR con el escáner de Google Play Services. `null` si se cancela;
  /// lanza [PlatformException] si el escáner no está disponible en la tablet.
  static Future<String?> escanearQr() => _canal.invokeMethod<String>('escanearQr');

  /// Enlace `trespisos://…` con el que se abrió la app (QR leído con la cámara del sistema).
  static Future<String?> enlaceInicial() async {
    try {
      return await _canal.invokeMethod<String>('enlaceInicial');
    } on MissingPluginException {
      return null;
    }
  }

  static final _enlaces = StreamController<String>.broadcast();
  static bool _escuchando = false;

  /// Enlaces que llegan con la app ya abierta.
  static Stream<String> get enlaces {
    if (!_escuchando) {
      _escuchando = true;
      _canal.setMethodCallHandler((llamada) async {
        if (llamada.method == 'enlaceRecibido' && llamada.arguments is String) {
          _enlaces.add(llamada.arguments as String);
        }
      });
    }
    return _enlaces.stream;
  }

  /// Carpeta privada y persistente de la app (`filesDir` en Android).
  static Future<String> carpetaDatos() async {
    final ruta = await _canal.invokeMethod<String>('carpetaDatos');
    if (ruta == null) throw StateError('Android no devolvió la carpeta de datos');
    return ruta;
  }
}
