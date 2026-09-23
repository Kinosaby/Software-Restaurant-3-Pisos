import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../central/respaldo.dart';
import '../../central/seguridad.dart';
import '../../central/servidor_central.dart';
import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/formato.dart';
import '../../core/plataforma.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/sesion.dart';
import 'central_local.dart';
import 'enlace_qr.dart';
import 'respaldos_page.dart';

/// Elige cómo trabaja esta tablet: como central de cocina o conectada a la
/// central por el Wi-Fi del restaurante. Nada necesita internet.
class ConexionPage extends ConsumerStatefulWidget {
  const ConexionPage({super.key});

  @override
  ConsumerState<ConexionPage> createState() => _ConexionPageState();
}

class _ConexionPageState extends ConsumerState<ConexionPage> {
  // Con un QR escaneado se abre directamente en "Conectada a la central".
  late ModoConexion _modo = ref.read(enlacePendienteProvider) != null
      ? ModoConexion.enlazada
      : ref.read(conexionProvider)?.modo ?? ModoConexion.enlazada;

  @override
  Widget build(BuildContext context) {
    final actual = ref.watch(conexionProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conexión de esta tablet'),
        automaticallyImplyLeading: actual != null,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (actual != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Ahora: ${actual.modo.etiqueta} · ${actual.url}',
                    style: const TextStyle(color: Colores.apagado),
                  ),
                ),
              _OpcionModo(
                modo: ModoConexion.central,
                seleccionado: _modo,
                icono: Icons.soup_kitchen_outlined,
                descripcion: 'La tablet de cocina guarda menú, pedidos y ventas, y las demás se conectan a ella '
                    'por el Wi-Fi. Funciona sin internet.',
                onTap: () => setState(() => _modo = ModoConexion.central),
              ),
              _OpcionModo(
                modo: ModoConexion.enlazada,
                seleccionado: _modo,
                icono: Icons.tablet_android_outlined,
                descripcion: 'Tablet de mesero o caja. Se conecta a la central de cocina por el Wi-Fi; si se '
                    'pierde la señal, guarda los pedidos y los envía al volver.',
                onTap: () => setState(() => _modo = ModoConexion.enlazada),
              ),
              const SizedBox(height: 16),
              switch (_modo) {
                ModoConexion.central => const _FormularioCentral(),
                ModoConexion.enlazada => const _FormularioEnlace(),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _OpcionModo extends StatelessWidget {
  const _OpcionModo({
    required this.modo,
    required this.seleccionado,
    required this.icono,
    required this.descripcion,
    required this.onTap,
  });

  final ModoConexion modo;
  final ModoConexion seleccionado;
  final IconData icono;
  final String descripcion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activo = modo == seleccionado;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        shape: activo
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Colores.acento, width: 2),
              )
            : null,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(icono, color: activo ? Colores.acento : Colores.apagado, size: 32),
          title: Text(modo.etiqueta),
          subtitle: Text(descripcion, style: const TextStyle(color: Colores.apagado)),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Dejar de ser la central: avisa antes, porque las demás tablets dependen de ella.
Future<bool> _salirDeCentral(BuildContext context, WidgetRef ref) async {
  if (ref.read(centralLocalProvider) == null) return true;
  final ok = await confirmar(
    context,
    titulo: 'Esta tablet dejará de ser la central',
    mensaje: 'Las demás tablets perderán la conexión. Los datos de la central se conservan en esta tablet '
        'y vuelven al elegir de nuevo "Central de cocina".',
    accion: 'Continuar',
    destructiva: true,
  );
  if (ok) await ref.read(centralLocalProvider.notifier).detener();
  return ok;
}

class _FormularioCentral extends ConsumerStatefulWidget {
  const _FormularioCentral();

  @override
  ConsumerState<_FormularioCentral> createState() => _FormularioCentralState();
}

class _FormularioCentralState extends ConsumerState<_FormularioCentral> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController(text: 'Restaurante 3 Pisos');
  final _usuario = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _confirmacion = TextEditingController();
  bool _ocupado = false;

  @override
  void dispose() {
    _nombre.dispose();
    _usuario.dispose();
    _password.dispose();
    _confirmacion.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(centralLocalProvider.notifier).crear(
            admin: _usuario.text.trim(),
            password: _password.text,
            nombreRestaurante: _nombre.text,
          );
      // Con la sesión de administrador iniciada, el router pasa a la pantalla principal.
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, 'No se pudo iniciar la central: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Tablet nueva que reemplaza a la central: carga todo desde un archivo `.3pisos`.
  Future<void> _restaurar() async {
    final Uint8List? archivo;
    try {
      archivo = await Plataforma.abrirArchivo();
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, 'No se pudo abrir el archivo: $e', error: true);
      return;
    }
    if (archivo == null || !mounted) return;

    final InfoRespaldo info;
    try {
      info = leerInfoRespaldo(archivo);
    } on RespaldoInvalido catch (e) {
      mostrarMensaje(context, e.mensaje, error: true);
      return;
    }
    final ok = await confirmar(
      context,
      titulo: 'Restaurar respaldo',
      mensaje: '${info.restaurante}\nGuardado el ${fechaCorta(info.creado)}.\n\n'
          'Esta tablet pasará a ser la central con esos datos.',
      accion: 'Restaurar',
    );
    if (!ok || !mounted) return;
    final password = await pedirPasswordRespaldo(context, nueva: false);
    if (password == null || !mounted) return;

    setState(() => _ocupado = true);
    try {
      await ref.read(centralLocalProvider.notifier).restaurar(archivo, password);
      if (!mounted) return;
      mostrarMensaje(context, 'Respaldo cargado. Inicia sesión con un usuario del respaldo.');
      context.go('/login');
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, 'No se pudo restaurar: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Crea la cuenta de administrador. El menú del restaurante (54 productos) se carga solo. '
            'Si esta tablet ya era la central, escribe la cuenta de administrador que ya existe: los datos se conservan.',
            style: TextStyle(color: Colores.apagado),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nombre,
            decoration: const InputDecoration(labelText: 'Nombre del restaurante'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _usuario,
            decoration: const InputDecoration(labelText: 'Usuario administrador'),
            validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Mínimo 3 caracteres' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña'),
            validator: (v) => (v?.length ?? 0) < 6 ? 'Mínimo 6 caracteres' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _confirmacion,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Repite la contraseña'),
            validator: (v) => v != _password.text ? 'No coincide' : null,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _ocupado ? null : _iniciar,
            icon: _ocupado
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.power_settings_new),
            label: const Text('Iniciar central'),
          ),
          const SizedBox(height: 16),
          const Text(
            '¿Esta tablet reemplaza a una central perdida o dañada?',
            style: TextStyle(color: Colores.apagado),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _ocupado ? null : _restaurar,
            icon: const Icon(Icons.restore),
            label: const Text('Restaurar desde un respaldo'),
          ),
        ],
      ),
    );
  }
}

