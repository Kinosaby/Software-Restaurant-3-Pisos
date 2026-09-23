/// PostgreSQL devuelve NUMERIC como texto ("45.00"); aceptamos número o texto.
double leerDinero(Object? valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor?.toString() ?? '') ?? 0;
}

int leerEntero(Object? valor) {
  if (valor is num) return valor.toInt();
  return int.tryParse(valor?.toString() ?? '') ?? 0;
}

String? leerTextoOpcional(Object? valor) {
  final texto = valor?.toString().trim();
  return (texto == null || texto.isEmpty) ? null : texto;
}

class Producto {
  const Producto({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.categoria,
    required this.activo,
  });

  factory Producto.fromJson(Map<String, dynamic> json) => Producto(
        id: leerEntero(json['id']),
        nombre: json['nombre']?.toString() ?? '',
        precio: leerDinero(json['precio']),
        categoria: leerTextoOpcional(json['categoria']) ?? 'General',
        activo: json['activo'] != false,
      );

  final int id;
  final String nombre;
  final double precio;
  final String categoria;
  final bool activo;
}

enum EstadoPedido {
  pendiente('Pendiente'),
  preparando('Preparando'),
  listo('Listo'),
  pagado('Pagado'),
  cancelado('Cancelado');

  const EstadoPedido(this.etiqueta);
  final String etiqueta;

  static EstadoPedido desde(String? valor) =>
      EstadoPedido.values.firstWhere((e) => e.name == valor, orElse: () => EstadoPedido.pendiente);

  /// Pedidos que siguen en el salón o en cocina.
  bool get activo => this != pagado && this != cancelado;

  /// Solo se pueden editar o cancelar mientras cocina no los ha terminado.
  bool get modificable => this == pendiente || this == preparando;
}

enum TipoPedido {
  aqui('Para aquí'),
  llevar('Para llevar');

  const TipoPedido(this.etiqueta);
  final String etiqueta;

  static TipoPedido desde(String? valor) => valor == 'llevar' ? llevar : aqui;
}

class PedidoItem {
  const PedidoItem({
    required this.detalleId,
    required this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.precio,
    this.nota,
  });

  factory PedidoItem.fromJson(Map<String, dynamic> json) => PedidoItem(
        detalleId: leerEntero(json['id']),
        productoId: leerEntero(json['producto_id']),
        nombre: json['nombre']?.toString() ?? 'Producto',
        cantidad: leerEntero(json['cantidad']),
        precio: leerDinero(json['precio']),
        nota: leerTextoOpcional(json['nota']),
      );

  final int detalleId;
  final int productoId;
  final String nombre;
  final int cantidad;
  final double precio;
  final String? nota;

  double get subtotal => precio * cantidad;
}

class Pedido {
  const Pedido({
    required this.id,
    required this.mesa,
    required this.estado,
    required this.tipo,
    required this.total,
    required this.items,
    required this.creadoEn,
    this.comensal,
  });

  factory Pedido.fromJson(Map<String, dynamic> json) => Pedido(
        id: leerEntero(json['id']),
        mesa: leerEntero(json['mesa']),
        estado: EstadoPedido.desde(json['estado']?.toString()),
        tipo: TipoPedido.desde(json['tipo']?.toString()),
        total: leerDinero(json['total']),
        comensal: leerTextoOpcional(json['comensal']),
        creadoEn: DateTime.tryParse(json['creado_en']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        items: [
          for (final item in (json['productos'] as List? ?? const []))
            if (item is Map<String, dynamic>) PedidoItem.fromJson(item),
        ],
      );

  final int id;
  final int mesa;
  final EstadoPedido estado;
  final TipoPedido tipo;
  final double total;
  final String? comensal;
  final DateTime creadoEn;
  final List<PedidoItem> items;

  int get piezas => items.fold(0, (suma, item) => suma + item.cantidad);

  String get titulo {
    final base = tipo == TipoPedido.llevar ? 'Para llevar' : 'Mesa $mesa';
    return comensal == null ? base : '$base · $comensal';
  }
}

/// Productos añadidos a un pedido que cocina ya había terminado (`extra_pedido`).
class ExtraPedido {
  const ExtraPedido({
    required this.pedidoId,
    required this.mesa,
    required this.tipo,
    required this.items,
    required this.recibido,
  });

  factory ExtraPedido.fromJson(Map<String, dynamic> json, {DateTime? recibido}) => ExtraPedido(
        pedidoId: leerEntero(json['pedido_id']),
        mesa: leerEntero(json['mesa']),
        tipo: TipoPedido.desde(json['tipo']?.toString()),
        recibido: recibido ?? DateTime.now(),
        items: [
          for (final item in (json['items'] as List? ?? const []))
            if (item is Map<String, dynamic>) PedidoItem.fromJson(item),
        ],
      );

  final int pedidoId;
  final int mesa;
  final TipoPedido tipo;
  final List<PedidoItem> items;
  final DateTime recibido;
}

/// Cambio sobre un renglón existente del pedido (`items` de `PATCH /editar`).
class CambioItem {
  const CambioItem({required this.detalleId, required this.cantidad, this.nota});

  final int detalleId;

  /// 0 quita el renglón del pedido.
  final int cantidad;
  final String? nota;

  Map<String, dynamic> toJson() => {'detalle_id': detalleId, 'cantidad': cantidad, 'nota': nota};
}

/// Distingue "no cambiar" (`null`) de "cambiar a null" (`Opcional(null)`).
class Opcional<T> {
  const Opcional(this.valor);
  final T? valor;
}

/// Línea del pedido que el mesero está armando, antes de enviarlo.
class LineaCarrito {
  const LineaCarrito({required this.producto, this.cantidad = 1, this.nota});

  final Producto producto;
  final int cantidad;
  final String? nota;

  double get subtotal => producto.precio * cantidad;

  LineaCarrito copyWith({int? cantidad, String? nota, bool borrarNota = false}) => LineaCarrito(
        producto: producto,
        cantidad: cantidad ?? this.cantidad,
        nota: borrarNota ? null : (nota ?? this.nota),
      );

  Map<String, dynamic> toJson() => {
        'producto_id': producto.id,
        'cantidad': cantidad,
        if (nota != null) 'nota': nota,
      };
}
