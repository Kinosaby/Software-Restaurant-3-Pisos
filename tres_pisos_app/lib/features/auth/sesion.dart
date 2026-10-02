import 'dart:convert';

import '../../core/plataforma.dart' show RedWifi;

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
  const Conexion({required this.modo, required this.url, this.enlace, this.red});

  /// Lanza si el modo guardado ya no existe (p. ej. el antiguo modo "servidor").
  factory Conexion.fromJson(Map<String, dynamic> json) {
    final red = json['red'];
    return Conexion(
      modo: ModoConexion.values.firstWhere((m) => m.name == json['modo']),
      url: json['url'] as String,
      enlace: json['enlace'] as String?,
      red: red is Map && red['ssid'] is String && red['clave'] is String
          ? (ssid: red['ssid'] as String, clave: red['clave'] as String, seguridad: red['seguridad'] == 'wpa3' ? 'wpa3' : 'wpa2')
          : null,
    );
  }

  final ModoConexion modo;
  final String url;

  /// Código de enlace de la central (se manda en `X-Enlace`).
  final String? enlace;

  /// Red Wi-Fi propia de la central (sin router): al abrir la app el mesero se vuelve a unir.
  final RedWifi? red;

  Map<String, dynamic> toJson() => {
        'modo': modo.name,
        'url': url,
        'enlace': ?enlace,
        if (red case final r?) 'red': {'ssid': r.ssid, 'clave': r.clave, 'seguridad': r.seguridad},
      };

  Conexion copyWith({String? enlace}) => Conexion(modo: modo, url: url, enlace: enlace ?? this.enlace, red: red);
}

class Sesion {
  const Sesion({required this.conexion, required this.token, required this.usuario, this.desfase = Duration.zero});

  final Conexion conexion;
  final String token;
  final Usuario usuario;

  /// Hora de la central menos la hora de esta tablet, medida al recibir el
  /// token (ver [desfaseConCentral]). Las fechas del token son de la central y
  /// las tablets no tienen internet: sus relojes pueden ir horas o días
  /// desfasados. `null` si no se conoce (sesión guardada por una versión
  /// anterior): se renueva en cuanto se puede para medirlo.
  final Duration? desfase;

  String get servidor => conexion.url;

  /// La hora que tiene la central ahora, calculada con el reloj de esta tablet.
  DateTime horaCentral({DateTime? ahora}) => (ahora ?? DateTime.now()).toUtc().add(desfase ?? Duration.zero);

  /// Ya pasó la mitad de la vigencia del token según la hora de la central.
  bool debeRenovar({DateTime? ahora}) => desfase == null
      ? mitadVigenciaToken(token) != null
      : debeRenovarToken(token, ahora: horaCentral(ahora: ahora));

  /// Cuánto falta para renovar; `null` si el token no trae fechas.
  Duration? hastaRenovar({DateTime? ahora}) {
    final mitad = mitadVigenciaToken(token);
    if (mitad == null) return null;
    if (desfase == null) return Duration.zero;
    final falta = mitad.difference(horaCentral(ahora: ahora));
    return falta.isNegative ? Duration.zero : falta;
  }

  /// El token no ha caducado según la hora de la central. Solo sirve para no
  /// restaurar sesiones vencidas: quien decide si vale es la central.
  bool vigente({DateTime? ahora}) => tokenVigente(token, ahora: horaCentral(ahora: ahora));
}

/// Desfase entre el reloj de la central y el de esta tablet: el token recién
/// recibido trae la hora de la central en que se firmó (`iat`). Llamar justo al
/// recibirlo. `null` si el token no trae esa fecha.
Duration? desfaseConCentral(String token, {DateTime? ahora}) =>
    _fechaToken(token, 'iat')?.difference((ahora ?? DateTime.now()).toUtc());

/// Lee la fecha de expiración (`exp`) de un JWT sin verificar la firma.
/// Solo sirve para no restaurar sesiones ya vencidas; el servidor sigue siendo
/// quien valida el token. Es una hora de la central, no de esta tablet.
DateTime? expiracionToken(String token) => _fechaToken(token, 'exp');

DateTime? _fechaToken(String token, String campo) {
  final partes = token.split('.');
  if (partes.length != 3) return null;
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(partes[1])));
    final valor = (jsonDecode(payload) as Map<String, dynamic>)[campo];
    if (valor is num) {
      return DateTime.fromMillisecondsSinceEpoch(valor.toInt() * 1000, isUtc: true);
    }
  } on Object {
    return null;
  }
  return null;
}

/// Momento en que conviene renovar el token: la mitad de su vigencia (`iat` → `exp`).
/// `null` si el token no trae esas fechas.
DateTime? mitadVigenciaToken(String token) {
  final emitido = _fechaToken(token, 'iat');
  final expira = expiracionToken(token);
  if (emitido == null || expira == null || !expira.isAfter(emitido)) return null;
  return emitido.add(expira.difference(emitido) ~/ 2);
}

/// Ya pasó la mitad de la vigencia del token: hay que pedir uno nuevo.
/// [ahora] debe ser la hora de la central ([Sesion.horaCentral]).
bool debeRenovarToken(String token, {DateTime? ahora}) {
  final mitad = mitadVigenciaToken(token);
  return mitad != null && !(ahora ?? DateTime.now().toUtc()).isBefore(mitad);
}

/// [ahora] debe ser la hora de la central ([Sesion.horaCentral]).
bool tokenVigente(String token, {DateTime? ahora}) {
  final exp = expiracionToken(token);
  if (exp == null) return false;
  // Margen de un minuto para no arrancar con un token a punto de caducar.
  return exp.isAfter((ahora ?? DateTime.now().toUtc()).add(const Duration(minutes: 1)));
}
