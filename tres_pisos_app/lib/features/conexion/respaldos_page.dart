import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formato.dart';
import '../../core/plataforma.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import 'central_local.dart';

/// Días sin respaldo a partir de los cuales se avisa en rojo.
const diasAvisoRespaldo = 7;

/// "Hace 3 días" / "Nunca", para el menú de Gestión.
String descripcionUltimoRespaldo(DateTime? ultimo, {DateTime? ahora}) {
  if (ultimo == null) return 'Nunca se ha guardado un respaldo';
  final dias = (ahora ?? DateTime.now()).difference(ultimo).inDays;
  return switch (dias) {
    0 => 'Último respaldo: hoy ${hora(ultimo)}',
    1 => 'Último respaldo: ayer',
    _ => 'Último respaldo: hace $dias días',
  };
}

bool respaldoAtrasado(DateTime? ultimo, {DateTime? ahora}) =>
    ultimo == null || (ahora ?? DateTime.now()).difference(ultimo).inDays >= diasAvisoRespaldo;

/// Pide la contraseña del respaldo (dos veces al crear uno nuevo).
Future<String?> pedirPasswordRespaldo(BuildContext context, {required bool nueva}) {
  final password = TextEditingController();
  final confirmacion = TextEditingController();
  final form = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Contraseña del respaldo'),
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (nueva)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Guárdala en un lugar seguro. Sin ella el respaldo no se puede abrir: no hay forma de recuperarla.',
                  style: TextStyle(color: Colores.apagado),
                ),
              ),
            TextFormField(
              controller: password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Contraseña'),
              validator: (v) => nueva && (v?.length ?? 0) < 8 ? 'Mínimo 8 caracteres' : null,
            ),
            if (nueva) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: confirmacion,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Repite la contraseña'),
                validator: (v) => v != password.text ? 'No coincide' : null,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(context, password.text);
          },
          child: const Text('Continuar'),
        ),
      ],
    ),
  ).whenComplete(() {
    password.dispose();
    confirmacion.dispose();
  });
}

/// Respaldo de la central: un archivo cifrado para guardar fuera de la tablet.
class RespaldosPage extends ConsumerStatefulWidget {
  const RespaldosPage({super.key});

  @override
  ConsumerState<RespaldosPage> createState() => _RespaldosPageState();
}

class _RespaldosPageState extends ConsumerState<RespaldosPage> {
  bool _ocupado = false;

  Future<void> _respaldar({required bool compartir}) async {
    final password = await pedirPasswordRespaldo(context, nueva: true);
    if (password == null || !mounted) return;
    setState(() => _ocupado = true);
    try {
      final Uint8List archivo = await ref.read(centralLocalProvider.notifier).generarRespaldo(password);
      final nombre = 'respaldo-3pisos-${DateFormat('yyyy-MM-dd-HHmm').format(DateTime.now())}.3pisos';
      if (compartir) {
        await Plataforma.compartirArchivo(archivo, nombre: nombre, texto: 'Respaldo del restaurante');
        // No hay forma de saber si el usuario terminó de enviarlo; se marca igual y se le recuerda comprobarlo.
        await ref.read(ultimoRespaldoProvider.notifier).marcar();
        if (mounted) mostrarMensaje(context, 'Comprueba que el archivo llegó a su destino antes de darlo por guardado.');
      } else {
        final guardado = await Plataforma.guardarArchivo(archivo, nombre: nombre);
        if (!guardado) return;
        await ref.read(ultimoRespaldoProvider.notifier).marcar();
        if (mounted) mostrarMensaje(context, 'Respaldo guardado (${(archivo.length / 1024).ceil()} KB)');
      }
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, 'No se pudo guardar el respaldo: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ultimo = ref.watch(ultimoRespaldoProvider);
    final atrasado = respaldoAtrasado(ultimo);
    final texto = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Respaldos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: atrasado
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Colores.peligro),
                  )
                : null,
            child: ListTile(
              leading: Icon(
                atrasado ? Icons.warning_amber_rounded : Icons.verified_outlined,
                color: atrasado ? Colores.peligro : Colores.exito,
                size: 32,
              ),
              title: Text(descripcionUltimoRespaldo(ultimo)),
              subtitle: Text(
                atrasado
                    ? 'Todo el restaurante vive en esta tablet. Si se pierde o se rompe, sin respaldo se pierde todo.'
                    : 'Conviene guardar uno al cerrar cada semana.',
                style: const TextStyle(color: Colores.apagado),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Guardar un respaldo', style: texto.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Incluye usuarios, menú, pedidos, ventas y el código de enlace, cifrados con la contraseña que elijas. '
            'Guárdalo fuera de esta tablet (Drive, correo, otra tablet o una memoria USB).',
            style: TextStyle(color: Colores.apagado),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _ocupado ? null : () => _respaldar(compartir: false),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: _ocupado
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.save_alt),
            label: const Text('Guardar en…'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _ocupado ? null : () => _respaldar(compartir: true),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Enviar por WhatsApp, correo o Drive'),
          ),
          const SizedBox(height: 24),
          Text('Restaurar', style: texto.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Un respaldo se carga en una tablet nueva: instala la app, elige "Central de cocina" y toca '
            '"Restaurar desde un respaldo". Nunca sobrescribe una central que ya tiene datos. Después, en cada '
            'tablet de mesero, busca de nuevo la central (su IP cambia) y vuelve a iniciar sesión.',
            style: TextStyle(color: Colores.apagado),
          ),
        ],
      ),
    );
  }
}
