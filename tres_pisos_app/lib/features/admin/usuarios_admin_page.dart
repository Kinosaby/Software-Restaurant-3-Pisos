import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/sesion.dart';
import 'admin_repository.dart';

final usuariosAdminProvider = FutureProvider.autoDispose<List<Usuario>>(
  (ref) => ref.watch(adminRepositoryProvider).usuarios(),
);

IconData iconoRol(Rol rol) => switch (rol) {
      Rol.admin => Icons.admin_panel_settings_outlined,
      Rol.mesero => Icons.room_service_outlined,
      Rol.cocina => Icons.soup_kitchen_outlined,
    };

class UsuariosAdminPage extends ConsumerWidget {
  const UsuariosAdminPage({super.key});

  Future<void> _abrirFormulario(BuildContext context, WidgetRef ref, [Usuario? usuario]) async {
    final cambio = await showDialog<bool>(
      context: context,
      builder: (_) => _FormularioUsuario(usuario: usuario),
    );
    if (cambio ?? false) ref.invalidate(usuariosAdminProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuarios = ref.watch(usuariosAdminProvider);
    final yo = ref.watch(authControllerProvider)?.usuario.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Usuario'),
      ),
      body: usuarios.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorConReintento(error: e, alReintentar: () => ref.invalidate(usuariosAdminProvider)),
        data: (lista) => RefreshIndicator(
          onRefresh: () => ref.refresh(usuariosAdminProvider.future),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: lista.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final u = lista[i];
              return Card(
                child: ListTile(
                  leading: Icon(iconoRol(u.rol), color: Colores.acento),
                  title: Text(u.id == yo ? '${u.username} (tú)' : u.username),
                  subtitle: Text(u.rol.etiqueta),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _abrirFormulario(context, ref, u),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FormularioUsuario extends ConsumerStatefulWidget {
  const _FormularioUsuario({this.usuario});

  final Usuario? usuario;

  @override
  ConsumerState<_FormularioUsuario> createState() => _FormularioUsuarioState();
}

class _FormularioUsuarioState extends ConsumerState<_FormularioUsuario> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.usuario?.username);
  final _password = TextEditingController();
  late Rol _rol = widget.usuario?.rol ?? Rol.mesero;
  bool _ocupado = false;

  bool get _editando => widget.usuario != null;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(adminRepositoryProvider).guardarUsuario(
            id: widget.usuario?.id,
            username: _username.text.trim(),
            rol: _rol,
            password: _password.text,
          );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _eliminar() async {
    final usuario = widget.usuario!;
    final ok = await confirmar(
      context,
      titulo: 'Eliminar a ${usuario.username}',
      mensaje: 'Ya no podrá iniciar sesión y se cierran sus sesiones abiertas. Sus pedidos conservan su nombre.',
      accion: 'Eliminar',
      destructiva: true,
    );
    if (!ok || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(adminRepositoryProvider).eliminarUsuario(usuario.id);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esYo = widget.usuario?.id == ref.watch(authControllerProvider)?.usuario.id;

    return AlertDialog(
      title: Text(_editando ? 'Editar usuario' : 'Nuevo usuario'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _username,
                autofocus: !_editando,
                maxLength: 30,
                decoration: const InputDecoration(labelText: 'Usuario'),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  return t.length < 3 ? 'Mínimo 3 caracteres' : null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  helperText: _editando ? 'Déjala vacía para no cambiarla' : null,
                ),
                validator: (v) {
                  final t = v ?? '';
                  if (_editando && t.isEmpty) return null;
                  return t.length < 6 ? 'Mínimo 6 caracteres' : null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Rol>(
                initialValue: _rol,
                decoration: InputDecoration(
                  labelText: 'Rol',
                  helperText: esYo ? 'No puedes cambiar tu propio rol' : null,
                ),
                items: [
                  for (final rol in Rol.values)
                    DropdownMenuItem(
                      value: rol,
                      child: Row(
                        children: [Icon(iconoRol(rol), size: 20), const SizedBox(width: 10), Text(rol.etiqueta)],
                      ),
                    ),
                ],
                // Un admin no puede quitarse el rol a sí mismo y quedarse fuera.
                onChanged: esYo ? null : (rol) => setState(() => _rol = rol ?? _rol),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_editando && !esYo)
          TextButton(
            onPressed: _ocupado ? null : _eliminar,
            style: TextButton.styleFrom(foregroundColor: Colores.peligro),
            child: const Text('Eliminar'),
          ),
        TextButton(onPressed: _ocupado ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _ocupado ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
