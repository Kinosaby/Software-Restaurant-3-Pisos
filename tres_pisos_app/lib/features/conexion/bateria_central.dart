import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plataforma.dart';
import '../auth/auth_controller.dart';
import 'central_local.dart';

/// En la tablet central pide una sola vez quitar la app del ahorro de batería:
/// con él activo Android puede cortar la red o dormir la app con la pantalla
/// apagada y los meseros se quedarían sin conexión. Explica antes de abrir el
/// diálogo del sistema. En las demás tablets no hace nada.
class AvisoBateriaCentral extends ConsumerStatefulWidget {
  const AvisoBateriaCentral({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AvisoBateriaCentral> createState() => _AvisoBateriaCentralState();
}

class _AvisoBateriaCentralState extends ConsumerState<AvisoBateriaCentral> {
  static const _clave = 'bateria_central_pedida';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisar());
  }

  Future<void> _revisar() async {
    if (ref.read(centralLocalProvider) == null) return;
    final prefs = ref.read(almacenSesionProvider).prefs;
    if (prefs.getBool(_clave) ?? false) return;
    if (await Plataforma.bateriaSinRestriccion()) return;
    if (!mounted) return;
    await prefs.setBool(_clave, true);
    if (!mounted) return;
    final permitir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Mantener la central siempre activa'),
        content: const Text(
          'Esta tablet es la central: las tablets de los meseros envían los pedidos aquí.\n\n'
          'Para que Android no la duerma ni le corte el Wi-Fi cuando la pantalla se apague, '
          'en el siguiente aviso elige "Permitir" para que la app no use el ahorro de batería.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar')),
        ],
      ),
    );
    if (permitir ?? false) await Plataforma.pedirSinRestriccionBateria();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
