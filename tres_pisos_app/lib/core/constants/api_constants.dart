// lib/core/constants/api_constants.dart

class ApiConstants {
  /// En producción se inyecta al compilar:
  /// flutter build apk --dart-define=API_BASE_URL=https://servicio.up.railway.app
  /// El valor por defecto permite usar el emulador Android contra localhost.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  // Auth
  static const String login         = '/api/auth/login';
  static const String me            = '/api/auth/me';
  static const String usuarios      = '/api/auth/usuarios';
  static const String register      = '/api/auth/register';
  static String userById(int id)    => '/api/auth/$id';

  // Productos
  static const String productos     = '/api/productos';
  static String productoById(int id)=> '/api/productos/$id';

  // Pedidos
  static const String pedidos       = '/api/pedidos';
  static String pedidoById(int id)  => '/api/pedidos/$id';
  static String pedidoEstado(int id)=> '/api/pedidos/$id/estado';
  static String pedidoCancelar(int id) => '/api/pedidos/$id/cancelar';
  static String pedidoAgregar(int id)   => '/api/pedidos/$id/agregar';
  static String pedidoEditar(int id)    => '/api/pedidos/$id/editar';

  // Métricas
  static const String metricas      = '/api/metricas/resumen';
  static const String health         = '/api/health';
}
