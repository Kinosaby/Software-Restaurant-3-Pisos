import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/tema.dart';
import 'features/admin/historial_page.dart';
import 'features/admin/metricas_page.dart';
import 'features/admin/productos_admin_page.dart';
import 'features/admin/usuarios_admin_page.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/auth/sesion.dart';
import 'features/conexion/central_info_page.dart';
import 'features/conexion/conexion_page.dart';
import 'features/conexion/enlace_qr.dart';
import 'features/conexion/respaldos_page.dart';
import 'features/inicio/inicio_page.dart';
import 'features/mesas/mesas.dart';
import 'features/mesero/captura_pedido_page.dart';
import 'features/mesero/carrito.dart';
import 'features/mesero/editar_pedido_page.dart';
import 'features/mesero/pedido_detalle_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // GoRouter vuelve a evaluar `redirect` cada vez que cambia la sesión.
  final cambiosSesion = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => cambiosSesion.value++);
  ref.listen(conexionProvider, (_, _) => cambiosSesion.value++);
  ref.listen(enlacePendienteProvider, (_, _) => cambiosSesion.value++);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: cambiosSesion,
    redirect: (context, state) {
      final ruta = state.matchedLocation;
      // Primera vez: hay que decidir si esta tablet es la central o se conecta a ella.
      if (ref.read(conexionProvider) == null) return ruta == '/conexion' ? null : '/conexion';
      if (ruta == '/conexion') return null;
      // Se escaneó el QR de una central: la pantalla de conexión pide confirmar.
      if (ref.read(enlacePendienteProvider) != null) return '/conexion';

      final sesion = ref.read(authControllerProvider);
      if (sesion == null) return ruta == '/login' ? null : '/login';
      if (ruta == '/login') return '/';

      final capturaPedidos = ruta == '/nuevo' || ruta.endsWith('/agregar') || ruta.endsWith('/editar');
      if (capturaPedidos && !sesion.usuario.rol.tomaPedidos) return '/';
      if (ruta.startsWith('/admin') && sesion.usuario.rol != Rol.admin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/conexion', builder: (_, _) => const ConexionPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/', builder: (_, _) => const InicioPage()),
      GoRoute(
        path: '/nuevo',
        builder: (_, state) => CapturaPedidoPage(
          mesa: int.tryParse(state.uri.queryParameters['mesa'] ?? ''),
          plantilla: state.extra is PlantillaPedido ? state.extra! as PlantillaPedido : null,
        ),
      ),
      GoRoute(
        path: '/mesa/:numero',
        builder: (_, state) => MesaPage(numero: int.tryParse(state.pathParameters['numero'] ?? '') ?? 0),
      ),
      GoRoute(path: '/admin/metricas', builder: (_, _) => const MetricasPage()),
      GoRoute(path: '/admin/historial', builder: (_, _) => const HistorialPage()),
      GoRoute(path: '/admin/central', builder: (_, _) => const CentralInfoPage()),
      GoRoute(path: '/admin/respaldos', builder: (_, _) => const RespaldosPage()),
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
      // Android 15+ dibuja la app debajo de la barra de navegación del sistema: sin
      // esto los botones de abajo quedan tapados. El AppBar ya respeta la barra de arriba.
      builder: (context, child) => ColoredBox(
        color: Colores.fondo,
        child: SafeArea(top: false, child: child!),
      ),
    );
  }
}
