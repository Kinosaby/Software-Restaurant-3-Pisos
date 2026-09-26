import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/plataforma.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../conexion/central_local.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';
import '../pedidos/widgets_pedido.dart';

/// Pedidos de cocina agrupados como en la web: cada mesa junta sus cuentas; cada
/// pedido para llevar va por separado. Ordenados por el más antiguo.
class GrupoCocina {
  const GrupoCocina({required this.clave, required this.titulo, required this.pedidos, required this.llevar});

  final String clave;
  final String titulo;
  final List<Pedido> pedidos;
  final bool llevar;

  DateTime get desde => pedidos.map((p) => p.creadoEn).reduce((a, b) => a.isBefore(b) ? a : b);
  bool get hayPendientes => pedidos.any((p) => p.estado == EstadoPedido.pendiente);
}

List<GrupoCocina> agruparCocina(List<Pedido> activos) {
  final grupos = <String, GrupoCocina>{};
  for (final p in activos.where((p) => p.estado.modificable)) {
    final llevar = p.tipo == TipoPedido.llevar;
    final clave = llevar ? 'llevar-${p.id}' : 'mesa-${p.mesa}';
    final previo = grupos[clave];
    grupos[clave] = GrupoCocina(
      clave: clave,
      titulo: llevar ? 'Para llevar${p.comensal == null ? '' : ' · ${p.comensal}'}' : 'Mesa ${p.mesa}',
      pedidos: [...?previo?.pedidos, p],
      llevar: llevar,
    );
  }
  return grupos.values.toList()..sort((a, b) => a.desde.compareTo(b.desde));
}

class CocinaPage extends ConsumerStatefulWidget {
  const CocinaPage({super.key});

  @override
  ConsumerState<CocinaPage> createState() => _CocinaPageState();
}

class _CocinaPageState extends ConsumerState<CocinaPage> {
  late final Timer _reloj;
  late final bool _esCentral;
  final _enCurso = <String>{};

  @override
  void initState() {
    super.initState();
    // Refresca los "hace X min" de las tarjetas.
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
    // `ref` no se puede usar en dispose, así que se decide aquí.
    _esCentral = ref.read(centralLocalProvider) != null;
    unawaited(Plataforma.pantallaEncendida(true));
  }

  @override
  void dispose() {
    _reloj.cancel();
    // En la central la pantalla sigue encendida: las demás tablets dependen de ella.
    if (!_esCentral) unawaited(Plataforma.pantallaEncendida(false));
    super.dispose();
  }

