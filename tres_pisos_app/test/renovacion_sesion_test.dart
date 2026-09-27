import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tres_pisos_app/central/central.dart';
import 'package:tres_pisos_app/central/servidor_central.dart';
import 'package:tres_pisos_app/features/auth/almacen_sesion.dart';
import 'package:tres_pisos_app/features/auth/auth_controller.dart';
import 'package:tres_pisos_app/features/auth/sesion.dart';
import 'package:tres_pisos_app/features/pedidos/tiempo_real.dart';

String jwtCon(Map<String, dynamic> payload) {
  String parte(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${parte({'alg': 'HS256', 'typ': 'JWT'})}.${parte(payload)}.firma';
}

/// La tablet renueva su token a mitad de la vigencia y cierra la sesión si la
/// central ya no la acepta, contra una central real en localhost.
void main() {
  int segundos(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

  test('se renueva al pasar la mitad de la vigencia', () {
    final emitido = DateTime.utc(2026, 9, 26, 8);
    final token = jwtCon({'iat': segundos(emitido), 'exp': segundos(emitido.add(const Duration(hours: 12)))});
    expect(mitadVigenciaToken(token), DateTime.utc(2026, 9, 26, 14));
    expect(debeRenovarToken(token, ahora: DateTime.utc(2026, 9, 26, 13, 59)), isFalse);
    expect(debeRenovarToken(token, ahora: DateTime.utc(2026, 9, 26, 14)), isTrue);
    // Sin fechas (o mal formado) no se intenta renovar.
    expect(debeRenovarToken(jwtCon({'id': 1}), ahora: emitido), isFalse);
    expect(debeRenovarToken('no-es-un-jwt'), isFalse);
  });

  group('con una central real', () {
    late Directory carpeta;
    late Central central;
    late ServidorCentral servidor;
    late Conexion conexion;
    var ahora = DateTime.now();

    setUp(() async {
      ahora = DateTime.now();
      carpeta = await Directory.systemTemp.createTemp('renovacion');
      central = await Central.abrir(carpeta, iteraciones: 1000, reloj: () => ahora);
      await central.inicializar(admin: 'admin', password: 'secreto1');
      await central.crearUsuario({'username': 'luis', 'password': 'clave123', 'role': 'mesero'});
      servidor = ServidorCentral(central, puerto: 0, anunciar: false);
      await servidor.iniciar();
      conexion = Conexion(
        modo: ModoConexion.enlazada,
        url: 'http://127.0.0.1:${servidor.puertoEnUso}',
        enlace: central.codigoEnlace,
      );
    });

    tearDown(() async {
      await servidor.detener();
      await central.cerrar();
      await carpeta.delete(recursive: true);
    });

    /// Sesión de luis iniciada hace [hace].
    Future<Sesion> sesionDeHace(Duration hace) async {
      final real = ahora;
      ahora = real.subtract(hace);
      final login = await central.login('luis', 'clave123');
      ahora = real;
      return Sesion(
        conexion: conexion,
        token: login['token'] as String,
        usuario: Usuario.fromJson(login['user'] as Map<String, dynamic>),
      );
    }

    Future<(ProviderContainer, AlmacenSesion)> app(Sesion sesion) async {
      SharedPreferences.setMockInitialValues({});
      final almacen = AlmacenSesion(await SharedPreferences.getInstance());
      await almacen.guardar(sesion);
      final contenedor = ProviderContainer(overrides: [
        almacenSesionProvider.overrideWithValue(almacen),
        datosArranqueProvider.overrideWithValue(DatosArranque(conexion: conexion, sesion: sesion)),
      ]);
      addTearDown(contenedor.dispose);
      return (contenedor, almacen);
    }

    Future<void> esperar(bool Function() condicion) async {
      for (var i = 0; i < 100 && !condicion(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    test('un token a mitad de vigencia se renueva solo y se guarda', () async {
      final sesion = await sesionDeHace(const Duration(hours: 7));
      final (contenedor, almacen) = await app(sesion);
      contenedor.listen(authControllerProvider, (_, _) {});
      final cliente = contenedor.read(apiClientProvider);

      await esperar(() => contenedor.read(authControllerProvider)?.token != sesion.token);
      final nueva = contenedor.read(authControllerProvider)!;
      expect(nueva.token, isNot(sesion.token));
      expect(debeRenovarToken(nueva.token), isFalse);
      expect(almacen.cargar().sesion?.token, nueva.token);
      expect(identical(contenedor.read(apiClientProvider), cliente), isTrue,
          reason: 'renovar no reconstruye el cliente HTTP');

      // 13 h después del login original sigue dentro: el cliente usa el token nuevo.
      ahora = ahora.add(const Duration(hours: 6));
      expect(central.autenticar(sesion.token), isNull);
      final yo = await cliente.get('/api/auth/me');
      expect((yo['user'] as Map)['username'], 'luis');
    });

    test('un token reciente no se renueva', () async {
      final sesion = await sesionDeHace(const Duration(hours: 1));
      final (contenedor, _) = await app(sesion);
      contenedor.listen(authControllerProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(contenedor.read(authControllerProvider)?.token, sesion.token);
    });

    test('si la central ya no acepta la sesión al renovar, se cierra', () async {
      final sesion = await sesionDeHace(const Duration(hours: 7));
      await central.actualizarUsuario(sesion.usuario.id, {'username': 'luis', 'role': 'mesero', 'password': 'otra123'});
      final (contenedor, almacen) = await app(sesion);
      contenedor.listen(authControllerProvider, (_, _) {});

      await esperar(() => contenedor.read(authControllerProvider) == null);
      expect(contenedor.read(authControllerProvider), isNull);
      expect(almacen.cargar().sesion, isNull);
    });

    test('el tiempo real cierra sesión si la central revoca el token (y no reintenta sin fin)', () async {
      final sesion = await sesionDeHace(Duration.zero);
      final invalida = Completer<void>();
      final conectado = Completer<void>();
      final tiempoReal = TiempoRealCentral(
        conexion.url,
        token: () => sesion.token,
        enlace: central.codigoEnlace,
        alSesionInvalida: invalida.complete,
      );
      addTearDown(tiempoReal.cerrar);
      tiempoReal.eventos.listen((e) {
        if (e is Conectado && !conectado.isCompleted) conectado.complete();
      });
      await conectado.future.timeout(const Duration(seconds: 5));
      await esperar(() => servidor.clientesConectados == 1);
      expect(servidor.clientesConectados, 1);

      // Cambiar la contraseña cierra el socket; al reconectar con el token viejo la central responde 401.
      await central.actualizarUsuario(sesion.usuario.id, {'username': 'luis', 'role': 'mesero', 'password': 'otra123'});
      await invalida.future.timeout(const Duration(seconds: 5));
      expect(tiempoReal.estaConectado, isFalse);
    });

    test('el tiempo real reconecta con el token renovado cuando la central cierra el viejo', () async {
      var token = (await sesionDeHace(Duration.zero)).token;
      var conexiones = 0;
      var invalida = false;
      final tiempoReal = TiempoRealCentral(
        conexion.url,
        token: () => token,
        enlace: central.codigoEnlace,
        alSesionInvalida: () => invalida = true,
      );
      addTearDown(tiempoReal.cerrar);
      tiempoReal.eventos.listen((e) {
        if (e is Conectado) conexiones++;
      });
      await esperar(() => conexiones == 1 && servidor.clientesConectados == 1);

      // Se renovó a mitad de turno; horas después el token viejo caduca y la central lo cierra.
      ahora = ahora.add(const Duration(hours: 7));
      token = central.renovarSesion(central.autenticar(token)!)['token'] as String;
      ahora = ahora.add(const Duration(hours: 6));
      servidor.revisarSesiones();

      await esperar(() => conexiones == 2 && servidor.clientesConectados == 1);
      expect(conexiones, 2);
      expect(invalida, isFalse);
      expect(servidor.clientesConectados, 1);
    });
  });
}
