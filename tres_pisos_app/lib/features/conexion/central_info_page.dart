import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../central/servidor_central.dart';
import '../../core/plataforma.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import 'aviso_red.dart';
import 'central_local.dart';
import 'enlace_qr.dart';
import 'red_propia.dart';

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
    // Actualiza el número de tablets conectadas y la IP: si la central arrancó
    // sin Wi-Fi o el router le dio otra IP, el QR se corrige solo.
    _refresco = Timer.periodic(const Duration(seconds: 3), (_) {
      ref.invalidate(_ipsProvider);
      setState(() {});
    });
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

  Future<void> _redPropia(bool encender) async {
    final notifier = ref.read(redPropiaProvider.notifier);
    if (!encender) {
      // Solo se pregunta si hay una red de verdad que los meseros puedan estar usando.
      final ok = ref.read(redPropiaProvider).fase != FaseRedPropia.activa ||
          await confirmar(
            context,
            titulo: 'Apagar la red propia',
            mensaje: 'Las tablets de los meseros conectadas a esta red perderán la conexión. '
                'Úsalo solo si ya tienen un router.',
            accion: 'Apagar',
            destructiva: true,
          );
      if (ok) await notifier.apagar();
      return;
    }
    // Si falla, el motivo queda escrito debajo del interruptor (y aquí se avisa una vez).
    final error = await notifier.encender();
    if (error != null && mounted) mostrarMensaje(context, error, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(centralLocalProvider);
    final ips = ref.watch(_ipsProvider);
    final red = ref.watch(redPropiaProvider);
    // Android 7 no puede crear la red: la opción se ve desactivada, con el motivo.
    final puedeCrearRed = ref.watch(capacidadesRedProvider).value?.crearRed ?? true;
    // Al crearse la red la tablet estrena IP: se lee sin esperar al refresco.
    ref.listen(redPropiaProvider, (_, _) => ref.invalidate(_ipsProvider));
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
                        // Sin router y con la red caída no se muestra un QR que no serviría.
                        if (red.pedida && red.red == null)
                          const Text(
                            'El QR aparecerá aquí cuando la red Wi-Fi de la central esté lista.',
                            style: TextStyle(color: Colores.aviso),
                          )
                        else if (ips.value case final lista? when lista.isNotEmpty)
                          Center(
                            child: VistaQr(
                              datos: DatosEnlace(
                                ips: ordenarIps(lista),
                                puerto: local.servidor.puertoEnUso,
                                codigo: local.central.codigoEnlace,
                                nombre: local.central.nombre,
                                red: red.red,
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
                              ? const Text(
                                  'Sin Wi-Fi. Conecta la tablet a la red del restaurante o activa "Trabajar sin router".',
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.wifi_tethering, color: Colores.acento),
                          title: const Text('Trabajar sin router'),
                          subtitle: Text(
                            puedeCrearRed
                                ? 'Esta tablet crea su propia red Wi-Fi: sin router, sin internet y sin datos. '
                                    'Los meseros se unen escaneando el QR.'
                                : 'Esta tablet tiene Android 7 y no puede crear su propia red Wi-Fi. Usa un router, '
                                    'o pon como central una tablet con Android 8 o más nuevo.',
                            style: const TextStyle(color: Colores.apagado),
                          ),
                          // Encendido mientras se quiera red propia, aunque ahora esté caída.
                          value: red.pedida,
                          onChanged: puedeCrearRed || red.pedida ? _redPropia : null,
                        ),
                        if (red.fase == FaseRedPropia.creando) ...[
                          const LinearProgressIndicator(),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Text('Creando la red Wi-Fi…', style: TextStyle(color: Colores.apagado)),
                          ),
                        ],
                        if (red.fase == FaseRedPropia.caida)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'La red no está encendida: los meseros no pueden conectarse.',
                                  style: TextStyle(color: Colores.peligro, fontWeight: FontWeight.bold),
                                ),
                                if (red.error case final error?)
                                  Text(error, style: const TextStyle(color: Colores.peligro)),
                                if (red.reintentando)
                                  const Text('Se está volviendo a crear…', style: TextStyle(color: Colores.apagado)),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    if (ajustesParaRed(red.codigo) case final ajustes?)
                                      OutlinedButton.icon(
                                        onPressed: () => unawaited(Plataforma.abrirAjustes(ajustes)),
                                        icon: const Icon(Icons.settings),
                                        label: const Text('Abrir ajustes'),
                                      ),
                                    if (!red.reintentando)
                                      OutlinedButton.icon(
                                        onPressed: () => unawaited(_redPropia(true)),
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Reintentar'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        if (red.red case final r?)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Red: ${r.ssid}', style: texto.titleMedium),
                                SelectableText('Contraseña: ${r.clave}'),
                                const SizedBox(height: 6),
                                const Text(
                                  'Android cambia el nombre y la contraseña cada vez que se crea la red '
                                  '(si se reinicia esta tablet o la app, o si Android la apaga por pasar un rato '
                                  'sin tablets conectadas). Entonces cada mesero vuelve a escanear el QR; sus '
                                  'pedidos pendientes no se pierden.',
                                  style: TextStyle(color: Colores.apagado),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Tablets con Android 9 o anterior: conéctalas a esta red desde Ajustes > Wi-Fi '
                                  'con esta contraseña y después escanea el QR.',
                                  style: TextStyle(color: Colores.apagado),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.devices, color: Colores.acento),
                    title: Text(local.servidor.clientesConectados == 1
                        ? '1 conexión en tiempo real'
                        : '${local.servidor.clientesConectados} conexiones en tiempo real'),
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
