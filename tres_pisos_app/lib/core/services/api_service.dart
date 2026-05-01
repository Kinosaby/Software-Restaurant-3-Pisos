// lib/core/services/api_service.dart
import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import 'auth_service.dart';

class ApiService {
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ));

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await AuthService.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) {
        return handler.next(e);
      },
    ));
    _initialized = true;
  }

  // ───────── AUTH ─────────
  static Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await _dio.post(ApiConstants.login, data: {'username': username, 'password': password});
    return res.data;
  }

  // ───────── PRODUCTOS ─────────
  static Future<List<dynamic>> getProductos() async {
    final res = await _dio.get(ApiConstants.productos);
    return res.data['productos'] ?? [];
  }

  static Future<void> createProducto(Map<String, dynamic> data) async {
    await _dio.post(ApiConstants.productos, data: data);
  }

  static Future<void> updateProducto(int id, Map<String, dynamic> data) async {
    await _dio.put(ApiConstants.productoById(id), data: data);
  }

  static Future<void> deleteProducto(int id) async {
    await _dio.delete(ApiConstants.productoById(id));
  }

  // ───────── PEDIDOS ─────────
  static Future<List<dynamic>> getPedidos({String estado = ''}) async {
    final path = estado.isNotEmpty
        ? '${ApiConstants.pedidos}?estado=$estado'
        : ApiConstants.pedidos;
    final res = await _dio.get(path);
    return res.data['pedidos'] ?? [];
  }

  static Future<Map<String, dynamic>> createPedido(Map<String, dynamic> data) async {
    final res = await _dio.post(ApiConstants.pedidos, data: data);
    return res.data;
  }

  static Future<void> cambiarEstadoPedido(int id, String estado) async {
    await _dio.put(ApiConstants.pedidoEstado(id), data: {'estado': estado});
  }

  static Future<void> cancelarPedido(int id) async {
    await _dio.patch(ApiConstants.pedidoCancelar(id));
  }

  static Future<void> deletePedido(int id) async {
    await _dio.delete(ApiConstants.pedidoById(id));
  }

  // ───────── USUARIOS ─────────
  static Future<List<dynamic>> getUsuarios() async {
    final res = await _dio.get(ApiConstants.usuarios);
    return res.data['usuarios'] ?? [];
  }

  static Future<void> createUsuario(Map<String, dynamic> data) async {
    await _dio.post(ApiConstants.register, data: data);
  }

  static Future<void> updateUsuario(int id, Map<String, dynamic> data) async {
    await _dio.put(ApiConstants.userById(id), data: data);
  }

  static Future<void> deleteUsuario(int id) async {
    await _dio.delete(ApiConstants.userById(id));
  }

  // ───────── MÉTRICAS ─────────
  static Future<Map<String, dynamic>> getMetricas() async {
    final res = await _dio.get(ApiConstants.metricas);
    return res.data;
  }
}
