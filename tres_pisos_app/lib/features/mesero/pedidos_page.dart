import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../caja/cobro.dart';
import '../mesas/mesas.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';
import '../pedidos/widgets_pedido.dart';
import 'carrito.dart';

/// Salón para mesero y admin: mapa de mesas, cuentas abiertas y lo cobrado hoy.
class PedidosPage extends ConsumerWidget {
  const PedidosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puedeCrear = ref.watch(authControllerProvider)?.usuario.rol.tomaPedidos ?? false;
    final abiertas = ref.watch(pedidosActivosProvider.select((p) => p.value?.length ?? 0));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Salón'),
          actions: const [IndicadorConexion(), MenuUsuario()],
          bottom: TabBar(
            tabs: [
              const Tab(icon: Icon(Icons.grid_view), text: 'Mesas'),
              Tab(icon: const Icon(Icons.receipt_long_outlined), text: 'Cuentas ($abiertas)'),
              const Tab(icon: Icon(Icons.history), text: 'Cobradas hoy'),
            ],
          ),
        ),
        floatingActionButton: puedeCrear
            ? FloatingActionButton.extended(
                onPressed: () => context.push('/nuevo'),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo pedido'),
              )
            : null,
        body: const Column(
          children: [
            AvisoSinConexion(),
            Expanded(
              child: TabBarView(children: [MapaMesas(), _Cuentas(), _CobradasHoy()]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cuentas abiertas agrupadas por mesa (como en la web); las de llevar van al final.
class _Cuentas extends ConsumerWidget {
  const _Cuentas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidos = ref.watch(pedidosActivosProvider);
    final cola = ref.watch(colaEnviosProvider);
    final cobra = ref.watch(authControllerProvider)?.usuario.rol.cobra ?? false;

    return pedidos.when(
      loading: () => const Cargando(),
      error: (e, _) => ErrorConReintento(error: e, alReintentar: () => ref.invalidate(pedidosActivosProvider)),
      data: (todos) {
        final mesas = estadoMesas(todos.where((p) => p.tipo == TipoPedido.aqui).toList())
            .where((m) => m.pedidos.isNotEmpty)
            .toList();
        final llevar = todos.where((p) => p.tipo == TipoPedido.llevar).toList();

        return RefreshIndicator(
          onRefresh: () => ref.read(pedidosActivosProvider.notifier).recargar(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (cola.isNotEmpty) ...[
                const _Titulo('Pendientes de enviar', icono: Icons.cloud_upload_outlined, color: Colores.aviso),
                for (final envio in cola) _TarjetaEnvio(envio: envio),
                const SizedBox(height: 16),
              ],
              if (mesas.isEmpty && llevar.isEmpty && cola.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 120),
                  child: Vacio(icono: Icons.receipt_long, mensaje: 'No hay cuentas abiertas'),
                ),
              for (final mesa in mesas) ...[
                Row(
                  children: [
                    Expanded(
                      child: _Titulo('Mesa ${mesa.numero}', icono: mesa.situacion.icono, color: mesa.situacion.color),
                    ),
                    if (cobra && mesa.porCobrar.length > 1)
                      TextButton.icon(
                        onPressed: () => mostrarCobro(context, ref, mesa.porCobrar),
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label: Text('Cobrar mesa · ${dinero(mesa.porCobrar.fold(0, (s, p) => s + p.total))}'),
                      ),
                  ],
                ),
                for (final p in mesa.pedidos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TarjetaPedido(pedido: p, onTap: () => context.push('/pedido/${p.id}')),
                  ),
                const SizedBox(height: 8),
              ],
              if (llevar.isNotEmpty) ...[
                const _Titulo('Para llevar', icono: Icons.takeout_dining, color: Colores.acento),
                for (final p in llevar)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TarjetaPedido(pedido: p, onTap: () => context.push('/pedido/${p.id}')),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto, {required this.icono, required this.color});

  final String texto;
  final IconData icono;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icono, size: 20, color: color),
          const SizedBox(width: 8),
          Text(texto, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _TarjetaEnvio extends ConsumerWidget {
  const _TarjetaEnvio({required this.envio});

  final EnvioPendiente envio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cola = ref.read(colaEnviosProvider.notifier);
    final rechazado = envio.error != null;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: rechazado ? Colores.peligro : Colores.aviso),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(envio.descripcion, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              rechazado ? envio.error! : 'Guardado ${hora(envio.creado)} · cocina aún no lo recibe',
              style: TextStyle(color: rechazado ? Colores.peligro : Colores.apagado),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    final ok = await confirmar(
                      context,
                      titulo: 'Descartar envío',
                      mensaje: 'Se borra de esta tablet y cocina no lo recibirá.',
                      accion: 'Descartar',
                      destructiva: true,
                    );
                    if (ok) cola.descartar(envio);
                  },
                  child: const Text('Descartar'),
                ),
                FilledButton.tonal(onPressed: () => cola.reintentar(envio), child: const Text('Reintentar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo cobrado hoy: sirve para consultar y para repetir un pedido en un toque.
class _CobradasHoy extends ConsumerWidget {
  const _CobradasHoy();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pagados = ref.watch(pagadosHoyProvider);
    final puedeCrear = ref.watch(authControllerProvider)?.usuario.rol.tomaPedidos ?? false;

    return pagados.when(
      loading: () => const Cargando(),
      error: (e, _) => ErrorConReintento(error: e, alReintentar: () => ref.invalidate(pagadosHoyProvider)),
      data: (lista) {
        final total = lista.fold<double>(0, (s, p) => s + p.total);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(pagadosHoyProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Text('${lista.length} cuentas · ${dinero(total)}', style: const TextStyle(color: Colores.apagado)),
              const SizedBox(height: 12),
              if (lista.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 100),
                  child: Vacio(icono: Icons.history, mensaje: 'Aún no se ha cobrado nada hoy'),
                ),
              for (final p in lista)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TarjetaPedido(
                    pedido: p,
                    accion: puedeCrear ? BotonRepetir(pedido: p) : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Abre la captura con los mismos productos (al precio actual) y la misma mesa.
class BotonRepetir extends ConsumerWidget {
  const BotonRepetir({super.key, required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.replay),
      label: const Text('Repetir pedido'),
      onPressed: () async {
        try {
          final catalogo = await ref.read(productosProvider.future);
          final plantilla = PlantillaPedido.desde(pedido, catalogo);
          if (!context.mounted) return;
          if (plantilla.lineas.isEmpty) {
            mostrarMensaje(context, 'Ninguno de esos productos está disponible ahora.', error: true);
            return;
          }
          if (plantilla.lineas.length < pedido.items.length) {
            mostrarMensaje(context, 'Algunos productos ya no están disponibles y se omitieron.');
          }
          await context.push('/nuevo', extra: plantilla);
        } on Object catch (e) {
          if (context.mounted) mostrarMensaje(context, '$e', error: true);
        }
      },
    );
  }
}
