import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
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

final authControllerProvider = NotifierProvider<AuthController, Sesion?>(AuthController.new);

/// Sesión actual; `null` cuando no hay nadie identificado.
class AuthController extends Notifier<Sesion?> {
  late String _servidor;

  /// Último servidor usado, para rellenar el formulario de login.
  String get servidor => _servidor;

  @override
  Sesion? build() {
    final arranque = ref.read(datosArranqueProvider);
    _servidor = arranque.servidor;
    return arranque.sesion;
  }

  Future<void> iniciarSesion({
    required String servidor,
    required String usuario,
    required String password,
  }) async {
    final url = normalizarServidor(servidor);
    final datos = await ApiClient(servidor: url).post('/api/auth/login', {
      'username': usuario.trim(),
      'password': password,
    });

    final token = datos['token'];
    final user = datos['user'];
    if (token is! String || user is! Map<String, dynamic>) {
      throw ApiException('Respuesta de login inválida.');
    }
    final sesion = Sesion(servidor: url, token: token, usuario: Usuario.fromJson(user));

    await ref.read(almacenSesionProvider).guardar(sesion);
    _servidor = url;
    state = sesion;
  }

  Future<void> cerrarSesion() async {
    if (state == null) return;
    state = null;
    await ref.read(almacenSesionProvider).borrarSesion();
  }
}

/// Cliente HTTP autenticado con la sesión actual. Si el servidor responde 401
/// (token caducado o inválido) se cierra la sesión y el router vuelve al login.
final apiClientProvider = Provider<ApiClient>((ref) {
  final sesion = ref.watch(authControllerProvider);
  if (sesion == null) {
    throw ApiException('No hay sesión iniciada.', status: 401);
  }
  final auth = ref.read(authControllerProvider.notifier);
  return ApiClient(
    servidor: sesion.servidor,
    token: sesion.token,
    alNoAutorizado: auth.cerrarSesion,
  );
});
