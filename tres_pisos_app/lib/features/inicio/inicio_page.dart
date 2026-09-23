import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/tema.dart';
import '../admin/gestion_page.dart';
import '../auth/auth_controller.dart';
import '../auth/sesion.dart';
import '../avisos/avisos.dart';
import '../caja/caja_page.dart';
import '../cocina/cocina_page.dart';
import '../mesero/pedidos_page.dart';
import '../pedidos/pedidos_controller.dart';

/// Pantalla principal según el rol: mesero y cocina ven solo lo suyo;
/// el administrador puede moverse entre salón, cocina, caja y gestión.
/// Además muestra los avisos en tiempo real y mantiene activa la cola de envíos.
class InicioPage extends ConsumerWidget {
  const InicioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rol = ref.watch(authControllerProvider)?.usuario.rol;

    // La cola se procesa sola mientras haya alguien escuchándola.
    ref.watch(colaEnviosProvider);
    ref.listen(avisosProvider, (_, siguiente) {
      final aviso = siguiente.value;
      if (aviso == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(aviso.mensaje, style: const TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: aviso.urgente ? Colores.acento : Colores.exito,
          duration: Duration(seconds: aviso.urgente ? 6 : 5),
          action: aviso.pedidoId == null || rol == Rol.cocina
              ? null
              : SnackBarAction(
                  label: 'Ver',
                  textColor: Colores.fondo,
                  onPressed: () => context.push('/pedido/${aviso.pedidoId}'),
                ),
        ));
    });

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
          NavigationDestination(icon: Icon(Icons.table_restaurant_outlined), label: 'Salón'),
          NavigationDestination(icon: Icon(Icons.soup_kitchen_outlined), label: 'Cocina'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'Caja'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Gestión'),
        ],
      ),
    );
  }
}
