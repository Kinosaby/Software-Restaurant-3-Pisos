// lib/core/services/auth_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'pos_token';
  static const _userKey  = 'pos_user';

  static Future<void> saveSession(String token, Map<String, dynamic> user) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey,  value: jsonEncode(user));
  }

  static Future<String?> getToken() => _storage.read(key: _tokenKey);

  static Future<Map<String, dynamic>?> getUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      await clearSession();
      return null;
    }
  }

  static Future<void> clearSession() async {
    await _storage.deleteAll();
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    final user = await getUser();
    return token != null && token.isNotEmpty && user != null;
  }

  /// Devuelve el rol del usuario guardado ('admin', 'mesero', 'cocina')
  static Future<String> getRole() async {
    final user = await getUser();
    if (user == null) return '';
    return (user['role'] ?? user['rol'] ?? '').toString();
  }
}
