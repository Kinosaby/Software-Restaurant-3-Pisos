import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Red Wi-Fi propia de la central (sin router): nombre, contraseña y seguridad ("wpa2"/"wpa3").
typedef RedWifi = ({String ssid, String clave, String seguridad});

RedWifi? _redDe(Map<Object?, Object?>? datos) {
  final ssid = datos?['ssid'], clave = datos?['clave'];
  if (ssid is! String || clave is! String) return null;
  return (ssid: ssid, clave: clave, seguridad: datos?['seguridad'] == 'wpa3' ? 'wpa3' : 'wpa2');
}

/// Lo que esta versión de Android puede hacer con la red propia: crearla (Android 8+)
/// y unirse a ella sin pasar por Ajustes (Android 10+).
typedef CapacidadesRed = ({bool crearRed, bool unirseSola});

enum FaseRedPropia {
  /// No se trabaja con red propia.
  apagada,
  creando,
  activa,

  /// Se quiere red propia pero ahora no existe: Android la apagó o no pudo crearla.
  caida,
}

/// Estado real de la red propia de la central, tal como lo lleva Android.
class EstadoRedPropia {
  const EstadoRedPropia({
    this.fase = FaseRedPropia.apagada,
    this.red,
    this.error,
    this.codigo,
    this.reintentando = false,
    this.qrNuevo = false,
  });

  /// Lo que manda `RedLocal.estadoCentral()`. Una red "activa" sin nombre o clave no sirve: cuenta como caída.
  factory EstadoRedPropia.desde(Map<Object?, Object?>? datos) {
    if (datos == null) return const EstadoRedPropia();
    final red = _redDe(datos);
    var fase = FaseRedPropia.values.asNameMap()[datos['fase']] ?? FaseRedPropia.apagada;
    if (fase == FaseRedPropia.activa && red == null) fase = FaseRedPropia.caida;
    final error = datos['error'], codigo = datos['codigo'];
    return EstadoRedPropia(
      fase: fase,
      red: fase == FaseRedPropia.activa ? red : null,
      error: error is String && error.isNotEmpty ? error : null,
      codigo: codigo is String ? codigo : null,
      reintentando: datos['reintentando'] == true,
    );
  }

  final FaseRedPropia fase;

  /// Solo con la red activa.
  final RedWifi? red;

  /// Motivo en español por el que la red no está (fase [FaseRedPropia.caida]).
  final String? error;

  /// "PERMISO", "UBICACION" (se arreglan en Ajustes) o "RED".
  final String? codigo;

  /// Android va a volver a intentarlo solo.
  final bool reintentando;

  /// La red es distinta de la última que los meseros escanearon: deben escanear el QR otra vez.
  final bool qrNuevo;

  /// El usuario pidió trabajar con red propia (aunque ahora esté caída).
  bool get pedida => fase != FaseRedPropia.apagada;

  EstadoRedPropia con({required bool qrNuevo}) => EstadoRedPropia(
        fase: fase,
        red: red,
        error: error,
        codigo: codigo,
        reintentando: reintentando,
        qrNuevo: qrNuevo,
      );

  @override
  bool operator ==(Object other) =>
      other is EstadoRedPropia &&
      other.fase == fase &&
      other.red == red &&
      other.error == error &&
      other.codigo == codigo &&
      other.reintentando == reintentando &&
      other.qrNuevo == qrNuevo;

  @override
  int get hashCode => Object.hash(fase, red, error, codigo, reintentando, qrNuevo);
}

enum FaseRedMesero {
  /// La tablet usa su Wi-Fi normal (router) o se conectó a mano.
  ninguna,
  uniendo,
  unida,

  /// Se perdió la red y Android está volviendo a unirse.
  reintentando,

  /// No se pudo volver: hay que escanear de nuevo el QR de la central.
  perdida,
}

/// Mesero: unión de esta tablet a la red propia de la central.
class EstadoRedMesero {
  const EstadoRedMesero({this.fase = FaseRedMesero.ninguna, this.ssid, this.error});

  factory EstadoRedMesero.desde(Map<Object?, Object?>? datos) {
    if (datos == null) return const EstadoRedMesero();
    final ssid = datos['ssid'], error = datos['error'];
    return EstadoRedMesero(
      fase: FaseRedMesero.values.asNameMap()[datos['fase']] ?? FaseRedMesero.ninguna,
      ssid: ssid is String ? ssid : null,
      error: error is String && error.isNotEmpty ? error : null,
    );
  }

  final FaseRedMesero fase;
  final String? ssid;
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is EstadoRedMesero && other.fase == fase && other.ssid == ssid && other.error == error;

