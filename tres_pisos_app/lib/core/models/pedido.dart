// lib/core/models/pedido.dart

class DetallePedido {
  final int    productoId;
  final String nombre;
  final int    cantidad;
  final double precio;
  final String nota;

  DetallePedido({
    required this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.precio,
    required this.nota,
  });

  factory DetallePedido.fromJson(Map<String, dynamic> j) => DetallePedido(
    productoId: j['producto_id'] ?? 0,
    nombre:     j['nombre']      ?? '',
    cantidad:   j['cantidad']    ?? 1,
    precio:     double.tryParse(j['precio'].toString()) ?? 0,
    nota:       j['nota']        ?? '',
  );
}

class Pedido {
  final int              id;
  final int              mesa;
  final String           estado;
  final double           total;
  final DateTime         creadoEn;
  final List<DetallePedido> productos;

  Pedido({
    required this.id,
    required this.mesa,
    required this.estado,
    required this.total,
    required this.creadoEn,
    required this.productos,
  });

  factory Pedido.fromJson(Map<String, dynamic> j) {
    final rawProds = j['productos'];
    List<DetallePedido> prods = [];
    if (rawProds is List) {
      prods = rawProds.map((p) => DetallePedido.fromJson(p as Map<String, dynamic>)).toList();
    }
    return Pedido(
      id:        j['id'],
      mesa:      j['mesa']  ?? 0,
      estado:    j['estado'] ?? 'pendiente',
      total:     double.tryParse(j['total'].toString()) ?? 0,
      creadoEn:  DateTime.tryParse(j['creado_en'] ?? '') ?? DateTime.now(),
      productos: prods,
    );
  }

  bool get isPendiente  => estado == 'pendiente';
  bool get isPreparando => estado == 'preparando';
  bool get isListo      => estado == 'listo';
  bool get isPagado     => estado == 'pagado';
  bool get isCancelado  => estado == 'cancelado';
}

/// Ítem en el carrito local (antes de enviar al servidor)
class CartItem {
  final int    productoId;
  final String nombre;
  final double precio;
  int          cantidad;
  String       nota;

  CartItem({
    required this.productoId,
    required this.nombre,
    required this.precio,
    this.cantidad = 1,
    this.nota     = '',
  });

  double get subtotal => precio * cantidad;
}
