import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
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

/// Punto verde/rojo en la barra superior según el estado del Socket.IO.
class IndicadorConexion extends ConsumerWidget {
  const IndicadorConexion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conectado = ref.watch(conexionProvider).value ?? false;
    return Tooltip(
      message: conectado ? 'Conectado en tiempo real' : 'Sin conexión en tiempo real',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.circle, size: 12, color: conectado ? Colores.exito : Colores.peligro),
      ),
    );
  }
}

/// Menú con el usuario actual y la opción de cerrar sesión.
class MenuUsuario extends ConsumerWidget {
  const MenuUsuario({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuario = ref.watch(authControllerProvider)?.usuario;
    return PopupMenuButton<void>(
      icon: const Icon(Icons.account_circle_outlined),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: Text('${usuario?.username ?? ''} · ${usuario?.rol.etiqueta ?? ''}'),
        ),
        PopupMenuItem<void>(
          onTap: () => ref.read(authControllerProvider.notifier).cerrarSesion(),
          child: const Row(
            children: [Icon(Icons.logout), SizedBox(width: 12), Text('Cerrar sesión')],
          ),
        ),
      ],
    );
  }
}
