import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'modelos.dart';
import 'pedidos_repository.dart';
import 'tiempo_real.dart';

/// Catálogo de productos activos, ordenado por categoría y nombre (así lo devuelve el backend).
final productosProvider = FutureProvider.autoDispose<List<Producto>>((ref) async {
  final productos = await ref.watch(pedidosRepositoryProvider).productos();
  return productos.where((p) => p.activo).toList();
});

// autoDispose: al cerrar sesión ninguna pantalla lo escucha y se libera junto con el socket.
final pedidosActivosProvider =
    AsyncNotifierProvider.autoDispose<PedidosActivos, List<Pedido>>(PedidosActivos.new);

/// Pedidos pendientes, en preparación y listos, sincronizados en tiempo real.
/// Orden FIFO: el más antiguo primero, igual que en el backend.
class PedidosActivos extends AsyncNotifier<List<Pedido>> {
  @override
  Future<List<Pedido>> build() async {
    final repo = ref.watch(pedidosRepositoryProvider);
    final suscripcion = ref.watch(tiempoRealProvider).eventos.listen(_alEvento);
    ref.onDispose(suscripcion.cancel);
    return ordenarPedidos(await repo.pedidosActivos());
  }

  void _alEvento(EventoTiempoReal evento) {
    switch (evento) {
      case PedidoCambiado(:final pedido):
        aplicar(pedido);
      case ExtraRecibido():
      // El backend no reenvía el pedido completo al añadir extras, y tras una
      // reconexión pudimos perder eventos: en ambos casos recargamos.
      case Conectado():
        unawaited(recargar());
    }
  }

  /// Inserta o reemplaza un pedido; si ya no está activo, lo quita de la lista.
  void aplicar(Pedido pedido) {
    final actuales = state.value;
    if (actuales == null) return;
    state = AsyncData(reemplazarPedido(actuales, pedido));
  }

  /// Recarga sin tapar la lista actual con un indicador de carga.
  Future<void> recargar() async {
    try {
      final pedidos = await ref.read(pedidosRepositoryProvider).pedidosActivos();
      if (!ref.mounted) return;
      state = AsyncData(ordenarPedidos(pedidos));
    } on Object catch (e, st) {
      if (!ref.mounted) return;
      // Si ya teníamos datos, preferimos mostrarlos a mostrar un error por un fallo puntual.
      if (!state.hasValue) state = AsyncError(e, st);
    }
  }

  Future<Pedido> crear({
    required int mesa,
    required TipoPedido tipo,
    String? comensal,
    required List<LineaCarrito> lineas,
  }) =>
      _ejecutar((repo) => repo.crear(mesa: mesa, tipo: tipo, comensal: comensal, lineas: lineas));

  Future<Pedido> agregar(int pedidoId, List<LineaCarrito> lineas) =>
      _ejecutar((repo) => repo.agregar(pedidoId, lineas));

  Future<Pedido> editar(
    int pedidoId, {
    List<CambioItem> items = const [],
    int? mesa,
    TipoPedido? tipo,
    Opcional<String>? comensal,
  }) =>
      _ejecutar((repo) => repo.editar(pedidoId, items: items, mesa: mesa, tipo: tipo, comensal: comensal));

  Future<Pedido> cambiarEstado(int pedidoId, EstadoPedido estado) =>
      _ejecutar((repo) => repo.cambiarEstado(pedidoId, estado));

  Future<Pedido> cancelar(int pedidoId) => _ejecutar((repo) => repo.cancelar(pedidoId));

  Future<Pedido> _ejecutar(Future<Pedido> Function(PedidosRepository repo) accion) async {
    final pedido = await accion(ref.read(pedidosRepositoryProvider));
    if (ref.mounted) aplicar(pedido);
    return pedido;
  }
}

List<Pedido> ordenarPedidos(Iterable<Pedido> pedidos) {
  final lista = pedidos.toList()
    ..sort((a, b) {
      final porFecha = a.creadoEn.compareTo(b.creadoEn);
      return porFecha != 0 ? porFecha : a.id.compareTo(b.id);
    });
  return lista;
}

List<Pedido> reemplazarPedido(List<Pedido> actuales, Pedido pedido) => ordenarPedidos([
      for (final p in actuales)
        if (p.id != pedido.id) p,
      if (pedido.estado.activo) pedido,
    ]);

final extrasCocinaProvider =
    NotifierProvider.autoDispose<ExtrasCocina, List<ExtraPedido>>(ExtrasCocina.new);

/// Extras que llegan a cocina para pedidos ya terminados. El backend no los guarda
/// por separado, así que viven en memoria hasta que cocina los marca como hechos.
class ExtrasCocina extends Notifier<List<ExtraPedido>> {
  @override
  List<ExtraPedido> build() {
    final suscripcion = ref.watch(tiempoRealProvider).eventos.listen((evento) {
      if (evento is ExtraRecibido) state = [...state, evento.extra];
    });
    ref.onDispose(suscripcion.cancel);
    return const [];
  }

  void marcarHecho(ExtraPedido extra) {
    state = [for (final e in state) if (!identical(e, extra)) e];
  }
}
