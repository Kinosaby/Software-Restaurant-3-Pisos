import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../auth/auth_controller.dart';
import 'modelos.dart';

final pedidosRepositoryProvider = Provider<PedidosRepository>(
  (ref) => PedidosRepository(ref.watch(apiClientProvider)),
);

/// Endpoints `/api/productos` y `/api/pedidos` del backend.
class PedidosRepository {
  PedidosRepository(this._api);

  final ApiClient _api;

  Future<List<Producto>> productos() async {
    final datos = await _api.get('/api/productos');
    return [
      for (final p in (datos['productos'] as List? ?? const []))
        if (p is Map<String, dynamic>) Producto.fromJson(p),
    ];
  }

  Future<List<Pedido>> pedidos({EstadoPedido? estado}) async {
    final datos = await _api.get('/api/pedidos', query: {if (estado != null) 'estado': estado.name});
    return [
      for (final p in (datos['pedidos'] as List? ?? const []))
        if (p is Map<String, dynamic>) Pedido.fromJson(p),
    ];
  }

  /// El backend solo filtra por un estado a la vez, así que pedimos los activos en paralelo.
  Future<List<Pedido>> pedidosActivos() async {
    final grupos = await Future.wait([
      for (final estado in EstadoPedido.values.where((e) => e.activo)) pedidos(estado: estado),
    ]);
    return grupos.expand((g) => g).toList();
  }

  Future<Pedido> crear({
    required int mesa,
    required TipoPedido tipo,
    String? comensal,
    required List<LineaCarrito> lineas,
  }) async {
    final datos = await _api.post('/api/pedidos', {
      'mesa': mesa,
      'tipo': tipo.name,
      if (comensal != null && comensal.trim().isNotEmpty) 'comensal': comensal.trim(),
      'productos': [for (final l in lineas) l.toJson()],
    });
    return _pedido(datos);
  }

  Future<Pedido> agregar(int pedidoId, List<LineaCarrito> lineas) async {
    final datos = await _api.patch('/api/pedidos/$pedidoId/agregar', {
      'productos': [for (final l in lineas) l.toJson()],
    });
    return _pedido(datos);
  }

  /// `PATCH /editar`: solo se mandan los campos que cambiaron. Una cantidad 0
  /// quita el item. El backend reescribe la nota de cada item enviado, así que
  /// siempre se manda la nota que debe quedar.
  Future<Pedido> editar(
    int pedidoId, {
    List<CambioItem> items = const [],
    int? mesa,
    TipoPedido? tipo,
    Opcional<String>? comensal,
  }) async {
    final datos = await _api.patch('/api/pedidos/$pedidoId/editar', {
      if (items.isNotEmpty) 'items': [for (final i in items) i.toJson()],
      'mesa': ?mesa,
      if (tipo != null) 'tipo': tipo.name,
      if (comensal != null) 'comensal': comensal.valor,
    });
    return _pedido(datos);
  }

  Future<Pedido> cambiarEstado(int pedidoId, EstadoPedido estado) async {
    final datos = await _api.put('/api/pedidos/$pedidoId/estado', {'estado': estado.name});
    return _pedido(datos);
  }

  Future<Pedido> cancelar(int pedidoId) async {
    final datos = await _api.patch('/api/pedidos/$pedidoId/cancelar');
    return _pedido(datos);
  }

  Pedido _pedido(Map<String, dynamic> datos) {
    final pedido = datos['pedido'];
    if (pedido is! Map<String, dynamic>) {
      throw ApiException('El servidor no devolvió el pedido.');
    }
    return Pedido.fromJson(pedido);
  }
}
