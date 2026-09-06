// lib/core/services/api_service.dart
import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import '../errors/api_exception.dart';
import 'auth_service.dart';

class ApiService {
  static void Function()? onUnauthorized;
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
      onError: (DioException e, handler) async {
        if (e.response?.statusCode == 401) {
          await AuthService.clearSession();
          onUnauthorized?.call();
        }
        return handler.reject(e);
      },
    ));
    _initialized = true;
  }

  static ApiException _mapError(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final data = error.response?.data;
      String? message;
      String? code;
      if (data is Map) {
        message = data['error']?.toString() ?? data['mensaje']?.toString();
        code = data['code']?.toString();
        final errors = data['errors'];
        if (message == null && errors is List && errors.isNotEmpty) {
          final first = errors.first;
          if (first is Map) message = first['mensaje']?.toString();
        }
      }

      message ??= switch (error.type) {
        DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout =>
          'El servidor tardó demasiado en responder.',
        DioExceptionType.connectionError =>
          'No se pudo conectar con el servidor. Revisa tu internet.',
        _ => 'Ocurrió un error al comunicarse con el servidor.',
      };

      return ApiException(
        message,
        statusCode: error.response?.statusCode,
        code: code,
      );
    }
    return ApiException(error.toString());
  }

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      throw _mapError(error);
    }
  }

  // ───────── AUTH ─────────
  static Future<Map<String, dynamic>> login(String username, String password) async {
    return _guard(() async {
      final res = await _dio.post(ApiConstants.login, data: {'username': username, 'password': password});
      return Map<String, dynamic>.from(res.data as Map);
    });
  }

  static Future<bool> healthCheck() => _guard(() async {
    final res = await _dio.get(ApiConstants.health);
    return res.statusCode == 200 && res.data?['status'] == 'ok';
  });

  // ───────── PRODUCTOS ─────────
  static Future<List<dynamic>> getProductos() async {
    return _guard(() async {
      final res = await _dio.get(ApiConstants.productos);
      return res.data['productos'] ?? <dynamic>[];
    });
  }

  static Future<void> createProducto(Map<String, dynamic> data) async {
    await _guard(() => _dio.post(ApiConstants.productos, data: data));
  }

  static Future<void> updateProducto(int id, Map<String, dynamic> data) async {
    await _guard(() => _dio.put(ApiConstants.productoById(id), data: data));
  }

  static Future<void> deleteProducto(int id) async {
    await _guard(() => _dio.delete(ApiConstants.productoById(id)));
  }

  // ───────── PEDIDOS ─────────
  static Future<List<dynamic>> getPedidos({String estado = ''}) async {
    final path = estado.isNotEmpty
        ? '${ApiConstants.pedidos}?estado=$estado'
        : ApiConstants.pedidos;
    return _guard(() async {
      final res = await _dio.get(path);
      return res.data['pedidos'] ?? <dynamic>[];
    });
  }

  static Future<Map<String, dynamic>> createPedido(Map<String, dynamic> data) async {
    return _guard(() async {
      final res = await _dio.post(ApiConstants.pedidos, data: data);
      return Map<String, dynamic>.from(res.data as Map);
    });
  }

  static Future<void> cambiarEstadoPedido(int id, String estado) async {
    await _guard(() => _dio.put(ApiConstants.pedidoEstado(id), data: {'estado': estado}));
  }

  static Future<void> cancelarPedido(int id) async {
    await _guard(() => _dio.patch(ApiConstants.pedidoCancelar(id)));
  }

  static Future<void> agregarProductos(int id, Map<String, dynamic> data) async {
    await _guard(() => _dio.patch(ApiConstants.pedidoAgregar(id), data: data));
  }

  static Future<void> editarPedido(int id, Map<String, dynamic> data) async {
    await _guard(() => _dio.patch(ApiConstants.pedidoEditar(id), data: data));
  }

  static Future<void> deletePedido(int id) async {
    await _guard(() => _dio.delete(ApiConstants.pedidoById(id)));
  }

  // ───────── USUARIOS ─────────
  static Future<List<dynamic>> getUsuarios() async {
    return _guard(() async {
      final res = await _dio.get(ApiConstants.usuarios);
      return res.data['usuarios'] ?? <dynamic>[];
    });
  }

  static Future<void> createUsuario(Map<String, dynamic> data) async {
    await _guard(() => _dio.post(ApiConstants.register, data: data));
  }

  static Future<void> updateUsuario(int id, Map<String, dynamic> data) async {
    await _guard(() => _dio.put(ApiConstants.userById(id), data: data));
  }

  static Future<void> deleteUsuario(int id) async {
    await _guard(() => _dio.delete(ApiConstants.userById(id)));
  }

  // ───────── MÉTRICAS ─────────
  static Future<Map<String, dynamic>> getMetricas() async {
    return _guard(() async {
      final res = await _dio.get(ApiConstants.metricas);
      return Map<String, dynamic>.from(res.data as Map);
    });
  }
}
