// lib/features/menu/role_menu_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/theme/app_theme.dart';

class RoleMenuScreen extends StatefulWidget {
  const RoleMenuScreen({super.key});
  @override
  State<RoleMenuScreen> createState() => _RoleMenuScreenState();
}

class _RoleMenuScreenState extends State<RoleMenuScreen> {
  String _username = '';
  String _role     = '';

  @override
  void initState() {
    super.initState();
    _load();
    SocketService.connect();
  }

  Future<void> _load() async {
    final user = await AuthService.getUser();
    if (!mounted) return;
    setState(() {
      _username = user?['username'] ?? user?['usuario'] ?? 'Usuario';
      _role     = user?['role']     ?? user?['rol']     ?? '';
    });
  }

  Future<void> _logout() async {
    SocketService.disconnect();
    await AuthService.clearSession();
    if (!mounted) return;
    context.go('/login');
  }

  Widget _roleCard({required String title, required String desc, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, color: AppColors.amber, size: 30),
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3 PISOS'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.amber,
                child: Text(_username.isNotEmpty ? _username[0].toUpperCase() : 'U',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              const SizedBox(width: 8),
              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_username, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                  child: Text(_role, style: const TextStyle(color: AppColors.amber, fontSize: 10))),
              ]),
              const SizedBox(width: 12),
              TextButton(onPressed: _logout, child: const Text('Salir', style: TextStyle(color: AppColors.muted))),
            ]),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Panel de Control', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Selecciona tu area de trabajo', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                children: [
                  if (_role == 'admin' || _role == 'mesero')
                    _roleCard(
                      title: 'Mesero',
                      desc: 'Tomar pedidos y gestionar mesas',
                      icon: Icons.person_outline,
                      onTap: () => context.go('/mesero'),
                    ),
                  if (_role == 'admin' || _role == 'cocina')
                    _roleCard(
                      title: 'Cocina',
                      desc: 'Ver pedidos y actualizar estado',
                      icon: Icons.local_fire_department_outlined,
                      onTap: () => context.go('/cocina'),
                    ),
                  if (_role == 'admin')
                    _roleCard(
                      title: 'Administrador',
                      desc: 'Usuarios, productos y metricas',
                      icon: Icons.settings_outlined,
                      onTap: () => context.go('/admin'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
