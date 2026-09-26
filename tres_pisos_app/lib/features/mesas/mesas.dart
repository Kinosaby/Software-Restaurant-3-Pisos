import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../caja/cobro.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';
import '../pedidos/widgets_pedido.dart';

/// Mesas del restaurante (igual que `TOTAL_MESAS` en la web).
const totalMesas = 13;

/// Situación de una mesa según sus cuentas activas (la más urgente manda).
enum SituacionMesa {
  libre('Libre', Colores.apagado, Icons.event_seat_outlined),
  esperando('Esperando cocina', Colores.aviso, Icons.hourglass_top),
  enCocina('En cocina', Colores.azul, Icons.local_fire_department_outlined),
  lista('Lista para servir', Colores.exito, Icons.room_service_outlined);

  const SituacionMesa(this.etiqueta, this.color, this.icono);
  final String etiqueta;
  final Color color;
  final IconData icono;
}

class EstadoMesa {
  const EstadoMesa(this.numero, this.pedidos);

  final int numero;

  /// Cuentas activas de la mesa (pedidos para aquí; los de llevar van aparte).
  final List<Pedido> pedidos;

  SituacionMesa get situacion {
    if (pedidos.isEmpty) return SituacionMesa.libre;
    if (pedidos.any((p) => p.estado == EstadoPedido.listo)) return SituacionMesa.lista;
    if (pedidos.any((p) => p.estado == EstadoPedido.preparando)) return SituacionMesa.enCocina;
    return SituacionMesa.esperando;
  }

  double get total => pedidos.fold(0, (s, p) => s + p.total);
  List<Pedido> get porCobrar => [for (final p in pedidos) if (p.estado == EstadoPedido.listo) p];

  /// Desde cuándo está ocupada (la cuenta más antigua).
  DateTime? get desde => pedidos.isEmpty ? null : pedidos.map((p) => p.creadoEn).reduce((a, b) => a.isBefore(b) ? a : b);
}

/// Mesas 1..[totalMesas] más cualquier otra que tenga cuentas (p. ej. una mesa extra en la terraza).
List<EstadoMesa> estadoMesas(List<Pedido> activos) {
  final porMesa = <int, List<Pedido>>{};
  for (final p in activos) {
    porMesa.putIfAbsent(p.mesa, () => []).add(p);
  }
  final numeros = {for (var i = 1; i <= totalMesas; i++) i, ...porMesa.keys}.toList()..sort();
  return [for (final n in numeros) EstadoMesa(n, porMesa[n] ?? const [])];
}

/// Cuadrícula de mesas en vivo. Tocar una mesa libre empieza un pedido; una ocupada abre sus cuentas.
class MapaMesas extends ConsumerStatefulWidget {
  const MapaMesas({super.key});

  @override
  ConsumerState<MapaMesas> createState() => _MapaMesasState();
}

class _MapaMesasState extends ConsumerState<MapaMesas> {
  late final Timer _reloj;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _reloj.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pedidos = ref.watch(pedidosActivosProvider);
    final puedeCrear = ref.watch(authControllerProvider)?.usuario.rol.tomaPedidos ?? false;

    return pedidos.when(
      loading: () => const Cargando(),
      error: (e, _) => ErrorConReintento(error: e, alReintentar: () => ref.invalidate(pedidosActivosProvider)),
      data: (todos) {
        final mesas = estadoMesas(todos.where((p) => p.tipo == TipoPedido.aqui).toList());
        return RefreshIndicator(
          onRefresh: () => ref.read(pedidosActivosProvider.notifier).recargar(),
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: _Leyenda()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 170,
                    mainAxisExtent: 140,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: mesas.length,
                  itemBuilder: (context, i) {
                    final mesa = mesas[i];
                    return _TarjetaMesa(
                      mesa: mesa,
                      onTap: mesa.pedidos.isEmpty
                          ? (puedeCrear ? () => context.push('/nuevo?mesa=${mesa.numero}') : null)
                          : () => context.push('/mesa/${mesa.numero}'),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          for (final s in SituacionMesa.values)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(s.icono, size: 16, color: s.color),
                const SizedBox(width: 4),
                Text(s.etiqueta, style: const TextStyle(fontSize: 12, color: Colores.apagado)),
              ],
            ),
        ],
      ),
    );
  }
}

