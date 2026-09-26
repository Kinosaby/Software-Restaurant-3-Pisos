import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    await ref.read(almacenSesionProvider).guardarConexion(conexion);
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
class AuthController extends Notifier<Sesion?> {
  @override
  Sesion? build() => ref.read(datosArranqueProvider).sesion;

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
  }

  Future<void> cerrarSesion() async {
    if (state == null) return;
    state = null;
    await ref.read(almacenSesionProvider).borrarSesion();
  }
}

/// Cliente HTTP autenticado con la sesión actual. Si el servidor responde 401
/// (token caducado, revocado o código de enlace renovado) se cierra la sesión
/// y el router vuelve al login.
final apiClientProvider = Provider<ApiClient>((ref) {
  final sesion = ref.watch(authControllerProvider);
  if (sesion == null) {
    throw ApiException('No hay sesión iniciada.', status: 401);
  }
  // El enlace puede renovarse en la central sin cambiar la sesión.
  final enlace = ref.watch(conexionProvider.select((c) => c?.enlace)) ?? sesion.conexion.enlace;
  final auth = ref.read(authControllerProvider.notifier);
  return ApiClient(
    servidor: sesion.servidor,
    token: sesion.token,
    enlace: enlace,
    alNoAutorizado: auth.cerrarSesion,
  );
});
