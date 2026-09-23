import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin/gestion_page.dart';
import '../auth/auth_controller.dart';
import '../auth/sesion.dart';
import '../caja/caja_page.dart';
import '../cocina/cocina_page.dart';
import '../mesero/pedidos_page.dart';

/// Pantalla principal según el rol: mesero y cocina ven solo lo suyo;
/// el administrador puede moverse entre salón, cocina y caja.
class InicioPage extends ConsumerWidget {
  const InicioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rol = ref.watch(authControllerProvider)?.usuario.rol;
    return switch (rol) {
      Rol.mesero => const PedidosPage(),
      Rol.cocina => const CocinaPage(),
      Rol.admin => const _InicioAdmin(),
      // Sin sesión el router redirige al login; esto solo se ve durante la transición.
      null => const Scaffold(),
    };
  }
}

class _InicioAdmin extends StatefulWidget {
  const _InicioAdmin();

  @override
  State<_InicioAdmin> createState() => _InicioAdminState();
}

class _InicioAdminState extends State<_InicioAdmin> {
  int _seccion = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _seccion,
        children: const [PedidosPage(), CocinaPage(), CajaPage(), GestionPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _seccion,
        onDestinationSelected: (i) => setState(() => _seccion = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Pedidos'),
          NavigationDestination(icon: Icon(Icons.soup_kitchen_outlined), label: 'Cocina'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'Caja'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Gestión'),
        ],
      ),
    );
  }
}
