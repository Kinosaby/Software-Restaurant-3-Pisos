import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../central/servidor_central.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import 'central_local.dart';
import 'enlace_qr.dart';

final _ipsProvider = FutureProvider.autoDispose<List<String>>((ref) => ipsLocales());

/// Datos para enlazar las tablets de los meseros con esta central.
class CentralInfoPage extends ConsumerStatefulWidget {
  const CentralInfoPage({super.key});

  @override
  ConsumerState<CentralInfoPage> createState() => _CentralInfoPageState();
}

class _CentralInfoPageState extends ConsumerState<CentralInfoPage> {
  late final Timer _refresco;

  @override
  void initState() {
    super.initState();
    // Actualiza el número de tablets conectadas.
    _refresco = Timer.periodic(const Duration(seconds: 3), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _refresco.cancel();
    super.dispose();
  }

  Future<void> _renovar() async {
    final ok = await confirmar(
      context,
      titulo: 'Renovar código de enlace',
      mensaje: 'Úsalo si se perdió una tablet o alguien conoce el código. Se cerrarán todas las sesiones y '
          'cada tablet de mesero tendrá que volver a enlazarse con el código nuevo.',
      accion: 'Renovar',
      destructiva: true,
    );
    if (!ok) return;
    try {
      await ref.read(centralLocalProvider.notifier).renovarEnlace();
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(centralLocalProvider);
    final ips = ref.watch(_ipsProvider);
    final texto = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Central de cocina')),
      body: local == null
          ? const Vacio(icono: Icons.cloud_off, mensaje: 'Esta tablet no es la central')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Para enlazar una tablet', style: texto.titleMedium),
                        const SizedBox(height: 4),
                        const Text(
                          'En la tablet del mesero elige "Conectada a la central" y toca "Escanear QR". '
                          'También sirve la cámara normal de la tablet.',
                          style: TextStyle(color: Colores.apagado),
                        ),
                        const SizedBox(height: 16),
                        if (ips.value case final lista? when lista.isNotEmpty)
                          Center(
                            child: VistaQr(
                              datos: DatosEnlace(
                                ips: ordenarIps(lista),
                                puerto: local.servidor.puertoEnUso,
                                codigo: local.central.codigoEnlace,
                                nombre: local.central.nombre,
                              ).uri.toString(),
                            ),
                          ),
                        const SizedBox(height: 16),
                        const Text('Sin cámara: escribe en la tablet del mesero', style: TextStyle(color: Colores.apagado)),
                        const SizedBox(height: 8),
                        const Text('IP de la central', style: TextStyle(color: Colores.apagado)),
                        ips.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (_, _) => const Text('No se pudo leer la IP'),
                          data: (lista) => lista.isEmpty
                              ? const Text('Sin Wi-Fi. Conecta la tablet a la red del restaurante.',
                                  style: TextStyle(color: Colores.peligro))
                              : Wrap(
                                  spacing: 12,
                                  children: [
                                    for (final ip in lista)
                                      SelectableText(ip, style: texto.headlineSmall?.copyWith(color: Colores.crema)),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Código de enlace', style: TextStyle(color: Colores.apagado)),
                        Row(
                          children: [
                            SelectableText(
                              local.central.codigoEnlace,
                              style: texto.displaySmall?.copyWith(
                                color: Colores.dorado,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copiar',
                              icon: const Icon(Icons.copy),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: local.central.codigoEnlace));
                                mostrarMensaje(context, 'Código copiado');
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.devices, color: Colores.acento),
                    title: Text('${local.servidor.clientesConectados} conexiones en tiempo real'),
                    subtitle: const Text('Incluye esta misma tablet', style: TextStyle(color: Colores.apagado)),
                  ),
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Mantén la app abierta y la tablet conectada a la corriente: si la app se cierra o la tablet '
                      'se apaga, las demás no podrán enviar pedidos hasta que vuelva. El router debe ser el '
                      'mismo para todas; no necesita internet. Usa la red del personal, no la de invitados.',
                      style: TextStyle(color: Colores.apagado),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _renovar,
                  style: OutlinedButton.styleFrom(foregroundColor: Colores.peligro),
                  icon: const Icon(Icons.key_off),
                  label: const Text('Renovar código de enlace'),
                ),
              ],
            ),
    );
  }
}