  Future<void> _ejecutar(String clave, Future<void> Function() accion) async {
    setState(() => _enCurso.add(clave));
    try {
      await accion();
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _enCurso.remove(clave));
    }
  }

  Future<void> _avanzarGrupo(GrupoCocina grupo, EstadoPedido estado) => _ejecutar(
        grupo.clave,
        () => ref.read(pedidosActivosProvider.notifier).cambiarEstadoVarios(
              [
                for (final p in grupo.pedidos)
                  if (estado == EstadoPedido.listo || p.estado == EstadoPedido.pendiente) p.id,
              ],
              estado,
            ),
      );

  Future<void> _cancelar(Pedido pedido) async {
    final ok = await confirmar(
      context,
      titulo: 'Cancelar pedido #${pedido.id}',
      mensaje: 'Se avisará al mesero. No se puede deshacer.',
      accion: 'Cancelar pedido',
      destructiva: true,
    );
    if (!ok) return;
    await _ejecutar('p${pedido.id}',
        () => ref.read(pedidosActivosProvider.notifier).cambiarEstado(pedido.id, EstadoPedido.cancelado));
  }

  @override
  Widget build(BuildContext context) {
    final pedidos = ref.watch(pedidosActivosProvider);
    final extras = ref.watch(extrasCocinaProvider);

    // Las casillas de pedidos que ya salieron de cocina no se necesitan.
    ref.listen(pedidosActivosProvider, (_, siguiente) {
      final activos = siguiente.value;
      if (activos == null) return;
      ref.read(marcasCocinaProvider.notifier).limpiar({
        for (final p in activos.where((p) => p.estado.modificable)) 'p${p.id}',
        for (final e in ref.read(extrasCocinaProvider)) 'e${e.clave}',
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cocina'),
        actions: const [IndicadorConexion(), MenuUsuario()],
      ),
      body: Column(
        children: [
          const AvisoSinConexion(),
          Expanded(
            child: pedidos.when(
              loading: () => const Cargando(),
              error: (e, _) => ErrorConReintento(
                error: e,
                alReintentar: () => ref.invalidate(pedidosActivosProvider),
              ),
              data: (todos) {
                final grupos = agruparCocina(todos);
                return RefreshIndicator(
                  onRefresh: () => ref.read(pedidosActivosProvider.notifier).recargar(),
                  child: grupos.isEmpty && extras.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 160),
                            Vacio(icono: Icons.soup_kitchen_outlined, mensaje: 'Sin pedidos por preparar'),
                          ],
                        )
                      : CustomScrollView(
                          slivers: [
                            if (extras.isNotEmpty)
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                sliver: SliverList.separated(
                                  itemCount: extras.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                                  itemBuilder: (context, i) => _TarjetaExtra(extra: extras[i]),
                                ),
                              ),
                            SliverPadding(
                              padding: const EdgeInsets.all(16),
                              sliver: SliverGrid.builder(
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 440,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  mainAxisExtent: 420,
                                ),
                                itemCount: grupos.length,
                                itemBuilder: (context, i) => _TarjetaGrupo(
                                  grupo: grupos[i],
                                  ocupado: _enCurso.contains(grupos[i].clave),
                                  onPreparar: () => _avanzarGrupo(grupos[i], EstadoPedido.preparando),
                                  onListo: () => _avanzarGrupo(grupos[i], EstadoPedido.listo),
                                  onCancelar: _cancelar,
                                ),
                              ),
                            ),
                          ],
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaGrupo extends ConsumerWidget {
  const _TarjetaGrupo({
    required this.grupo,
    required this.ocupado,
    required this.onPreparar,
    required this.onListo,
    required this.onCancelar,
  });

  final GrupoCocina grupo;
  final bool ocupado;
  final VoidCallback onPreparar;
  final VoidCallback onListo;
  final void Function(Pedido) onCancelar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marcas = ref.watch(marcasCocinaProvider);
    final minutos = DateTime.now().difference(grupo.desde).inMinutes;
    final color = grupo.hayPendientes ? Colores.aviso : Colores.azul;
    final renglones = grupo.pedidos.fold(0, (s, p) => s + p.items.length);
    final hechos = grupo.pedidos.fold(0, (s, p) => s + (marcas['p${p.id}']?.length ?? 0));
    final todoMarcado = renglones > 0 && hechos >= renglones;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.7), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(grupo.llevar ? Icons.takeout_dining : Icons.table_restaurant, color: Colores.acento),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(grupo.titulo,
                      style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis),
                ),
                Text(
                  tiempoTranscurrido(grupo.desde),
                  style: TextStyle(
                    color: minutos >= 20 ? Colores.peligro : Colores.apagado,
                    fontWeight: minutos >= 20 ? FontWeight.bold : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('$hechos/$renglones listos', style: const TextStyle(color: Colores.apagado, fontSize: 12)),
            const Divider(height: 16),
            Expanded(
              child: ListView(
                children: [
                  for (final p in grupo.pedidos) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            [if (p.comensal != null && !grupo.llevar) p.comensal!, '#${p.id}', ?p.mesero].join(' · '),
                            style: const TextStyle(color: Colores.apagado, fontSize: 12),
                          ),
                        ),
                        ChipEstado(p.estado),
                        IconButton(
                          tooltip: 'Cancelar pedido',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 18, color: Colores.peligro),
                          onPressed: ocupado ? null : () => onCancelar(p),
                        ),
                      ],
                    ),
                    for (var i = 0; i < p.items.length; i++)
                      _RenglonMarcable(
                        item: p.items[i],
                        hecho: marcas['p${p.id}']?.contains(i) ?? false,
                        onTap: () => ref.read(marcasCocinaProvider.notifier).alternar('p${p.id}', i),
                      ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (grupo.hayPendientes) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: ocupado ? null : onPreparar,
                      style: FilledButton.styleFrom(backgroundColor: Colores.azul, foregroundColor: Colores.fondo),
                      icon: const Icon(Icons.local_fire_department),
                      label: const Text('Preparar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: ocupado ? null : onListo,
                    style: FilledButton.styleFrom(
                      backgroundColor: todoMarcado ? Colores.exito : Colores.exito.withValues(alpha: 0.35),
                      foregroundColor: Colores.fondo,
                    ),
                    icon: Icon(todoMarcado ? Icons.done_all : Icons.check),
                    label: Text(grupo.pedidos.length > 1 ? 'Todo listo' : 'Listo'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Renglón con casilla: cocina va marcando lo que ya está hecho.
class _RenglonMarcable extends StatelessWidget {
  const _RenglonMarcable({required this.item, required this.hecho, required this.onTap});

  final PedidoItem item;
  final bool hecho;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: hecho ? 0.45 : 1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: hecho, onChanged: (_) => onTap(), visualDensity: VisualDensity.compact),
            Expanded(child: RenglonItem(item, grande: true)),
          ],
        ),
      ),
    );
  }
}

class _TarjetaExtra extends ConsumerWidget {
  const _TarjetaExtra({required this.extra});

  final ExtraPedido extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marcas = ref.watch(marcasCocinaProvider)['e${extra.clave}'] ?? const <int>{};
    final titulo = extra.tipo == TipoPedido.llevar ? 'Para llevar (mesa ${extra.mesa})' : 'Mesa ${extra.mesa}';
    return Card(
      color: Colores.dorado.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colores.dorado, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.add_alert, color: Colores.dorado),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Extra · $titulo${extra.comensal == null ? '' : ' · ${extra.comensal}'} · #${extra.pedidoId}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colores.dorado),
                  ),
                ),
                Text(tiempoTranscurrido(extra.recibido), style: const TextStyle(color: Colores.apagado)),
              ],
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < extra.items.length; i++)
              _RenglonMarcable(
                item: extra.items[i],
                hecho: marcas.contains(i),
                onTap: () => ref.read(marcasCocinaProvider.notifier).alternar('e${extra.clave}', i),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => ref.read(extrasCocinaProvider.notifier).marcarHecho(extra),
                icon: const Icon(Icons.check),
                label: const Text('Extra terminado'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
