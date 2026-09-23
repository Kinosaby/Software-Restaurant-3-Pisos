import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../conexion/central_local.dart';

/// Punto de entrada a las herramientas del administrador.
class GestionPage extends ConsumerWidget {
  const GestionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esCentral = ref.watch(centralLocalProvider) != null;

    Widget opcion(IconData icono, String titulo, String detalle, String ruta) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              leading: Icon(icono, color: Colores.acento, size: 32),
              title: Text(titulo),
              subtitle: Text(detalle, style: const TextStyle(color: Colores.apagado)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(ruta),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión'),
        actions: const [IndicadorConexion(), MenuUsuario()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (esCentral)
            opcion(Icons.hub_outlined, 'Central de cocina', 'IP y código para enlazar las tablets de los meseros',
                '/admin/central'),
          opcion(Icons.insights_outlined, 'Métricas', 'Ventas del día y la semana, jueves a domingo, productos más pedidos',
              '/admin/metricas'),
          opcion(Icons.receipt_long_outlined, 'Pedidos e historial', 'Pedidos de hoy o de siempre; tickets y borrado',
              '/admin/historial'),
          opcion(Icons.restaurant_menu, 'Productos', 'Menú, precios, categorías y disponibilidad', '/admin/productos'),
          opcion(Icons.group_outlined, 'Usuarios', 'Meseros, cocina y administradores', '/admin/usuarios'),
          opcion(Icons.settings_ethernet, 'Conexión de esta tablet', 'Central de cocina o conectada a la central',
              '/conexion'),
        ],
      ),
    );
  }
}
