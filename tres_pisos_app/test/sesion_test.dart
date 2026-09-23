import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tres_pisos_app/core/config.dart';
import 'package:tres_pisos_app/features/auth/almacen_sesion.dart';
import 'package:tres_pisos_app/features/auth/sesion.dart';

String jwtCon(Map<String, dynamic> payload) {
  String parte(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${parte({'alg': 'HS256', 'typ': 'JWT'})}.${parte(payload)}.firma';
}

void main() {
  final ahora = DateTime.utc(2026, 9, 22, 12);
  int segundos(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

  test('token vigente y caducado', () {
    final vigente = jwtCon({'id': 1, 'exp': segundos(ahora.add(const Duration(hours: 8)))});
    final caducado = jwtCon({'id': 1, 'exp': segundos(ahora.subtract(const Duration(minutes: 5)))});
    final porCaducar = jwtCon({'id': 1, 'exp': segundos(ahora.add(const Duration(seconds: 30)))});

    expect(tokenVigente(vigente, ahora: ahora), isTrue);
    expect(tokenVigente(caducado, ahora: ahora), isFalse);
    expect(tokenVigente(porCaducar, ahora: ahora), isFalse);
  });

  test('un token mal formado no se considera vigente', () {
    expect(tokenVigente('no-es-un-jwt', ahora: ahora), isFalse);
    expect(tokenVigente('a.%%%.c', ahora: ahora), isFalse);
  });

  test('AlmacenSesion restaura una sesión vigente y al cerrarla recuerda el servidor', () async {
    final token = jwtCon({'id': 1, 'exp': segundos(DateTime.now().toUtc().add(const Duration(hours: 8)))});
    SharedPreferences.setMockInitialValues({});
    final almacen = AlmacenSesion(await SharedPreferences.getInstance());

    expect(almacen.cargar().sesion, isNull);
    expect(almacen.cargar().servidor, servidorPorDefecto);

    await almacen.guardar(Sesion(
      servidor: 'http://192.168.1.50:3000',
      token: token,
      usuario: const Usuario(id: 1, username: 'luis', rol: Rol.mesero),
    ));
    final restaurada = almacen.cargar().sesion;
    expect(restaurada?.usuario.username, 'luis');
    expect(restaurada?.usuario.rol, Rol.mesero);

    await almacen.borrarSesion();
    final trasCerrar = almacen.cargar();
    expect(trasCerrar.sesion, isNull);
    expect(trasCerrar.servidor, 'http://192.168.1.50:3000');
  });

  test('AlmacenSesion descarta un token caducado', () async {
    final caducado = jwtCon({'id': 1, 'exp': segundos(DateTime.now().toUtc().subtract(const Duration(hours: 1)))});
    SharedPreferences.setMockInitialValues({
      'token': caducado,
      'usuario': '{"id":1,"username":"luis","role":"mesero"}',
    });
    final almacen = AlmacenSesion(await SharedPreferences.getInstance());
    expect(almacen.cargar().sesion, isNull);
  });

  test('Usuario.fromJson con el formato de /api/auth/login', () {
    final usuario = Usuario.fromJson({'id': 3, 'username': 'ana', 'role': 'cocina', 'created_at': null});
    expect(usuario.rol, Rol.cocina);
    expect(usuario.rol.tomaPedidos, isFalse);
    expect(Usuario.fromJson(usuario.toJson()).username, 'ana');
    expect(() => Usuario.fromJson({'id': 1, 'username': 'x', 'role': 'cajero'}), throwsFormatException);
  });
}
