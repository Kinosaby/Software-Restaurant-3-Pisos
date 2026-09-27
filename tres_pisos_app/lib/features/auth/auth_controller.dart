import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/almacen_local.dart';
import '../../core/api_client.dart';
import 'almacen_sesion.dart';
import 'sesion.dart';

/// Se sobreescribe en `main()` con lo leído del almacenamiento antes de arrancar.
final datosArranqueProvider = Provider<DatosArranque>(
  (ref) => throw UnimplementedError('datosArranqueProvider se define en main()'),
);

/// Se sobreescribe en `main()` una vez abierto SharedPreferences.
final almacenSesionProvider = Provider<AlmacenSesion>(
  (ref) => throw UnimplementedError('almacenSesionProvider se define en main()'),
);

/// Con quién habla esta tablet; `null` hasta que se configura por primera vez.
final conexionProvider = NotifierProvider<ConexionController, Conexion?>(ConexionController.new);

class ConexionController extends Notifier<Conexion?> {
  @override
  Conexion? build() => ref.read(datosArranqueProvider).conexion;

  /// Cambiar de conexión cierra la sesión: el token de un servidor no vale en otro.
  Future<void> usar(Conexion conexion) async {
    await ref.read(authControllerProvider.notifier).cerrarSesion();
    final anterior = state;
    final almacen = ref.read(almacenSesionProvider);
    // Misma central (mismo código) con otra IP: la cola sin enviar no se queda atrás.
    if (anterior != null &&
        anterior.modo == ModoConexion.enlazada &&
        conexion.modo == ModoConexion.enlazada &&
        anterior.enlace != null &&
        anterior.enlace == conexion.enlace) {
      await AlmacenLocal.mudar(almacen.prefs, desde: anterior.url, hacia: conexion.url);
    }
    await almacen.guardarConexion(conexion);
    state = conexion;
  }

  /// La central renovó su código: se actualiza sin cerrar la sesión local.
  Future<void> actualizarEnlace(String enlace) async {
    final actual = state;
    if (actual == null) return;
    final nueva = actual.copyWith(enlace: enlace);
    await ref.read(almacenSesionProvider).guardarConexion(nueva);
    state = nueva;
  }
}

final authControllerProvider = NotifierProvider<AuthController, Sesion?>(AuthController.new);

/// Sesión actual; `null` cuando no hay nadie identificado.
///
/// El token dura 12 h: al pasar la mitad se pide uno nuevo a la central
/// (`POST /api/auth/renovar`) para que un turno largo no deje a nadie fuera.
/// Si la central responde 401 (sesión revocada o caducada) se cierra la sesión.
class AuthController extends Notifier<Sesion?> {
  Timer? _renovacion;
  Future<void>? _renovando;

  @override
  Sesion? build() {
    ref.onDispose(() => _renovacion?.cancel());
    final sesion = ref.read(datosArranqueProvider).sesion;
    _programarRenovacion(sesion);
    return sesion;
  }

  /// Token actual, leído en cada petición (cambia al renovarse).
  String? get tokenActual => state?.token;

  void _programarRenovacion(Sesion? sesion, {Duration? espera}) {
    _renovacion?.cancel();
    _renovacion = null;
    if (sesion == null) return;
    final mitad = mitadVigenciaToken(sesion.token);
    if (mitad == null) return;
    final hastaMitad = mitad.difference(DateTime.now().toUtc());
    final retraso = espera ?? (hastaMitad.isNegative ? Duration.zero : hastaMitad);
    _renovacion = Timer(retraso, () => unawaited(renovarSiHaceFalta()));
  }

  /// Pide un token nuevo si ya pasó la mitad de la vigencia del actual (también
  /// se llama al reconectar el tiempo real). Sin red, o con una central de una
  /// versión anterior que no sabe renovar, se reintenta más tarde.
  Future<void> renovarSiHaceFalta() => _renovando ??= _renovar().whenComplete(() => _renovando = null);

  Future<void> _renovar() async {
    final sesion = state;
    if (sesion == null || !debeRenovarToken(sesion.token)) return;
    final enlace = ref.read(conexionProvider)?.enlace ?? sesion.conexion.enlace;
    try {
      final datos = await ApiClient(servidor: sesion.servidor, token: sesion.token, enlace: enlace)
          .post('/api/auth/renovar', const <String, dynamic>{});
      final token = datos['token'];
      if (token is! String || !identical(state, sesion)) return;
      final user = datos['user'];
      final nueva = Sesion(
        conexion: sesion.conexion,
        token: token,
        usuario: user is Map<String, dynamic> ? Usuario.fromJson(user) : sesion.usuario,
      );
      await ref.read(almacenSesionProvider).guardar(nueva);
      if (!identical(state, sesion)) return;
      state = nueva;
      _programarRenovacion(nueva);
    } on ApiException catch (e) {
      if (!identical(state, sesion)) return;
      if (e.noAutorizado) {
        await cerrarSesion();
        return;
      }
      _programarRenovacion(sesion, espera: Duration(minutes: e.sinConexion ? 1 : 10));
    } on FormatException {
      if (identical(state, sesion)) _programarRenovacion(sesion, espera: const Duration(minutes: 10));
    }
  }

  Future<void> iniciarSesion({required String usuario, required String password}) async {
    final conexion = ref.read(conexionProvider);
    if (conexion == null) throw ApiException('Primero configura la conexión de esta tablet.');

    final datos = await ApiClient(servidor: conexion.url, enlace: conexion.enlace).post('/api/auth/login', {
      'username': usuario.trim(),
      'password': password,
    });

    final token = datos['token'];
    final user = datos['user'];
    if (token is! String || user is! Map<String, dynamic>) {
      throw ApiException('Respuesta de login inválida.');
    }
    final sesion = Sesion(conexion: conexion, token: token, usuario: Usuario.fromJson(user));

    await ref.read(almacenSesionProvider).guardar(sesion);
    state = sesion;
    _programarRenovacion(sesion);
  }

  Future<void> cerrarSesion() async {
    _renovacion?.cancel();
    _renovacion = null;
    if (state == null) return;
    state = null;
    await ref.read(almacenSesionProvider).borrarSesion();
  }
}

/// Identifica la sesión sin el token: renovar el token no la cambia, así que no
/// se reconstruyen el cliente HTTP, el tiempo real ni lo que depende de ellos.
final sesionActivaProvider = Provider<({String servidor, String? enlace, int usuario})?>((ref) =>
    ref.watch(authControllerProvider.select((s) =>
        s == null ? null : (servidor: s.servidor, enlace: s.conexion.enlace, usuario: s.usuario.id))));

/// Cliente HTTP autenticado con la sesión actual. Si el servidor responde 401
/// (token caducado, revocado o código de enlace renovado) se cierra la sesión
/// y el router vuelve al login.
final apiClientProvider = Provider<ApiClient>((ref) {
  final sesion = ref.watch(sesionActivaProvider);
  if (sesion == null) {
    throw ApiException('No hay sesión iniciada.', status: 401);
  }
  // El enlace puede renovarse en la central sin cambiar la sesión.
  final enlace = ref.watch(conexionProvider.select((c) => c?.enlace)) ?? sesion.enlace;
  final auth = ref.read(authControllerProvider.notifier);
  return ApiClient(
    servidor: sesion.servidor,
    token: auth.tokenActual,
    enlace: enlace,
    alNoAutorizado: auth.cerrarSesion,
    leerToken: () => auth.tokenActual,
  );
});
