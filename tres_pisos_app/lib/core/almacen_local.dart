import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/auth/auth_controller.dart';

/// Datos que la tablet guarda para trabajar sin conexión: caché del menú y de
/// los pedidos, cola de envíos, estado de cocina y favoritos.
///
/// Todo va separado por servidor (URL), para no mezclar datos si la tablet
/// cambia de conexión.
class AlmacenLocal {
  AlmacenLocal(this._prefs, this._servidor);

  final SharedPreferences _prefs;
  final String _servidor;

  String _clave(String nombre) => 'local:$_servidor:$nombre';

  List<Map<String, dynamic>>? lista(String nombre) {
    final json = _prefs.getString(_clave(nombre));
    if (json == null) return null;
    try {
      return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    } on Object {
      return null;
    }
  }

  Future<void> guardarLista(String nombre, List<Map<String, dynamic>> datos) =>
      _prefs.setString(_clave(nombre), jsonEncode(datos));

  Map<String, dynamic> mapa(String nombre) {
    final json = _prefs.getString(_clave(nombre));
    if (json == null) return {};
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } on Object {
      return {};
    }
  }

  Future<void> guardarMapa(String nombre, Map<String, dynamic> datos) =>
      _prefs.setString(_clave(nombre), jsonEncode(datos));

  /// Preferencias de la tablet (no dependen del servidor).
  bool preferencia(String nombre, {bool porDefecto = true}) => _prefs.getBool('pref:$nombre') ?? porDefecto;

  Future<void> guardarPreferencia(String nombre, bool valor) => _prefs.setBool('pref:$nombre', valor);
}

final almacenLocalProvider = Provider<AlmacenLocal>((ref) {
  final servidor = ref.watch(conexionProvider.select((c) => c?.url)) ?? 'sin-conexion';
  return AlmacenLocal(ref.watch(almacenSesionProvider).prefs, servidor);
});