class _TarjetaMesa extends StatelessWidget {
  const _TarjetaMesa({required this.mesa, this.onTap});

  final EstadoMesa mesa;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = mesa.situacion;
    final libre = s == SituacionMesa.libre;
    final minutos = mesa.desde == null ? 0 : DateTime.now().difference(mesa.desde!).inMinutes;
    return Card(
      color: libre ? null : s.color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: s.color.withValues(alpha: libre ? 0.25 : 0.8), width: libre ? 1 : 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${mesa.numero}',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Icon(s.icono, color: s.color),
                ],
              ),
              const Spacer(),
              Text(s.etiqueta, style: TextStyle(color: s.color, fontWeight: FontWeight.w600, fontSize: 13)),
              if (!libre)
                Text(
                  '${mesa.pedidos.length == 1 ? '1 cuenta' : '${mesa.pedidos.length} cuentas'} · ${dinero(mesa.total)}'
                  '${minutos > 0 ? ' · $minutos min' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colores.apagado, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selector de mesa para la captura: libres y ocupadas, con la seleccionada resaltada.
Future<int?> elegirMesa(BuildContext context, WidgetRef ref, {int? actual}) {
  final activos = ref.read(pedidosActivosProvider).value ?? const [];
  final mesas = estadoMesas(activos.where((p) => p.tipo == TipoPedido.aqui).toList());
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Elige la mesa', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in mesas)
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: m.numero == actual
                            ? Colores.acento
                            : m.situacion == SituacionMesa.libre
                                ? Colores.tarjeta
                                : m.situacion.color.withValues(alpha: 0.25),
                        foregroundColor: m.numero == actual ? Colores.fondo : Colores.crema,
                      ),
                      onPressed: () => Navigator.pop(context, m.numero),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${m.numero}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          Text(
                            m.situacion == SituacionMesa.libre ? 'Libre' : 'Ocupada',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Cuentas de una mesa: agregar otra cuenta, abrir cada una y cobrar todo lo listo junto.
class MesaPage extends ConsumerWidget {
  const MesaPage({super.key, required this.numero});

  final int numero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidos = ref.watch(pedidosActivosProvider);
    final rol = ref.watch(authControllerProvider)?.usuario.rol;
    final cuentas = [
      for (final p in pedidos.value ?? const <Pedido>[])
        if (p.mesa == numero && p.tipo == TipoPedido.aqui) p,
    ];
    final mesa = EstadoMesa(numero, cuentas);

    return Scaffold(
      appBar: AppBar(title: Text('Mesa $numero')),
      floatingActionButton: (rol?.tomaPedidos ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/nuevo?mesa=$numero'),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Otra cuenta'),
            )
          : null,
      body: cuentas.isEmpty
          ? const Vacio(icono: Icons.event_seat_outlined, mensaje: 'La mesa está libre')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Row(
                  children: [
                    Icon(mesa.situacion.icono, color: mesa.situacion.color),
                    const SizedBox(width: 8),
                    Text(mesa.situacion.etiqueta, style: TextStyle(color: mesa.situacion.color)),
                    const Spacer(),
                    Text(
                      dinero(mesa.total),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colores.dorado),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if ((rol?.cobra ?? false) && mesa.porCobrar.isNotEmpty) ...[
                  FilledButton.icon(
                    onPressed: () => mostrarCobro(context, ref, mesa.porCobrar),
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(mesa.porCobrar.length == 1
                        ? 'Cobrar ${dinero(mesa.porCobrar.single.total)}'
                        : 'Cobrar mesa completa (${mesa.porCobrar.length} cuentas) · '
                            '${dinero(mesa.porCobrar.fold(0, (s, p) => s + p.total))}'),
                  ),
                  const SizedBox(height: 12),
                ],
                for (final p in cuentas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TarjetaPedido(pedido: p, onTap: () => context.push('/pedido/${p.id}')),
                  ),
              ],
            ),
    );
  }
}
