import 'dart:convert';

enum Rol {
  admin('Administrador'),
  mesero('Mesero'),
  cocina('Cocina');

  const Rol(this.etiqueta);
  final String etiqueta;

  static Rol? desde(String? valor) {
    for (final rol in Rol.values) {
      if (rol.name == valor) return rol;
    }
    return null;
  }

  bool get tomaPedidos => this == Rol.admin || this == Rol.mesero;
  bool get cobra => this == Rol.admin || this == Rol.mesero;
}

class Usuario {
  const Usuario({required this.id, required this.username, required this.rol});

  factory Usuario.fromJson(Map<String, dynamic> json) {
    final rol = Rol.desde(json['role']?.toString());
    if (rol == null) {
      throw FormatException('Rol desconocido: ${json['role']}');
    }
    return Usuario(
      id: (json['id'] as num).toInt(),
      username: json['username'].toString(),
      rol: rol,
    );
  }

  final int id;
  final String username;
  final Rol rol;

  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'role': rol.name};
}

/// Con quién habla esta tablet.
enum ModoConexion {
  /// Esta tablet es la central de cocina: guarda los datos y atiende a las demás por Wi-Fi.
  central('Central de cocina'),

  /// Conectada a la central de cocina por el Wi-Fi del restaurante (no necesita internet).
  enlazada('Conectada a la central');

  const ModoConexion(this.etiqueta);
  final String etiqueta;
}

/// Todo funciona en la red local del restaurante, sin internet: la tablet de
/// cocina es la central y las demás se conectan a ella.
class Conexion {
  const Conexion({required this.modo, required this.url, this.enlace});

  /// Lanza si el modo guardado ya no existe (p. ej. el antiguo modo "servidor").
  factory Conexion.fromJson(Map<String, dynamic> json) => Conexion(
        modo: ModoConexion.values.firstWhere((m) => m.name == json['modo']),
        url: json['url'] as String,
        enlace: json['enlace'] as String?,
      );

  final ModoConexion modo;
  final String url;

  /// Código de enlace de la central (se manda en `X-Enlace`).
  final String? enlace;

  Map<String, dynamic> toJson() => {'modo': modo.name, 'url': url, 'enlace': ?enlace};

  Conexion copyWith({String? enlace}) => Conexion(modo: modo, url: url, enlace: enlace ?? this.enlace);
}

class Sesion {
  const Sesion({required this.conexion, required this.token, required this.usuario});

  final Conexion conexion;
  final String token;
  final Usuario usuario;

  String get servidor => conexion.url;
}

/// Lee la fecha de expiración (`exp`) de un JWT sin verificar la firma.
/// Solo sirve para no restaurar sesiones ya vencidas; el servidor sigue siendo
/// quien valida el token.
DateTime? expiracionToken(String token) {
  final partes = token.split('.');
  if (partes.length != 3) return null;
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(partes[1])));
    final exp = (jsonDecode(payload) as Map<String, dynamic>)['exp'];
    if (exp is num) {
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
    }
  } on FormatException {
    return null;
  }
  return null;
}

bool tokenVigente(String token, {DateTime? ahora}) {
  final exp = expiracionToken(token);
  if (exp == null) return false;
  // Margen de un minuto para no arrancar con un token a punto de caducar.
  return exp.isAfter((ahora ?? DateTime.now().toUtc()).add(const Duration(minutes: 1)));
}
