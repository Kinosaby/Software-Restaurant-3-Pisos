// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/api_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_snackbar.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading    = false;
  bool _showPass   = false;

  Future<void> _login() async {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (user.isEmpty || pass.isEmpty) {
      AppSnackbar.error(context, 'Completa todos los campos.');
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await ApiService.login(user, pass);
      await AuthService.saveSession(res['token'], res['user'] ?? res);
      final role = await AuthService.getRole();
      if (!mounted) return;
      switch (role) {
        case 'admin':  context.go('/menu');   break;
        case 'mesero': context.go('/mesero'); break;
        case 'cocina': context.go('/cocina'); break;
        default:       context.go('/menu');
      }
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, e.toString().replaceAll('DioException', '').trim());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.restaurant, color: AppColors.amber, size: 44),
                ),
                const SizedBox(height: 20),
                const Text('3 PISOS',
                  style: TextStyle(
                    color: AppColors.amber,
                    fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 6),
                const Text('Sistema de gestión de pedidos',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 36),

                // Card login
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Usuario
                      const Text('Usuario', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _userCtrl,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Nombre de usuario',
                          prefixIcon: Icon(Icons.person_outline, color: AppColors.muted, size: 20),
                        ),
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                      ),
                      const SizedBox(height: 16),
                      // Contraseña
                      const Text('Contraseña', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passCtrl,
                        obscureText: !_showPass,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          prefixIcon: const Icon(Icons.lock_outline, color: AppColors.muted, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility,
                                color: AppColors.muted, size: 20),
                            onPressed: () => setState(() => _showPass = !_showPass),
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _login(),
                      ),
                      const SizedBox(height: 24),
                      // Botón
                      ElevatedButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                          ? const SizedBox(height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Text('INGRESAR'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }
}
