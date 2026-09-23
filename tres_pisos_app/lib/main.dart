import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'features/auth/almacen_sesion.dart';
import 'features/auth/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');

  // Se lee la sesión guardada antes de pintar para abrir directo en la pantalla del rol.
  final almacen = AlmacenSesion(await SharedPreferences.getInstance());
  final arranque = almacen.cargar();

  runApp(ProviderScope(
    overrides: [
      almacenSesionProvider.overrideWithValue(almacen),
      datosArranqueProvider.overrideWithValue(arranque),
    ],
    child: const TresPisosApp(),
  ));
}
