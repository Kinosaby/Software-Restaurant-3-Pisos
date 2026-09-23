import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/tema.dart';
import '../../core/widgets.dart';

/// Punto de entrada a las herramientas del administrador.
class GestionPage extends StatelessWidget {
  const GestionPage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget opcion(IconData icono, String titulo, String detalle, String ruta) => Card(
          child: ListTile(
            leading: Icon(icono, color: Colores.acento, size: 32),
            title: Text(titulo),
            subtitle: Text(detalle, style: const TextStyle(color: Colores.apagado)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(ruta),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión'),
        actions: const [MenuUsuario()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          opcion(Icons.insights_outlined, 'Métricas', 'Ventas del día y la semana, productos más pedidos', '/admin/metricas'),
          const SizedBox(height: 10),
          opcion(Icons.restaurant_menu, 'Productos', 'Menú, precios, categorías y disponibilidad', '/admin/productos'),
          const SizedBox(height: 10),
          opcion(Icons.group_outlined, 'Usuarios', 'Meseros, cocina y administradores', '/admin/usuarios'),
        ],
      ),
    );
  }
}
