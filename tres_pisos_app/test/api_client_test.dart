import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/core/api_client.dart';
import 'package:tres_pisos_app/core/config.dart';

/// Responde siempre con el mismo estado y cuerpo JSON, sin red.
class AdaptadorFijo implements HttpClientAdapter {
  AdaptadorFijo(this.status, this.cuerpo);

  final int status;
  final Object cuerpo;
  RequestOptions? ultima;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    ultima = options;
    return ResponseBody.fromString(
      jsonEncode(cuerpo),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient cliente(AdaptadorFijo adaptador, {void Function()? alNoAutorizado}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://servidor', headers: {'Authorization': 'Bearer abc'}))
    ..httpClientAdapter = adaptador;
  return ApiClient(servidor: 'http://servidor', dio: dio, alNoAutorizado: alNoAutorizado);
}

void main() {
  test('devuelve el cuerpo en respuestas correctas', () async {
    final adaptador = AdaptadorFijo(200, {'success': true, 'productos': []});
    final datos = await cliente(adaptador).get('/api/productos');
    expect(datos['success'], isTrue);
    expect(adaptador.ultima?.headers['Authorization'], 'Bearer abc');
  });

  test('usa el mensaje de error del backend', () async {
    final api = cliente(AdaptadorFijo(400, {
      'success': false,
      'code': 'INVALID_STATUS',
      'error': 'No se puede modificar un pedido cancelado.',
    }));
    await expectLater(
      api.patch('/api/pedidos/1/agregar', {}),
      throwsA(isA<ApiException>()
          .having((e) => e.mensaje, 'mensaje', 'No se puede modificar un pedido cancelado.')
          .having((e) => e.codigo, 'codigo', 'INVALID_STATUS')),
    );
  });

  test('une los mensajes de validación de express-validator', () async {
    final api = cliente(AdaptadorFijo(400, {
      'success': false,
      'code': 'VALIDATION_ERROR',
      'errors': [
        {'campo': 'mesa', 'mensaje': 'La mesa debe ser un número entero positivo.'},
        {'campo': 'productos', 'mensaje': 'Debe incluir al menos un producto.'},
      ],
    }));
    await expectLater(
      api.post('/api/pedidos', {}),
      throwsA(isA<ApiException>().having(
        (e) => e.mensaje,
        'mensaje',
        'La mesa debe ser un número entero positivo.\nDebe incluir al menos un producto.',
      )),
    );
  });

  test('un 401 avisa para cerrar la sesión', () async {
    var cerrada = false;
    final api = cliente(
      AdaptadorFijo(401, {'success': false, 'code': 'TOKEN_EXPIRED', 'error': 'El token ha expirado.'}),
      alNoAutorizado: () => cerrada = true,
    );
    await expectLater(api.get('/api/pedidos'), throwsA(isA<ApiException>()));
    expect(cerrada, isTrue);
  });

  test('error de conexión con mensaje entendible', () {
    final error = errorDesdeDio(DioException.connectionError(
      requestOptions: RequestOptions(path: '/api/pedidos'),
      reason: 'Connection refused',
    ));
    expect(error.mensaje, contains('No hay conexión con el servidor'));
  });

  test('normalizarServidor', () {
    expect(normalizarServidor(' http://192.168.1.50:3000/ '), 'http://192.168.1.50:3000');
    expect(normalizarServidor('192.168.1.50:3000'), 'http://192.168.1.50:3000');
    expect(normalizarServidor('http://192.168.1.20:8787//'), 'http://192.168.1.20:8787');
  });
}
