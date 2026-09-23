import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';
import '../pedidos/widgets_pedido.dart';

/// Pedidos activos del salón para mesero y admin.
class PedidosPage extends ConsumerStatefulWidget {
  const PedidosPage({super.key});

  @override
  ConsumerState<PedidosPage> createState() => _PedidosPageState();
}

class _PedidosPageState extends ConsumerState<PedidosPage> {
  EstadoPedido? _filtro;

  @override
  Widget build(BuildContext context) {
    final pedidos = ref.watch(pedidosActivosProvider);
    final puedeCrear = ref.watch(authControllerProvider)?.usuario.rol.tomaPedidos ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
        actions: const [IndicadorConexion(), MenuUsuario()],
      ),
      floatingActionButton: puedeCrear
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/nuevo'),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo pedido'),
            )
          : null,
      body: pedidos.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorConReintento(
          error: e,
          alReintentar: () => ref.invalidate(pedidosActivosProvider),
        ),
        data: (todos) {
          final visibles = _filtro == null ? todos : todos.where((p) => p.estado == _filtro).toList();
          return Column(
            children: [
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    for (final estado in [null, ...EstadoPedido.values.where((e) => e.activo)])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            '${estado?.etiqueta ?? 'Todos'} '
                            '(${estado == null ? todos.length : todos.where((p) => p.estado == estado).length})',
                          ),
                          selected: _filtro == estado,
                          onSelected: (_) => setState(() => _filtro = estado),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => ref.read(pedidosActivosProvider.notifier).recargar(),
                  child: visibles.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Vacio(icono: Icons.receipt_long, mensaje: 'No hay pedidos activos'),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          itemCount: visibles.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final pedido = visibles[i];
                            return TarjetaPedido(
                              pedido: pedido,
                              onTap: () => context.push('/pedido/${pedido.id}'),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
