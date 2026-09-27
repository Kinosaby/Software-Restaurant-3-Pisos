import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/plataforma.dart';
import '../auth/auth_controller.dart';

const _preferencia = 'red_propia';

/// Red Wi-Fi propia de la central: sin router, sin internet y sin datos, las
/// tablets de los meseros se unen a ella escaneando el QR.
final redPropiaProvider = AsyncNotifierProvider<RedPropia, RedWifi?>(RedPropia.new);

class RedPropia extends AsyncNotifier<RedWifi?> {
  @override
  Future<RedWifi?> build() => Plataforma.redPropiaActual();

  /// Android elige nombre y contraseña: cambian cada vez que se crea la red.
  Future<void> encender() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final red = await Plataforma.crearRedPropia();
      await ref.read(almacenSesionProvider).prefs.setBool(_preferencia, true);
      return red;
    });
  }

  Future<void> apagar() async {
    await Plataforma.apagarRedPropia();
    await ref.read(almacenSesionProvider).prefs.setBool(_preferencia, false);
    state = const AsyncData(null);
  }
}

/// Al arrancar la central: si trabajaba con red propia, la vuelve a crear.
/// Devuelve el motivo si no pudo (para avisarlo), o `null`.
Future<String?> reanudarRedPropia(SharedPreferences prefs) async {
  if (prefs.getBool(_preferencia) != true) return null;
  try {
    await Plataforma.crearRedPropia();
    return null;
  } on PlatformException catch (e) {
    return e.message ?? 'No se pudo crear la red propia de la central.';
  } on MissingPluginException {
    return null;
  }
}

/// Mesero: si la central trabaja con red propia, vuelve a unirse al abrir la app.
Future<void> unirseARedGuardada(RedWifi? red) async {
  if (red == null) return;
  try {
    await Plataforma.conectarRed(red);
  } on PlatformException {
    // La app sigue reintentando conectar con la central; el aviso de "sin conexión" ya se ve.
  } on MissingPluginException {
    // Pruebas.
  }
}
