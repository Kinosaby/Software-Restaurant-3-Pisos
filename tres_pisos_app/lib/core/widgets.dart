import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/avisos/avisos.dart';
import '../features/pedidos/pedidos_controller.dart';
import '../features/pedidos/tiempo_real.dart';
import 'tema.dart';

void mostrarMensaje(BuildContext context, String mensaje, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(mensaje),
      backgroundColor: error ? Colores.peligro : null,
    ));
}

Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  required String accion,
  bool destructiva = false,
}) async {
  final resultado = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
        FilledButton(
          style: destructiva ? FilledButton.styleFrom(backgroundColor: Colores.peligro) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(accion),
        ),
      ],
    ),
  );
  return resultado ?? false;
}

class Cargando extends StatelessWidget {
  const Cargando({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class ErrorConReintento extends StatelessWidget {
  const ErrorConReintento({super.key, required this.error, required this.alReintentar});

  final Object error;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colores.apagado),
            const SizedBox(height: 12),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: alReintentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class Vacio extends StatelessWidget {
  const Vacio({super.key, required this.icono, required this.mensaje});

  final IconData icono;
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 56, color: Colores.apagado),
          const SizedBox(height: 12),
          Text(mensaje, style: const TextStyle(color: Colores.apagado)),
        ],
      ),
    );
  }
}

/// Punto verde/rojo en la barra superior según la conexión en tiempo real.
class IndicadorConexion extends ConsumerWidget {
  const IndicadorConexion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conectado = ref.watch(conexionTiempoRealProvider).value ?? false;
    return Tooltip(
      message: conectado ? 'Conectado con la central' : 'Sin conexión con la central',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.circle, size: 12, color: conectado ? Colores.exito : Colores.peligro),
      ),
    );
  }
}

/// Franja que avisa cuando se trabaja con datos guardados o hay envíos esperando conexión.
class AvisoSinConexion extends ConsumerWidget {
  const AvisoSinConexion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sinConexion = ref.watch(sinConexionProvider);
    final cola = ref.watch(colaEnviosProvider);
    final pendientes = cola.where((e) => e.error == null).length;
    final rechazados = cola.length - pendientes;
    if (!sinConexion && cola.isEmpty) return const SizedBox.shrink();

    final partes = [
      if (sinConexion) 'Sin conexión: se muestran los datos guardados',
      if (pendientes > 0) '$pendientes por enviar',
      if (rechazados > 0) '$rechazados rechazados',
    ];
    return Material(
      color: (rechazados > 0 ? Colores.peligro : Colores.aviso).withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(sinConexion ? Icons.cloud_off : Icons.cloud_upload_outlined,
                size: 18, color: rechazados > 0 ? Colores.peligro : Colores.aviso),
            const SizedBox(width: 10),
            Expanded(child: Text(partes.join(' · '), style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );
  }
}

/// Menú con el usuario actual, el sonido de los avisos y cerrar sesión.
class MenuUsuario extends ConsumerWidget {
  const MenuUsuario({super.key});

  Future<void> _cerrarSesion(BuildContext context, WidgetRef ref) async {
    final pendientes = ref.read(colaEnviosProvider).length;
    if (pendientes > 0) {
      final ok = await confirmar(
        context,
        titulo: 'Hay $pendientes envíos sin completar',
        mensaje: 'Se quedan guardados en esta tablet y se enviarán cuando alguien vuelva a iniciar sesión en ella.',
        accion: 'Cerrar sesión',
      );
      if (!ok) return;
    }
    await ref.read(authControllerProvider.notifier).cerrarSesion();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuario = ref.watch(authControllerProvider)?.usuario;
    final sonido = ref.watch(sonidoActivoProvider);
    return PopupMenuButton<void>(
      icon: const Icon(Icons.account_circle_outlined),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: Text('${usuario?.username ?? ''} · ${usuario?.rol.etiqueta ?? ''}'),
        ),
        PopupMenuItem<void>(
          onTap: ref.read(sonidoActivoProvider.notifier).alternar,
          child: Row(
            children: [
              Icon(sonido ? Icons.volume_up_outlined : Icons.volume_off_outlined),
              const SizedBox(width: 12),
              Text(sonido ? 'Silenciar avisos' : 'Activar sonido de avisos'),
            ],
          ),
        ),
        PopupMenuItem<void>(
          onTap: () => _cerrarSesion(context, ref),
          child: const Row(
            children: [Icon(Icons.logout), SizedBox(width: 12), Text('Cerrar sesión')],
          ),
        ),
      ],
    );
  }
}
