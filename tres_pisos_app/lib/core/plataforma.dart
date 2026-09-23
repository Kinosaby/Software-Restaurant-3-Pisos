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

  static Future<void> multicast(bool activo) => _llamar('multicast', {'activo': activo});

  /// Carpeta privada y persistente de la app (`filesDir` en Android).
  static Future<String> carpetaDatos() async {
    final ruta = await _canal.invokeMethod<String>('carpetaDatos');
    if (ruta == null) throw StateError('Android no devolvió la carpeta de datos');
    return ruta;
  }
}