class _FormularioEnlace extends ConsumerStatefulWidget {
  const _FormularioEnlace();

  @override
  ConsumerState<_FormularioEnlace> createState() => _FormularioEnlaceState();
}

class _FormularioEnlaceState extends ConsumerState<_FormularioEnlace> {
  final _ip = TextEditingController();
  final _codigo = TextEditingController();
  List<CentralEncontrada> _encontradas = const [];
  bool _buscando = false;
  bool _buscado = false;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    final actual = ref.read(conexionProvider);
    if (actual?.modo == ModoConexion.enlazada) {
      _ip.text = Uri.parse(actual!.url).host;
      _codigo.text = actual.enlace ?? '';
    }
    // La app se abrió (o volvió) con el QR de una central: se pide confirmar.
    final pendiente = ref.read(enlacePendienteProvider);
    if (pendiente != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_conectarCon(pendiente));
      });
    }
  }

  @override
  void dispose() {
    _ip.dispose();
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _escanear() async {
    final String? texto;
    try {
      texto = await Plataforma.escanearQr();
    } on Object {
      if (mounted) {
        mostrarMensaje(
          context,
          'El escáner no está disponible en esta tablet. Abre la cámara y apunta al QR, o escribe la IP y el código.',
          error: true,
        );
      }
      return;
    }
    if (texto == null || !mounted) return;
    final datos = DatosEnlace.leer(texto);
    if (datos == null) {
      mostrarMensaje(context, 'Ese QR no es el de una central de Tres Pisos.', error: true);
      return;
    }
    await _conectarCon(datos);
  }

  /// Confirma, prueba cada IP del QR y enlaza con la primera que responde con ese código.
  Future<void> _conectarCon(DatosEnlace datos) async {
    final pendiente = ref.read(enlacePendienteProvider.notifier);
    if (ref.read(centralLocalProvider) != null) {
      pendiente.descartar();
      mostrarMensaje(context, 'Esta tablet es la central: el QR se escanea desde las tablets de los meseros.');
      return;
    }
    final ok = await confirmar(
      context,
      titulo: 'Conectar a la central',
      mensaje: '${datos.nombre ?? 'Central de cocina'}\n${datos.ips.join(' · ')}\n\n'
          'Solo conecta tablets a la central de tu restaurante.',
      accion: 'Conectar',
    );
    pendiente.descartar();
    if (!ok || !mounted) return;

    setState(() => _ocupado = true);
    try {
      ApiException? ultimoError;
      for (final url in datos.urls) {
        try {
          await ApiClient(servidor: url, enlace: datos.codigo).get('/api/central/info');
          if (!mounted) return;
          await ref
              .read(conexionProvider.notifier)
              .usar(Conexion(modo: ModoConexion.enlazada, url: url, enlace: datos.codigo));
          if (mounted) context.go('/login');
          return;
        } on ApiException catch (e) {
          ultimoError = e;
        }
      }
      if (mounted) {
        mostrarMensaje(
          context,
          ultimoError == null || ultimoError.sinConexion
              ? 'No se encontró la central. Comprueba que las dos tablets estén en el mismo Wi-Fi '
                  'y que la app de cocina esté abierta.'
              : ultimoError.mensaje,
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _buscar() async {
    setState(() {
      _buscando = true;
      _buscado = true;
    });
    await Plataforma.multicast(true);
    final encontradas = await buscarCentrales();
    await Plataforma.multicast(false);
    if (!mounted) return;
    setState(() {
      _buscando = false;
      _encontradas = encontradas;
      if (_ip.text.isEmpty && encontradas.length == 1) _ip.text = encontradas.single.ip;
    });
  }

  Future<void> _conectarManual() async {
    final host = _ip.text.trim();
    final codigo = normalizarCodigo(_codigo.text);
    if (host.isEmpty || codigo.length != 9) {
      mostrarMensaje(context, 'Escribe la IP de la central y el código de enlace (8 caracteres).', error: true);
      return;
    }
    final url = host.contains(':') ? normalizarServidor(host) : 'http://$host:$puertoCentral';
    setState(() => _ocupado = true);
    try {
      await ApiClient(servidor: url, enlace: codigo).get('/api/central/info');
      if (!mounted) return;
      if (!await _salirDeCentral(context, ref)) return;
      await ref.read(conexionProvider.notifier).usar(Conexion(modo: ModoConexion.enlazada, url: url, enlace: codigo));
      if (mounted) context.go('/login');
    } on ApiException catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // QR recibido con esta pantalla ya abierta (cámara del sistema).
    ref.listen(enlacePendienteProvider, (_, datos) {
      if (datos != null) unawaited(_conectarCon(datos));
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'En la tablet de cocina abre Gestión → Central de cocina y escanea el QR que aparece. '
          'Las dos tablets deben estar en el mismo Wi-Fi (no hace falta internet).',
          style: TextStyle(color: Colores.apagado),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _ocupado ? null : _escanear,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          icon: _ocupado
              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Icon(Icons.qr_code_scanner, size: 28),
          label: const Text('Escanear QR de la central', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 16),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Sin cámara: escribir IP y código', style: TextStyle(color: Colores.apagado)),
            onExpansionChanged: (abierto) {
              if (abierto && !_buscado) unawaited(_buscar());
            },
            children: [
              Row(
                children: [
                  Text('Centrales en el Wi-Fi', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _buscando ? null : _buscar,
                    icon: _buscando
                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_find),
                    label: Text(_buscando ? 'Buscando…' : 'Buscar'),
                  ),
                ],
              ),
              if (_buscado && !_buscando && _encontradas.isEmpty)
                const Text(
                  'No se encontró ninguna automáticamente. Escribe la IP a mano.',
                  style: TextStyle(color: Colores.apagado),
                ),
              for (final c in _encontradas)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.soup_kitchen_outlined, color: Colores.acento),
                    title: Text(c.nombre),
                    subtitle: Text(c.ip),
                    trailing: _ip.text == c.ip ? const Icon(Icons.check_circle, color: Colores.exito) : null,
                    onTap: () => setState(() => _ip.text = c.ip),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _ip,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'IP de la central', hintText: '192.168.1.20'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _codigo,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Código de enlace', hintText: 'K7P2-9QXM'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _ocupado ? null : _conectarManual,
                icon: const Icon(Icons.link),
                label: const Text('Conectar'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