  @override
  int get hashCode => Object.hash(fase, ssid, error);
}

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

  /// Solo en la tablet central: servicio en primer plano (aviso fijo "Central de cocina
  /// activa") que evita que Android congele o mate la app al salir de primer plano y
  /// mantiene despiertos la CPU y el Wi-Fi. Con él activo, Atrás en la pantalla raíz
  /// manda la app a segundo plano en lugar de cerrarla.
  static Future<void> servicioCentral(bool activo) => _llamar('servicioCentral', {'activo': activo});

  /// `true` si la app ya está fuera del ahorro de batería (o no se puede saber).
  static Future<bool> bateriaSinRestriccion() async {
    try {
      return await _canal.invokeMethod<bool>('bateriaSinRestriccion') ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException catch (e) {
      debugPrint('Plataforma.bateriaSinRestriccion: ${e.message}');
      return true;
    }
  }

  /// Abre el diálogo del sistema para excluir la app del ahorro de batería.
  static Future<void> pedirSinRestriccionBateria() => _llamar('pedirSinRestriccionBateria');

  /// Qué puede hacer esta tablet con la red propia. Si no se puede saber, se supone que todo.
  static Future<CapacidadesRed> capacidadesRed() async {
    try {
      final datos = await _canal.invokeMapMethod<Object?, Object?>('redCapacidades');
      return (crearRed: datos?['crear'] != false, unirseSola: datos?['unir'] != false);
    } on MissingPluginException {
      return (crearRed: true, unirseSola: true);
    } on PlatformException catch (e) {
      debugPrint('Plataforma.capacidadesRed: ${e.message}');
      return (crearRed: true, unirseSola: true);
    }
  }

  /// Central: crea su propia red Wi-Fi (sin router, internet ni datos), pidiendo antes el
  /// permiso que haga falta. Android elige nombre y contraseña. Lanza [PlatformException]
  /// con el motivo en español si no puede; si el fallo es pasajero, Android sigue
  /// reintentando y el resultado llega por [cambiosRedPropia].
  static Future<RedWifi> crearRedPropia() async {
    final red = _redDe(await _canal.invokeMapMethod<Object?, Object?>('redPropia', {'activa': true}));
    if (red == null) throw PlatformException(code: 'RED', message: 'Android no devolvió los datos de la red.');
    return red;
  }

  static Future<void> apagarRedPropia() => _llamar('redPropia', {'activa': false});

  /// Estado real de la red propia de la central.
  static Future<EstadoRedPropia> estadoRedPropia() async {
    try {
      return EstadoRedPropia.desde(await _canal.invokeMapMethod<Object?, Object?>('redPropiaEstado'));
    } on MissingPluginException {
      return const EstadoRedPropia();
    } on PlatformException catch (e) {
      debugPrint('Plataforma.estadoRedPropia: ${e.message}');
      return const EstadoRedPropia();
    }
  }

  /// Mesero: se une a la red propia de la central y la app la usa para hablar con ella.
  /// Lanza [PlatformException] con el motivo si no lo logra (código "NO_COMPATIBLE"
  /// en Android 9 o anterior, que no puede unirse sin pasar por Ajustes).
  static Future<void> conectarRed(RedWifi red) =>
      _canal.invokeMethod<bool>('conectarRed', {'ssid': red.ssid, 'clave': red.clave, 'seguridad': red.seguridad});

  /// Deja la red propia de la central: la app vuelve a usar el Wi-Fi normal de la tablet.
  static Future<void> desconectarRed() => _llamar('desconectarRed');

  /// Mesero: cómo va la unión a la red propia de la central.
  static Future<EstadoRedMesero> estadoRedMesero() async {
    try {
      return EstadoRedMesero.desde(await _canal.invokeMapMethod<Object?, Object?>('redMeseroEstado'));
    } on MissingPluginException {
      return const EstadoRedMesero();
    } on PlatformException catch (e) {
      debugPrint('Plataforma.estadoRedMesero: ${e.message}');
      return const EstadoRedMesero();
    }
  }

  /// Abre los Ajustes de Android: "ubicacion", "wifi" o "app" (permisos de la app).
  static Future<void> abrirAjustes(String cual) => _llamar('abrirAjustes', {'cual': cual});

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
  static final _redPropia = StreamController<EstadoRedPropia>.broadcast();
  static final _redMesero = StreamController<EstadoRedMesero>.broadcast();
  static bool _escuchando = false;

  /// Avisos que Android manda por su cuenta (sin que Dart los pida).
  static void _escuchar() {
    if (_escuchando) return;
    _escuchando = true;
    _canal.setMethodCallHandler((llamada) async {
      final datos = llamada.arguments;
      switch (llamada.method) {
        case 'enlaceRecibido' when datos is String:
          _enlaces.add(datos);
        case 'redPropiaCambio' when datos is Map:
          _redPropia.add(EstadoRedPropia.desde(datos));
        case 'redMeseroCambio' when datos is Map:
          _redMesero.add(EstadoRedMesero.desde(datos));
      }
    });
  }

  /// Enlaces que llegan con la app ya abierta.
  static Stream<String> get enlaces {
    _escuchar();
    return _enlaces.stream;
  }

  /// Central: la red propia cambió (Android la apagó, se volvió a crear con otro nombre...).
  static Stream<EstadoRedPropia> get cambiosRedPropia {
    _escuchar();
    return _redPropia.stream;
  }

  /// Mesero: se perdió o se recuperó la red propia de la central.
  static Stream<EstadoRedMesero> get cambiosRedMesero {
    _escuchar();
    return _redMesero.stream;
  }

  /// Carpeta privada y persistente de la app (`filesDir` en Android).
  static Future<String> carpetaDatos() async {
    final ruta = await _canal.invokeMethod<String>('carpetaDatos');
    if (ruta == null) throw StateError('Android no devolvió la carpeta de datos');
    return ruta;
  }
}
