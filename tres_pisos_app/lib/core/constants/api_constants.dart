// lib/core/constants/api_constants.dart

class ApiConstants {
  // Cambiar a trespisos.duckdns.org:3000 cuando el port forwarding esté listo
  // Para pruebas locales: http://192.168.x.x:3000
  static const String baseUrl = 'http://trespisos.duckdns.org:3000';

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

  // Métricas
  static const String metricas      = '/api/metricas/resumen';
}
