import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/tema.dart';
import 'features/admin/metricas_page.dart';
import 'features/admin/productos_admin_page.dart';
import 'features/admin/usuarios_admin_page.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/auth/sesion.dart';
import 'features/inicio/inicio_page.dart';
import 'features/mesero/captura_pedido_page.dart';
import 'features/mesero/editar_pedido_page.dart';
import 'features/mesero/pedido_detalle_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // GoRouter vuelve a evaluar `redirect` cada vez que cambia la sesión.
  final cambiosSesion = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => cambiosSesion.value++);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: cambiosSesion,
    redirect: (context, state) {
      final sesion = ref.read(authControllerProvider);
      final ruta = state.matchedLocation;
      if (sesion == null) return ruta == '/login' ? null : '/login';
      if (ruta == '/login') return '/';

      final capturaPedidos = ruta == '/nuevo' || ruta.endsWith('/agregar') || ruta.endsWith('/editar');
      if (capturaPedidos && !sesion.usuario.rol.tomaPedidos) return '/';
      if (ruta.startsWith('/admin') && sesion.usuario.rol != Rol.admin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/', builder: (_, _) => const InicioPage()),
      GoRoute(path: '/nuevo', builder: (_, _) => const CapturaPedidoPage()),
      GoRoute(path: '/admin/metricas', builder: (_, _) => const MetricasPage()),
      GoRoute(path: '/admin/productos', builder: (_, _) => const ProductosAdminPage()),
      GoRoute(path: '/admin/usuarios', builder: (_, _) => const UsuariosAdminPage()),
      GoRoute(
        path: '/pedido/:id',
        builder: (_, state) => PedidoDetallePage(pedidoId: _id(state)),
        routes: [
          GoRoute(
            path: 'agregar',
            builder: (_, state) => CapturaPedidoPage(pedidoId: _id(state)),
          ),
          GoRoute(
            path: 'editar',
            builder: (_, state) => EditarPedidoPage(pedidoId: _id(state)),
          ),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    cambiosSesion.dispose();
  });
  return router;
});

int _id(GoRouterState state) => int.tryParse(state.pathParameters['id'] ?? '') ?? 0;

class TresPisosApp extends ConsumerWidget {
  const TresPisosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Tres Pisos',
      debugShowCheckedModeBanner: false,
      theme: crearTema(),
      locale: const Locale('es', 'MX'),
      supportedLocales: const [Locale('es', 'MX'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
