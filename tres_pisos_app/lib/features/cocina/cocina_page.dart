import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/plataforma.dart';
import '../../core/tema.dart';
import '../../core/widgets.dart';
import '../avisos/avisos.dart';
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

/// Pedidos listos con extras que cocina aún no termina, del extra más antiguo al más nuevo.
List<Pedido> extrasCocina(List<Pedido> activos) {
  DateTime desde(Pedido p) =>
      p.extrasPendientes.map((i) => i.extraDesde!).reduce((a, b) => a.isBefore(b) ? a : b);
  return activos.where((p) => p.conExtrasPendientes).toList()..sort((a, b) => desde(a).compareTo(desde(b)));
}

class CocinaPage extends ConsumerStatefulWidget {
  const CocinaPage({super.key});

  @override
  ConsumerState<CocinaPage> createState() => _CocinaPageState();
}

/// Lo último que se marcó listo, mientras todavía se puede regresar a cocina.
typedef _Deshacer = ({String titulo, List<int> ids, Map<String, Set<int>> marcas});

class _CocinaPageState extends ConsumerState<CocinaPage> {
  /// Tiempo que se ofrece "Deshacer" después de marcar un pedido como listo.
  static const _esperaDeshacer = Duration(seconds: 8);

  late final Timer _reloj;
  late final bool _esCentral;
  late final PantallaCocina _pantalla;
  final _enCurso = <String>{};
  _Deshacer? _deshacer;
  Timer? _relojDeshacer;

  @override
  void initState() {
    super.initState();
    // Refresca los "hace X min" de las tarjetas.
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
    // `ref` no se puede usar en dispose, así que se decide aquí.
    _esCentral = ref.read(centralLocalProvider) != null;
    _pantalla = ref.read(pantallaCocinaProvider);
    unawaited(Plataforma.pantallaEncendida(true));
  }

  @override
  void dispose() {
    _reloj.cancel();
    _relojDeshacer?.cancel();
    _pantalla.fijar(this, visible: false);
    // En la central la pantalla sigue encendida: las demás tablets dependen de ella.
    if (!_esCentral) unawaited(Plataforma.pantallaEncendida(false));
    super.dispose();
  }

  /// Devuelve `true` si la acción terminó sin errores.
  Future<bool> _ejecutar(String clave, Future<void> Function() accion) async {
    setState(() => _enCurso.add(clave));
    try {
      await accion();
      return true;
    } on Object catch (e) {
      if (mounted) mostrarMensaje(context, '$e', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _enCurso.remove(clave));
    }
  }

  /// "Listo" saca el pedido de cocina y avisa al mesero: se confirma antes y,
  /// durante unos segundos, se puede regresar a cocina con "Deshacer".
  Future<void> _marcarListo(GrupoCocina grupo) async {
    final marcas = ref.read(marcasCocinaProvider);
    final sinMarcar = grupo.pedidos.fold(
      0,
      (s, p) => s + p.items.where((i) => i.paraCocina && !(marcas['p${p.id}']?.contains(i.detalleId) ?? false)).length,
    );
    final falta = switch (sinMarcar) {
      0 => '',
      1 => 'Falta 1 producto por marcar. ',
      _ => 'Faltan $sinMarcar productos por marcar. ',
    };
    final varios = grupo.pedidos.length > 1;
    final ok = await confirmar(
      context,
      titulo: '¿${grupo.titulo} ya está ${varios ? 'toda lista' : 'lista'}?',
      mensaje: '${falta}Se avisará al mesero y saldrá de la pantalla de cocina.',
      accion: varios ? 'Sí, todo listo' : 'Sí, está listo',
    );
    if (!ok || !mounted) return;
    final hecho = await _avanzarGrupo(grupo, EstadoPedido.listo);
    if (!hecho || !mounted) return;
    // Lo cobrado por adelantado se cierra al quedar listo: eso ya no se puede regresar.
    final ids = [for (final p in grupo.pedidos) if (!p.cobrado) p.id];
    if (ids.isEmpty) return;
    _relojDeshacer?.cancel();
    setState(() => _deshacer = (
          titulo: grupo.titulo,
          ids: ids,
          marcas: {for (final id in ids) 'p$id': ?marcas['p$id']},
        ));
    _relojDeshacer = Timer(_esperaDeshacer, () {
      if (mounted) setState(() => _deshacer = null);
    });
  }

  /// Regresa a cocina (en preparación) lo que se acaba de marcar listo, con sus casillas.
  Future<void> _deshacerListo() async {
    final deshacer = _deshacer;
    if (deshacer == null) return;
    _relojDeshacer?.cancel();
    setState(() => _deshacer = null);
    final hecho = await _ejecutar(
      'deshacer',
      () => ref.read(pedidosActivosProvider.notifier).cambiarEstadoVarios(deshacer.ids, EstadoPedido.preparando),
    );
    if (!hecho || !mounted) return;
    ref.read(marcasCocinaProvider.notifier).restaurar(deshacer.marcas);
    mostrarMensaje(context, '${deshacer.titulo} volvió a cocina');
  }

