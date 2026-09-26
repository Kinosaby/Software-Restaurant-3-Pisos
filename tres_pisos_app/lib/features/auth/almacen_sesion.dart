import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sesion.dart';

/// Lo que la app necesita saber al arrancar, antes de pintar la primera pantalla.
class DatosArranque {
  const DatosArranque({this.conexion, this.sesion});

  /// `null` la primera vez: hay que elegir cómo se conecta esta tablet.
  final Conexion? conexion;
  final Sesion? sesion;
}

/// Guarda la conexión y la sesión (token + usuario) en el almacenamiento privado de la app.
///
/// No usamos flutter_secure_storage: su cadena de dependencias (path_provider →
/// objective_c) ejecuta un hook de compilación que falla cuando la ruta del SDK
/// de Flutter tiene espacios. Los tokens de la central caducan a las 12 h.
class AlmacenSesion {
  AlmacenSesion(this.prefs);

  final SharedPreferences prefs;

  static const _kConexion = 'conexion';
  static const _kToken = 'token';
  static const _kUsuario = 'usuario';

  /// `null` si nunca se configuró o si era una conexión al antiguo servidor web:
  /// en ambos casos hay que elegir de nuevo (central o conectada a la central).
  Conexion? cargarConexion() {
    final json = prefs.getString(_kConexion);
    if (json == null) return null;
    try {
      return Conexion.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  DatosArranque cargar() {
    final conexion = cargarConexion();
    final token = prefs.getString(_kToken);
    final usuarioJson = prefs.getString(_kUsuario);

    if (conexion == null || token == null || usuarioJson == null || !tokenVigente(token)) {
      return DatosArranque(conexion: conexion);
    }
    try {
      final usuario = Usuario.fromJson(jsonDecode(usuarioJson) as Map<String, dynamic>);
      return DatosArranque(
        conexion: conexion,
        sesion: Sesion(conexion: conexion, token: token, usuario: usuario),
      );
    } on Object {
      return DatosArranque(conexion: conexion);
    }
  }

  Future<void> guardarConexion(Conexion conexion) async {
    await prefs.setString(_kConexion, jsonEncode(conexion.toJson()));
  }

  Future<void> guardar(Sesion sesion) async {
    await guardarConexion(sesion.conexion);
    await prefs.setString(_kToken, sesion.token);
    await prefs.setString(_kUsuario, jsonEncode(sesion.usuario.toJson()));
  }

  /// Borra el token pero recuerda la conexión para el siguiente inicio de sesión.
  Future<void> borrarSesion() async {
    await prefs.remove(_kToken);
    await prefs.remove(_kUsuario);
  }
}
