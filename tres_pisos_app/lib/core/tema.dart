import 'package:flutter/material.dart';

import '../features/pedidos/modelos.dart';

/// Paleta tomada de la web (restaurante-app/css/estilos.css).
abstract final class Colores {
  static const fondo = Color(0xFF070401);
  static const superficie = Color(0xFF0D0803);
  static const tarjeta = Color(0xFF110E07);
  static const acento = Color(0xFFFF9500);
  static const dorado = Color(0xFFFFC84A);
  static const crema = Color(0xFFF5EAD8);
  static const apagado = Color(0xFF8A7060);
  static const exito = Color(0xFF4ADE80);
  static const aviso = Color(0xFFFACC15);
  static const peligro = Color(0xFFF87171);
  static const azul = Color(0xFF60A5FA);

  static Color deEstado(EstadoPedido estado) => switch (estado) {
        EstadoPedido.pendiente => aviso,
        EstadoPedido.preparando => azul,
        EstadoPedido.listo => exito,
        EstadoPedido.pagado => apagado,
        EstadoPedido.cancelado => peligro,
      };
}

ThemeData crearTema() {
  final esquema = ColorScheme.fromSeed(
    seedColor: Colores.acento,
    brightness: Brightness.dark,
  ).copyWith(
    primary: Colores.acento,
    onPrimary: Colores.fondo,
    secondary: Colores.dorado,
    onSecondary: Colores.fondo,
    surface: Colores.superficie,
    onSurface: Colores.crema,
    surfaceContainerLowest: Colores.fondo,
    surfaceContainer: Colores.tarjeta,
    error: Colores.peligro,
  );

  return ThemeData(
    colorScheme: esquema,
    scaffoldBackgroundColor: Colores.fondo,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colores.fondo,
      foregroundColor: Colores.crema,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colores.tarjeta,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colores.acento.withValues(alpha: 0.12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colores.tarjeta,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
