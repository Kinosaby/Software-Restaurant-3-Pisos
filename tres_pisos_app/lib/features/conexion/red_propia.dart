import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/plataforma.dart';
import '../auth/auth_controller.dart';

const _preferencia = 'red_propia';

/// Nombre de la última red que ya se avisó a los meseros (la que escanearon).
const _ssidAvisado = 'red_propia_ssid';

/// Qué puede hacer esta tablet con la red propia según su versión de Android.
final capacidadesRedProvider = FutureProvider<CapacidadesRed>((ref) => Plataforma.capacidadesRed());

/// Red Wi-Fi propia de la central: sin router, sin internet y sin datos, las
/// tablets de los meseros se unen a ella escaneando el QR.
///
/// El estado es el que lleva Android: si el sistema apaga la red, aquí se ve
/// "caída" y, cuando se vuelve a crear (con otro nombre y contraseña), la nueva.
final redPropiaProvider = NotifierProvider<RedPropia, EstadoRedPropia>(RedPropia.new);

class RedPropia extends Notifier<EstadoRedPropia> {
  /// El administrador acaba de encenderla desde la pantalla de la central: ya ve el QR nuevo.
  bool _porUsuario = false;

  @override
  EstadoRedPropia build() {
    final suscripcion = Plataforma.cambiosRedPropia.listen(_recibir);
    ref.onDispose(suscripcion.cancel);
    unawaited(_cargar());
    return const EstadoRedPropia();
  }

  SharedPreferences get _prefs => ref.read(almacenSesionProvider).prefs;

  Future<void> _cargar() async {
    final actual = await Plataforma.estadoRedPropia();
    if (ref.mounted) _recibir(actual);
  }

  void _recibir(EstadoRedPropia nuevo) {
    var qrNuevo = false;
    if (nuevo.red case final red?) {
      if (_porUsuario) {
        unawaited(_prefs.setString(_ssidAvisado, red.ssid));
      } else {
        // Android cambia nombre y contraseña cada vez que crea la red.
        qrNuevo = _prefs.getString(_ssidAvisado) != red.ssid;
      }
    }
    state = nuevo.con(qrNuevo: qrNuevo);
  }

  /// Enciende la red o, si estaba caída, lo vuelve a intentar. Devuelve el motivo
  /// en español si no se pudo (el estado guarda el mismo motivo), o `null`.
  Future<String?> encender() async {
    _porUsuario = !state.pedida;
    try {
      await _prefs.setBool(_preferencia, true);
      if (state.fase != FaseRedPropia.activa) state = const EstadoRedPropia(fase: FaseRedPropia.creando);
      final red = await Plataforma.crearRedPropia();
      if (ref.mounted) _recibir(EstadoRedPropia(fase: FaseRedPropia.activa, red: red));
      return null;
    } on PlatformException catch (e) {
      final actual = await Plataforma.estadoRedPropia();
      if (!ref.mounted) return null;
      _recibir(actual);
      // Android no la va a crear (p. ej. una tablet con Android 7): no se intenta al abrir la app.
      if (!actual.pedida) await _prefs.setBool(_preferencia, false);
      return e.message ?? 'No se pudo crear la red propia de la central.';
    } on MissingPluginException {
      if (ref.mounted) state = const EstadoRedPropia();
      return 'La red propia solo funciona en la tablet (Android).';
    } finally {
      _porUsuario = false;
    }
  }

  Future<void> apagar() async {
    await Plataforma.apagarRedPropia();
    await _prefs.setBool(_preferencia, false);
    await _prefs.remove(_ssidAvisado);
    if (ref.mounted) state = const EstadoRedPropia();
  }

  /// Los meseros ya volvieron a escanear el QR de la red actual.
  Future<void> qrAvisado() async {
    final red = state.red;
    if (red == null) return;
    state = state.con(qrNuevo: false);
    await _prefs.setString(_ssidAvisado, red.ssid);
  }
}

/// Al arrancar la central: si trabajaba con red propia, la vuelve a crear.
///
/// No espera a Android (puede tardar o pedir un permiso) para no retrasar el arranque:
/// el resultado, y el motivo si falla, llegan a [redPropiaProvider] y se ven en el
/// aviso de red y en la pantalla de la central. Por eso siempre devuelve `null`.
Future<String?> reanudarRedPropia(SharedPreferences prefs) async {
  if (prefs.getBool(_preferencia) != true) return null;
  unawaited(Plataforma.crearRedPropia().then<void>((_) {}, onError: (Object _) {}));
  return null;
}

/// Mesero: cómo va la unión de esta tablet a la red propia de la central.
final redMeseroProvider = NotifierProvider<RedMesero, EstadoRedMesero>(RedMesero.new);

class RedMesero extends Notifier<EstadoRedMesero> {
  @override
  EstadoRedMesero build() {
    final suscripcion = Plataforma.cambiosRedMesero.listen((nuevo) => state = nuevo);
    ref.onDispose(suscripcion.cancel);
    unawaited(_cargar());
    return const EstadoRedMesero();
  }

  Future<void> _cargar() async {
    final actual = await Plataforma.estadoRedMesero();
    if (ref.mounted) state = actual;
  }

  /// Vuelve a unirse a la red guardada de la central (la del último QR escaneado).
  Future<void> reintentar() => unirseARedGuardada(ref.read(conexionProvider)?.red);
}

/// Mesero: si la central trabaja con red propia, vuelve a unirse al abrir la app.
/// Si no lo logra, [redMeseroProvider] queda en "perdida" y el aviso de red lo dice.
Future<void> unirseARedGuardada(RedWifi? red) async {
  if (red == null) return;
  try {
    await Plataforma.conectarRed(red);
  } on PlatformException {
    // El aviso de red ya dice qué hacer (o es Android 9 o anterior, que se conecta desde Ajustes).
  } on MissingPluginException {
    // Pruebas.
  }
}
