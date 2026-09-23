import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'features/auth/almacen_sesion.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/sesion.dart';
import 'features/conexion/central_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');

  // Se lee la sesión guardada antes de pintar para abrir directo en la pantalla del rol.
  final almacen = AlmacenSesion(await SharedPreferences.getInstance());
  var arranque = almacen.cargar();

  // En la tablet de cocina la central arranca con la app: las demás dependen de ella.
  CentralLocal? central;
  if (arranque.conexion?.modo == ModoConexion.central) {
    try {
      central = await CentralLocal.arrancar();
      // El puerto o el código de enlace pueden haber cambiado desde la última vez.
      final conexion = central.conexion;
      await almacen.guardarConexion(conexion);
      final sesion = arranque.sesion;
      arranque = DatosArranque(
        conexion: conexion,
        sesion: sesion == null ? null : Sesion(conexion: conexion, token: sesion.token, usuario: sesion.usuario),
      );
    } on Object catch (e) {
      debugPrint('No se pudo arrancar la central: $e');
    }
  }

  runApp(ProviderScope(
    overrides: [
      almacenSesionProvider.overrideWithValue(almacen),
      datosArranqueProvider.overrideWithValue(arranque),
      centralArranqueProvider.overrideWithValue(central),
    ],
    child: const TresPisosApp(),
  ));
}
