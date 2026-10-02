import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  test('AlmacenSesion restaura una sesión vigente y al cerrarla recuerda la conexión', () async {
    final token = jwtCon({'id': 1, 'exp': segundos(DateTime.now().toUtc().add(const Duration(hours: 8)))});
    SharedPreferences.setMockInitialValues({});
    final almacen = AlmacenSesion(await SharedPreferences.getInstance());

    expect(almacen.cargar().sesion, isNull);
    expect(almacen.cargar().conexion, isNull, reason: 'la primera vez hay que elegir la conexión');

    const conexion = Conexion(modo: ModoConexion.enlazada, url: 'http://192.168.1.20:8787', enlace: 'K7P2-9QXM');
    await almacen.guardar(Sesion(
      conexion: conexion,
      token: token,
      usuario: const Usuario(id: 1, username: 'luis', rol: Rol.mesero),
    ));
    final restaurada = almacen.cargar().sesion;
    expect(restaurada?.usuario.username, 'luis');
    expect(restaurada?.usuario.rol, Rol.mesero);
    expect(restaurada?.conexion.enlace, 'K7P2-9QXM');

    await almacen.borrarSesion();
    final trasCerrar = almacen.cargar();
    expect(trasCerrar.sesion, isNull);
    expect(trasCerrar.conexion?.modo, ModoConexion.enlazada);
    expect(trasCerrar.conexion?.url, 'http://192.168.1.20:8787');
  });

  test('una conexión al antiguo servidor web obliga a configurar de nuevo', () async {
    final token = jwtCon({'id': 1, 'exp': segundos(DateTime.now().toUtc().add(const Duration(hours: 8)))});
    SharedPreferences.setMockInitialValues({
      'conexion': '{"modo":"servidor","url":"https://tres-pisos.up.railway.app"}',
      'token': token,
      'usuario': '{"id":1,"username":"luis","role":"mesero"}',
    });
    final arranque = AlmacenSesion(await SharedPreferences.getInstance()).cargar();
    expect(arranque.conexion, isNull);
    expect(arranque.sesion, isNull);
  });

  test('AlmacenSesion descarta un token caducado', () async {
    final caducado = jwtCon({'id': 1, 'exp': segundos(DateTime.now().toUtc().subtract(const Duration(hours: 1)))});
    SharedPreferences.setMockInitialValues({
      'conexion': '{"modo":"enlazada","url":"http://192.168.1.20:8787","enlace":"K7P2-9QXM"}',
      'token': caducado,
      'usuario': '{"id":1,"username":"luis","role":"mesero"}',
    });
    final almacen = AlmacenSesion(await SharedPreferences.getInstance());
    expect(almacen.cargar().sesion, isNull);
  });

  group('reloj de la tablet distinto al de la central', () {
    const conexion = Conexion(modo: ModoConexion.enlazada, url: 'http://192.168.1.20:8787', enlace: 'K7P2-9QXM');
    const usuario = Usuario(id: 1, username: 'luis', rol: Rol.mesero);
    // La central firmó el token a las 12:00 de SU reloj, con 12 h de vigencia.
    final token = jwtCon({
      'id': 1,
      'iat': segundos(ahora),
      'exp': segundos(ahora.add(const Duration(hours: 12))),
    });

    for (final (caso, adelanto) in [
      ('atrasada 2 días', const Duration(days: -2)),
      ('adelantada 5 horas', const Duration(hours: 5)),
      ('adelantada 2 días', const Duration(days: 2)),
      ('en hora', Duration.zero),
    ]) {
      test('tablet $caso: la sesión dura y se renueva igual', () {
        // Lo que marca el reloj de la tablet cuando recibe el token.
        final tablet = ahora.add(adelanto);
        final desfase = desfaseConCentral(token, ahora: tablet);
        expect(desfase, -adelanto);
        final sesion = Sesion(conexion: conexion, token: token, usuario: usuario, desfase: desfase);

        expect(sesion.horaCentral(ahora: tablet), ahora);
        expect(sesion.vigente(ahora: tablet), isTrue);
        expect(sesion.debeRenovar(ahora: tablet), isFalse);
        expect(sesion.hastaRenovar(ahora: tablet), const Duration(hours: 6));

        expect(sesion.debeRenovar(ahora: tablet.add(const Duration(hours: 5, minutes: 59))), isFalse);
        expect(sesion.debeRenovar(ahora: tablet.add(const Duration(hours: 6))), isTrue);
        expect(sesion.hastaRenovar(ahora: tablet.add(const Duration(hours: 8))), Duration.zero);

        expect(sesion.vigente(ahora: tablet.add(const Duration(hours: 11))), isTrue);
        expect(sesion.vigente(ahora: tablet.add(const Duration(hours: 12))), isFalse);
      });
    }

    test('sin desfase conocido (sesión de una versión anterior) se pide renovar enseguida', () {
      final sesion = Sesion(conexion: conexion, token: token, usuario: usuario, desfase: null);
      expect(sesion.debeRenovar(ahora: ahora), isTrue);
      expect(sesion.hastaRenovar(ahora: ahora), Duration.zero);
      // Un token sin fechas no se puede renovar a ciegas: no hay ciclo.
      final sinFechas = Sesion(conexion: conexion, token: jwtCon({'id': 1}), usuario: usuario, desfase: null);
      expect(sinFechas.debeRenovar(ahora: ahora), isFalse);
      expect(sinFechas.hastaRenovar(ahora: ahora), isNull);
      expect(desfaseConCentral(jwtCon({'id': 1}), ahora: ahora), isNull);
      expect(desfaseConCentral('no-es-un-jwt', ahora: ahora), isNull);
    });

    test('AlmacenSesion restaura con el desfase guardado aunque el reloj de la tablet diga que caducó', () async {
      // La central va 3 días por detrás de la tablet: para el reloj de la tablet el token caducó hace días.
      const desfase = Duration(days: -3);
      final central = DateTime.now().toUtc().add(desfase);
      final emitido = jwtCon({
        'id': 1,
        'iat': segundos(central.subtract(const Duration(hours: 1))),
        'exp': segundos(central.add(const Duration(hours: 11))),
      });
      SharedPreferences.setMockInitialValues({});
      final almacen = AlmacenSesion(await SharedPreferences.getInstance());
      await almacen.guardar(Sesion(conexion: conexion, token: emitido, usuario: usuario, desfase: desfase));

      final restaurada = almacen.cargar().sesion;
      expect(restaurada?.token, emitido);
      expect(restaurada?.desfase, desfase);
      expect(restaurada?.debeRenovar(), isFalse);

      await almacen.borrarSesion();
      expect(almacen.prefs.getKeys(), {'conexion'}, reason: 'el desfase se borra con la sesión');
    });

    test('AlmacenSesion descarta un token que caducó para la central aunque la tablet vaya atrasada', () async {
      // La tablet va 3 días atrasada: su reloj cree que al token le quedan días.
      const desfase = Duration(days: 3);
      final central = DateTime.now().toUtc().add(desfase);
      final caducado = jwtCon({
        'id': 1,
        'iat': segundos(central.subtract(const Duration(hours: 13))),
        'exp': segundos(central.subtract(const Duration(hours: 1))),
      });
      SharedPreferences.setMockInitialValues({});
      final almacen = AlmacenSesion(await SharedPreferences.getInstance());
      await almacen.guardar(Sesion(conexion: conexion, token: caducado, usuario: usuario, desfase: desfase));
      expect(almacen.cargar().sesion, isNull);
      expect(almacen.cargar().conexion?.url, conexion.url);
    });

    test('una sesión guardada con el formato anterior no revienta', () async {
      final vigente = jwtCon({'id': 1, 'exp': segundos(DateTime.now().toUtc().add(const Duration(hours: 8)))});
      final base = {
        'conexion': '{"modo":"enlazada","url":"http://192.168.1.20:8787","enlace":"K7P2-9QXM"}',
        'token': vigente,
        'usuario': '{"id":1,"username":"luis","role":"mesero"}',
      };
      SharedPreferences.setMockInitialValues(base);
      final restaurada = AlmacenSesion(await SharedPreferences.getInstance()).cargar().sesion;
      expect(restaurada?.usuario.username, 'luis');
      expect(restaurada?.desfase, isNull);

      // Un desfase guardado con un tipo inesperado se ignora.
      SharedPreferences.setMockInitialValues({...base, 'desfase_central': 'tres'});
      final rara = AlmacenSesion(await SharedPreferences.getInstance()).cargar().sesion;
      expect(rara?.usuario.username, 'luis');
      expect(rara?.desfase, isNull);
    });
  });

  test('Usuario.fromJson con el formato de /api/auth/login', () {
    final usuario = Usuario.fromJson({'id': 3, 'username': 'ana', 'role': 'cocina', 'created_at': null});
    expect(usuario.rol, Rol.cocina);
    expect(usuario.rol.tomaPedidos, isFalse);
    expect(Usuario.fromJson(usuario.toJson()).username, 'ana');
    expect(() => Usuario.fromJson({'id': 1, 'username': 'x', 'role': 'cajero'}), throwsFormatException);
  });
}
