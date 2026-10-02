import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plataforma.dart';
import '../../core/tema.dart';
import '../auth/auth_controller.dart';
import '../auth/sesion.dart';
import 'central_local.dart';
import 'red_propia.dart';

/// Pantalla de Ajustes donde se arregla el fallo, si lo arregla el usuario.
String? ajustesParaRed(String? codigo) => switch (codigo) {
      'UBICACION' => 'ubicacion',
      'PERMISO' => 'app',
      _ => null,
    };

/// Franja fija debajo de todas las pantallas cuando se trabaja sin router y la red
/// propia de la central no está: en la central, que la red se cayó o que cambió y hay
/// que volver a escanear el QR; en el mesero, que se perdió la red de la central.
class AvisoRed extends ConsumerWidget {
  const AvisoRed({super.key, required this.child, required this.alAbrirConexion});

  final Widget child;

  /// Lleva a la pantalla de conexión, donde se escanea el QR.
  final VoidCallback alAbrirConexion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conexion = ref.watch(conexionProvider);
    final Widget aviso;
    if (ref.watch(centralLocalProvider) != null) {
      aviso = _deCentral(ref, ref.watch(redPropiaProvider));
    } else if (conexion?.modo == ModoConexion.enlazada && conexion?.red != null) {
      aviso = _deMesero(ref, ref.watch(redMeseroProvider));
    } else {
      aviso = const SizedBox.shrink();
    }
    // Siempre la misma estructura: si cambiara al aparecer el aviso, las pantallas perderían su estado.
    return Column(children: [Expanded(child: child), aviso]);
  }

  Widget _deCentral(WidgetRef ref, EstadoRedPropia red) {
    final notifier = ref.read(redPropiaProvider.notifier);
    if (red.fase == FaseRedPropia.caida) {
      final ajustes = ajustesParaRed(red.codigo);
      return _Franja(
        color: Colores.peligro,
        icono: Icons.wifi_off,
        titulo: 'La red Wi-Fi de esta central está apagada: los meseros no pueden enviar pedidos.',
        detalle: [
          ?red.error,
          if (red.reintentando) 'Se está volviendo a crear…',
        ].join(' '),
        acciones: [
          if (ajustes != null) ('Abrir ajustes', () => unawaited(Plataforma.abrirAjustes(ajustes))),
          if (!red.reintentando) ('Reintentar', () => unawaited(notifier.encender())),
        ],
      );
    }
    if (red.fase == FaseRedPropia.activa && red.qrNuevo) {
      return _Franja(
        color: Colores.aviso,
        icono: Icons.qr_code_2,
        titulo: 'La red Wi-Fi de la central es nueva: cambió de nombre y contraseña.',
        detalle: 'Cada mesero debe volver a escanear el QR (Gestión → Central de cocina). '
            'Sus pedidos pendientes no se pierden.',
        acciones: [('Entendido', () => unawaited(notifier.qrAvisado()))],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _deMesero(WidgetRef ref, EstadoRedMesero red) {
    return switch (red.fase) {
      FaseRedMesero.perdida => _Franja(
          color: Colores.peligro,
          icono: Icons.wifi_off,
          titulo: 'Sin la red Wi-Fi de la central.',
          detalle: red.error ?? 'Vuelve a escanear el QR de la central.',
          acciones: [
            ('Reintentar', () => unawaited(ref.read(redMeseroProvider.notifier).reintentar())),
            ('Escanear QR', alAbrirConexion),
          ],
        ),
      FaseRedMesero.reintentando => const _Franja(
          color: Colores.aviso,
          icono: Icons.wifi_find,
          titulo: 'Se perdió la red Wi-Fi de la central. Reconectando…',
          detalle: 'Los pedidos se guardan y se envían al volver.',
          acciones: [],
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _Franja extends StatelessWidget {
  const _Franja({
    required this.color,
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.acciones,
  });

  final Color color;
  final IconData icono;
  final String titulo;
  final String detalle;
  final List<(String, VoidCallback)> acciones;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icono, color: Colors.black, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                  if (detalle.isNotEmpty)
                    Text(detalle, style: const TextStyle(color: Colors.black, fontSize: 13)),
                  if (acciones.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (texto, accion) in acciones)
                          TextButton(
                            onPressed: accion,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.black,
                              textStyle: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                            ),
                            child: Text(texto),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
