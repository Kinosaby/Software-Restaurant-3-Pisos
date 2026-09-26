import 'dart:io';

import 'package:dio/dio.dart';

/// Error de la API con un mensaje listo para mostrar al usuario.
class ApiException implements Exception {
  ApiException(this.mensaje, {this.status, this.codigo, this.sinConexion = false, this.entregaIncierta = false});

  final String mensaje;
  final int? status;
  final String? codigo;

  /// No hubo comunicación con el servidor (Wi-Fi caído, central apagada...).
  final bool sinConexion;

  /// La petición pudo llegar aunque no hubo respuesta (tiempo de espera agotado).
  /// Reintentar pedidos es seguro igualmente: la central reconoce `X-Operacion`.
  final bool entregaIncierta;

  bool get noAutorizado => status == 401;

  @override
  String toString() => mensaje;
}

/// Envoltorio de Dio que habla el formato de la central:
/// éxito `{ success: true, ... }`, error `{ success: false, error }`
/// o, en validaciones, `{ errors: [{ campo, mensaje }] }`.
class ApiClient {
  ApiClient({
    required String servidor,
    String? token,
    String? enlace,
    this._alNoAutorizado,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: servidor,
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                if (token != null) 'Authorization': 'Bearer $token',
                'X-Enlace': ?enlace,
              },
            ));

  final Dio _dio;
  final void Function()? _alNoAutorizado;

  Future<Map<String, dynamic>> get(String ruta, {Map<String, dynamic>? query}) =>
      _enviar(() => _dio.get(ruta, queryParameters: query));

  /// [operacion] identifica el envío para que la central ignore los reintentos repetidos.
  Future<Map<String, dynamic>> post(String ruta, Object? datos, {String? operacion}) =>
      _enviar(() => _dio.post(ruta, data: datos, options: _opciones(operacion)));

  Future<Map<String, dynamic>> put(String ruta, Object? datos) =>
      _enviar(() => _dio.put(ruta, data: datos));

  Future<Map<String, dynamic>> patch(String ruta, [Object? datos, String? operacion]) =>
      _enviar(() => _dio.patch(ruta, data: datos, options: _opciones(operacion)));

  Future<Map<String, dynamic>> delete(String ruta) => _enviar(() => _dio.delete(ruta));

  Options? _opciones(String? operacion) => operacion == null ? null : Options(headers: {'X-Operacion': operacion});

  Future<Map<String, dynamic>> _enviar(Future<Response<dynamic>> Function() peticion) async {
    try {
      final respuesta = await peticion();
      final datos = respuesta.data;
      if (datos is Map<String, dynamic>) return datos;
      throw ApiException('Respuesta inesperada del servidor.');
    } on DioException catch (e) {
      final error = errorDesdeDio(e);
      if (error.noAutorizado) _alNoAutorizado?.call();
      throw error;
    }
  }
}

/// Traduce un fallo de Dio a un [ApiException] con mensaje en español.
ApiException errorDesdeDio(DioException e) {
  final status = e.response?.statusCode;
  final cuerpo = e.response?.data;

  if (cuerpo is Map) {
    final errores = cuerpo['errors'];
    if (errores is List && errores.isNotEmpty) {
      final mensajes = errores
          .whereType<Map>()
          .map((err) => err['mensaje']?.toString())
          .whereType<String>()
          .toSet();
      if (mensajes.isNotEmpty) {
        return ApiException(mensajes.join('\n'), status: status, codigo: 'VALIDATION_ERROR');
      }
    }
    final mensaje = cuerpo['error'];
    if (mensaje is String && mensaje.isNotEmpty) {
      return ApiException(mensaje, status: status, codigo: cuerpo['code']?.toString());
    }
  }

  const sinRed = 'No hay conexión con el servidor. Revisa el Wi-Fi y la dirección.';
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.connectionError:
      return ApiException(sinRed, sinConexion: true);
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return ApiException('El servidor tardó demasiado en responder.',
          status: status, sinConexion: true, entregaIncierta: true);
    default:
      if (e.error is SocketException || e.error is HttpException) {
        return ApiException(sinRed, sinConexion: true, entregaIncierta: true);
      }
      if (status != null) {
        return ApiException('Error del servidor ($status).', status: status);
      }
      return ApiException('No se pudo completar la operación.');
  }
}
