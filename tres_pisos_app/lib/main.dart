// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/services/api_service.dart';
import 'core/services/auth_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/menu/role_menu_screen.dart';
import 'features/mesero/mesero_screen.dart';
import 'features/cocina/cocina_screen.dart';
import 'features/admin/admin_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.init();
  runApp(const ProviderScope(child: TresPisosApp()));
}

final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    final loggedIn = await AuthService.isLoggedIn();
    final isLogin  = state.matchedLocation == '/login';
    if (!loggedIn && !isLogin) return '/login';
    if (loggedIn && isLogin) {
      final role = await AuthService.getRole();
      return switch (role) { 'mesero' => '/mesero', 'cocina' => '/cocina', _ => '/menu' };
    }
    return null;
  },
  routes: [
    GoRoute(path: '/login',  builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/menu',   builder: (_, __) => const RoleMenuScreen()),
    GoRoute(path: '/mesero', builder: (_, __) => const MeseroScreen()),
    GoRoute(path: '/cocina', builder: (_, __) => const CocinaScreen()),
    GoRoute(path: '/admin',  builder: (_, __) => const AdminScreen()),
  ],
);

class TresPisosApp extends StatelessWidget {
  const TresPisosApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '3 Pisos POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}