  Future<bool> _avanzarGrupo(GrupoCocina grupo, EstadoPedido estado) => _ejecutar(
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
    final deshacer = _deshacer;
    // El aviso de pedido nuevo suena mientras esta pantalla esté a la vista, sea
    // cual sea el rol (la del administrador sigue montada en otra pestaña).
    _pantalla.fijar(this, visible: Visibility.of(context));

    // Las casillas de pedidos que ya salieron de cocina no se necesitan.
    ref.listen(pedidosActivosProvider, (_, siguiente) {
      final activos = siguiente.value;
      if (activos == null) return;
      ref.read(marcasCocinaProvider.notifier).limpiar({
        for (final p in activos.where((p) => p.estado.modificable)) 'p${p.id}',
        for (final p in extrasCocina(activos)) 'x${p.id}',
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
          if (deshacer != null)
            Material(
              color: Colores.exito.withValues(alpha: 0.18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Row(
                  children: [
                    const Icon(Icons.done_all, color: Colores.exito),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${deshacer.titulo} se marcó como lista',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _deshacerListo,
                      icon: const Icon(Icons.undo),
                      label: const Text('Deshacer'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: pedidos.when(
              loading: () => const Cargando(),
              error: (e, _) => ErrorConReintento(
                error: e,
                alReintentar: () => ref.invalidate(pedidosActivosProvider),
              ),
              data: (todos) {
                final grupos = agruparCocina(todos);
                final extras = extrasCocina(todos);
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
                                  itemBuilder: (context, i) => _TarjetaExtra(
                                    pedido: extras[i],
                                    ocupado: _enCurso.contains('x${extras[i].id}'),
                                    onTerminado: () => _ejecutar(
                                      'x${extras[i].id}',
                                      () => ref
                                          .read(pedidosActivosProvider.notifier)
                                          .cambiarEstado(extras[i].id, EstadoPedido.listo),
                                    ),
                                  ),
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
                                  onListo: () => _marcarListo(grupos[i]),
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
    // Las partes 2..N de un platillo dividido no se muestran: es un solo platillo.
    // Las marcas van por id de renglón: mover o dividir no las pasa a otro producto.
    bool visible(Pedido p, int detalleId) => p.items.any((i) => i.detalleId == detalleId && i.paraCocina);
    final renglones = grupo.pedidos.fold(0, (s, p) => s + p.items.where((i) => i.paraCocina).length);
    final hechos =
        grupo.pedidos.fold(0, (s, p) => s + (marcas['p${p.id}']?.where((id) => visible(p, id)).length ?? 0));
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
                // Sin esto la lista de cada tarjeta atrapaba el dedo aunque todo
                // cupiera, y la pantalla de cocina no se podía desplazar.
                primary: false,
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
                          // Ya cobrado por adelantado: no se cancela desde cocina.
                          onPressed: ocupado || p.cobrado ? null : () => onCancelar(p),
                        ),
                      ],
                    ),
                    for (final item in p.items)
                      if (item.paraCocina)
                        _RenglonMarcable(
                          item: item,
                          hecho: marcas['p${p.id}']?.contains(item.detalleId) ?? false,
                          onTap: () => ref.read(marcasCocinaProvider.notifier).alternar('p${p.id}', item.detalleId),
                        ),
                    if (!p.items.any((i) => i.paraCocina))
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Nada que preparar: ya se sirvió o lo prepara otra cuenta',
                          style: TextStyle(color: Colores.apagado, fontStyle: FontStyle.italic),
                        ),
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

/// Productos agregados a un pedido que cocina ya había terminado. Al terminarlos
/// el pedido vuelve a quedar listo (y la mesa, lista para servir).
class _TarjetaExtra extends ConsumerWidget {
  const _TarjetaExtra({required this.pedido, required this.ocupado, required this.onTerminado});

  final Pedido pedido;
  final bool ocupado;
  final VoidCallback onTerminado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = pedido.extrasPendientes;
    final recibido = items.map((i) => i.extraDesde!).reduce((a, b) => a.isBefore(b) ? a : b);
    final marcas = ref.watch(marcasCocinaProvider)['x${pedido.id}'] ?? const <int>{};
    final titulo = etiquetaMesa(pedido.mesa, llevar: pedido.tipo == TipoPedido.llevar);
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
                    'Extra · $titulo${pedido.comensal == null ? '' : ' · ${pedido.comensal}'} · #${pedido.id}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colores.dorado),
                  ),
                ),
                Text(tiempoTranscurrido(recibido), style: const TextStyle(color: Colores.apagado)),
              ],
            ),
            const SizedBox(height: 6),
            for (final item in items)
              _RenglonMarcable(
                item: item,
                hecho: marcas.contains(item.detalleId),
                onTap: () => ref.read(marcasCocinaProvider.notifier).alternar('x${pedido.id}', item.detalleId),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: ocupado ? null : onTerminado,
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
