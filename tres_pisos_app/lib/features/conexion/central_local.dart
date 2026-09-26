import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../central/central.dart';
import '../../central/respaldo.dart';
import '../../central/servidor_central.dart';
import '../../core/plataforma.dart';
import '../auth/auth_controller.dart';
import '../auth/sesion.dart';

/// Central que corre dentro de esta misma app (solo en la tablet de cocina).
class CentralLocal {
  CentralLocal(this.central, this.servidor);

  final Central central;
  final ServidorCentral servidor;

  String get urlLocal => 'http://127.0.0.1:${servidor.puertoEnUso}';

  Conexion get conexion => Conexion(modo: ModoConexion.central, url: urlLocal, enlace: central.codigoEnlace);

  /// Abre los datos guardados y empieza a atender en la red local.
  static Future<CentralLocal> arrancar() async {
    final carpeta = Directory('${await Plataforma.carpetaDatos()}${Platform.pathSeparator}central');
    await carpeta.create(recursive: true);
    final central = await Central.abrir(carpeta);
    final servidor = ServidorCentral(central);
    await servidor.iniciar();
    await Plataforma.pantallaEncendida(true);
    return CentralLocal(central, servidor);
  }
}

/// Se sobreescribe en `main()` si esta tablet ya era la central.
final centralArranqueProvider = Provider<CentralLocal?>((ref) => null);

final centralLocalProvider = NotifierProvider<CentralLocalController, CentralLocal?>(CentralLocalController.new);

class CentralLocalController extends Notifier<CentralLocal?> {
  @override
  CentralLocal? build() => ref.read(centralArranqueProvider);

  /// Convierte esta tablet en la central: crea el administrador, carga el menú
  /// del restaurante y deja la sesión del administrador iniciada.
  Future<void> crear({required String admin, required String password, String? nombreRestaurante}) async {
    final local = state ?? await CentralLocal.arrancar();
    state = local;
    if (!local.central.inicializada) {
      final menu = jsonDecode(await rootBundle.loadString('assets/menu/restaurante.json')) as Map<String, dynamic>;
      await local.central.inicializar(
        admin: admin,
        password: password,
        nombreRestaurante: nombreRestaurante,
        menu: (menu['productos'] as List).cast<Map<String, dynamic>>(),
      );
    }
    await ref.read(conexionProvider.notifier).usar(local.conexion);
    await ref.read(authControllerProvider.notifier).iniciarSesion(usuario: admin, password: password);
  }

  /// Deja de atender en la red (la tablet pasa a otro modo). Los datos se conservan.
  Future<void> detener() async {
    final local = state;
    if (local == null) return;
    state = null;
    await local.servidor.detener();
    await local.central.cerrar();
    await Plataforma.pantallaEncendida(false);
  }

  /// Nuevo código de enlace: las demás tablets deben volver a enlazarse y todas las sesiones se cierran.
  Future<String> renovarEnlace() async {
    final local = state ?? (throw StateError('Esta tablet no es la central'));
    final codigo = await local.central.renovarEnlace();
    await ref.read(conexionProvider.notifier).actualizarEnlace(codigo);
    return codigo;
  }

  /// Archivo `.3pisos` cifrado con [password] con todo lo que guarda la central.
  Future<Uint8List> generarRespaldo(String password) async {
    final local = state ?? (throw StateError('Esta tablet no es la central'));
    final registros = await local.central.exportar();
    final restaurante = local.central.nombre;
    // PBKDF2 tarda un par de segundos: fuera del hilo de la interfaz.
    return Isolate.run(() => cifrarRespaldo(registros, password, restaurante: restaurante));
  }

  /// Convierte esta tablet (sin datos) en la central restaurando un respaldo.
  /// Después hay que iniciar sesión con los usuarios del respaldo.
  Future<void> restaurar(Uint8List archivo, String password) async {
    final registros = await Isolate.run(() => descifrarRespaldo(archivo, password));
    final local = state ?? await CentralLocal.arrancar();
    state = local;
    await local.central.restaurar(registros);
    await ref.read(conexionProvider.notifier).usar(local.conexion);
  }
}

/// Fecha del último respaldo guardado desde esta tablet (para recordar hacerlo).
final ultimoRespaldoProvider = NotifierProvider<UltimoRespaldo, DateTime?>(UltimoRespaldo.new);

class UltimoRespaldo extends Notifier<DateTime?> {
  static const _clave = 'ultimo_respaldo';

  @override
  DateTime? build() => DateTime.tryParse(ref.read(almacenSesionProvider).prefs.getString(_clave) ?? '');

  Future<void> marcar() async {
    final ahora = DateTime.now();
    state = ahora;
    await ref.read(almacenSesionProvider).prefs.setString(_clave, ahora.toIso8601String());
  }
}
