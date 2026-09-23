import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../central/seguridad.dart';
import '../../central/servidor_central.dart';
import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/plataforma.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/sesion.dart';
import 'central_local.dart';

/// Elige cómo trabaja esta tablet: como central de cocina o conectada a la
/// central por el Wi-Fi del restaurante. Nada necesita internet.
class ConexionPage extends ConsumerStatefulWidget {
  const ConexionPage({super.key});

  @override
  ConsumerState<ConexionPage> createState() => _ConexionPageState();
}

class _ConexionPageState extends ConsumerState<ConexionPage> {
  late ModoConexion _modo = ref.read(conexionProvider)?.modo ?? ModoConexion.enlazada;

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
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    final actual = ref.read(conexionProvider);
    if (actual?.modo == ModoConexion.enlazada) {
      _ip.text = Uri.parse(actual!.url).host;
      _codigo.text = actual.enlace ?? '';
    }
    unawaited(_buscar());
  }

  @override
  void dispose() {
    _ip.dispose();
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() => _buscando = true);
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

  Future<void> _conectar() async {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'En la tablet de cocina abre Gestión → Central para ver su IP y el código de enlace. '
          'Las dos tablets deben estar en el mismo Wi-Fi (no hace falta internet).',
          style: TextStyle(color: Colores.apagado),
        ),
        const SizedBox(height: 12),
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
        if (!_buscando && _encontradas.isEmpty)
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
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _ocupado ? null : _conectar,
          icon: _ocupado
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Icon(Icons.link),
          label: const Text('Conectar'),
        ),
      ],
    );
  }
}
