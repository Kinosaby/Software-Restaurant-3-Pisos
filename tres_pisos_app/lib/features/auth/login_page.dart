import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tema.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  late final _servidor = TextEditingController(text: ref.read(authControllerProvider.notifier).servidor);
  final _usuario = TextEditingController();
  final _password = TextEditingController();
  bool _enviando = false;
  bool _verPassword = false;
  String? _error;

  @override
  void dispose() {
    _servidor.dispose();
    _usuario.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).iniciarSesion(
            servidor: _servidor.text,
            usuario: _usuario.text,
            password: _password.text,
          );
      // El router nos lleva a la pantalla del rol en cuanto cambia la sesión.
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset('assets/logo.jpg', height: 140, fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Restaurante 3 Pisos',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colores.dorado,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _usuario,
                        decoration: const InputDecoration(
                          labelText: 'Usuario',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe tu usuario' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: !_verPassword,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _verPassword ? 'Ocultar' : 'Mostrar',
                            icon: Icon(_verPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _verPassword = !_verPassword),
                          ),
                        ),
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _entrar(),
                        validator: (v) => (v == null || v.isEmpty) ? 'Escribe tu contraseña' : null,
                      ),
                      const SizedBox(height: 12),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        leading: const Icon(Icons.dns_outlined, color: Colores.apagado),
                        title: const Text('Servidor', style: TextStyle(color: Colores.apagado)),
                        subtitle: ValueListenableBuilder(
                          valueListenable: _servidor,
                          builder: (context, valor, _) => Text(valor.text),
                        ),
                        children: [
                          TextFormField(
                            controller: _servidor,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'Dirección del servidor',
                              hintText: 'http://192.168.1.50:3000',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Indica el servidor' : null,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: const TextStyle(color: Colores.peligro)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _enviando ? null : _entrar,
                        child: _enviando
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : const Text('Entrar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
