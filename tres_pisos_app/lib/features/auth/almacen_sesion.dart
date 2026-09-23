import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config.dart';
import 'sesion.dart';

/// Lo que la app necesita saber al arrancar, antes de pintar la primera pantalla.
class DatosArranque {
  const DatosArranque({required this.servidor, this.sesion});

  final String servidor;
  final Sesion? sesion;
}

/// Guarda el servidor y la sesión (token + usuario) en el almacenamiento privado de la app.
///
/// No usamos flutter_secure_storage: su cadena de dependencias (path_provider →
/// objective_c) ejecuta un hook de compilación que falla cuando la ruta del SDK
/// de Flutter tiene espacios. El token caduca a las 8 h (JWT_EXPIRES_IN).
class AlmacenSesion {
  AlmacenSesion(this._prefs);

  final SharedPreferences _prefs;

  static const _kServidor = 'servidor';
  static const _kToken = 'token';
  static const _kUsuario = 'usuario';

  DatosArranque cargar() {
    final servidor = _prefs.getString(_kServidor) ?? servidorPorDefecto;
    final token = _prefs.getString(_kToken);
    final usuarioJson = _prefs.getString(_kUsuario);

    if (token == null || usuarioJson == null || !tokenVigente(token)) {
      return DatosArranque(servidor: servidor);
    }
    try {
      final usuario = Usuario.fromJson(jsonDecode(usuarioJson) as Map<String, dynamic>);
      return DatosArranque(
        servidor: servidor,
        sesion: Sesion(servidor: servidor, token: token, usuario: usuario),
      );
    } on Object {
      return DatosArranque(servidor: servidor);
    }
  }

  Future<void> guardar(Sesion sesion) async {
    await _prefs.setString(_kServidor, sesion.servidor);
    await _prefs.setString(_kToken, sesion.token);
    await _prefs.setString(_kUsuario, jsonEncode(sesion.usuario.toJson()));
  }

  /// Borra el token pero recuerda el servidor para el siguiente inicio de sesión.
  Future<void> borrarSesion() async {
    await _prefs.remove(_kToken);
    await _prefs.remove(_kUsuario);
  }
}
