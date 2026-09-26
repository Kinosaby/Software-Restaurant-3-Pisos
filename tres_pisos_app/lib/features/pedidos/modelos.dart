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

/// Prefijo con el que la web marca un producto para llevar dentro de un pedido para aquí.
const prefijoLlevar = '[LLEVAR]';

/// Separa la marca de "para llevar" del texto de la nota.
({bool llevar, String? nota}) leerNota(String? nota) {
  if (nota == null || !nota.startsWith(prefijoLlevar)) return (llevar: false, nota: nota);
  return (llevar: true, nota: leerTextoOpcional(nota.substring(prefijoLlevar.length)));
}

/// Inverso de [leerNota]: la nota tal como la guarda el servidor.
String? componerNota({required bool llevar, String? nota}) {
  final texto = leerTextoOpcional(nota);
  if (!llevar) return texto;
  return texto == null ? prefijoLlevar : '$prefijoLlevar $texto';
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

  Map<String, dynamic> toJson() =>
      {'id': id, 'nombre': nombre, 'precio': precio, 'categoria': categoria, 'activo': activo};
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

  /// Nota tal como está en el servidor (puede empezar por [prefijoLlevar]).
  final String? nota;

  double get subtotal => precio * cantidad;
  bool get llevar => leerNota(nota).llevar;
  String? get notaVisible => leerNota(nota).nota;

  Map<String, dynamic> toJson() => {
        'id': detalleId,
        'producto_id': productoId,
        'nombre': nombre,
        'cantidad': cantidad,
        'nota': nota,
        'precio': precio,
      };
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
    this.usuarioId,
    this.mesero,
  });

  factory Pedido.fromJson(Map<String, dynamic> json) => Pedido(
        id: leerEntero(json['id']),
        mesa: leerEntero(json['mesa']),
        estado: EstadoPedido.desde(json['estado']?.toString()),
        tipo: TipoPedido.desde(json['tipo']?.toString()),
        total: leerDinero(json['total']),
        comensal: leerTextoOpcional(json['comensal']),
        usuarioId: json['usuario_id'] == null ? null : leerEntero(json['usuario_id']),
        mesero: leerTextoOpcional(json['mesero']),
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

  /// Quién tomó el pedido (para avisarle cuando esté listo).
  final int? usuarioId;
  final String? mesero;
  final DateTime creadoEn;
  final List<PedidoItem> items;

  int get piezas => items.fold(0, (suma, item) => suma + item.cantidad);

  String get titulo {
    final base = tipo == TipoPedido.llevar ? 'Para llevar' : 'Mesa $mesa';
    return comensal == null ? base : '$base · $comensal';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mesa': mesa,
        'estado': estado.name,
        'tipo': tipo.name,
        'total': total,
        'comensal': comensal,
        'usuario_id': usuarioId,
        'mesero': mesero,
        'creado_en': creadoEn.toUtc().toIso8601String(),
        'productos': [for (final i in items) i.toJson()],
      };
}

/// Productos añadidos a un pedido que cocina ya había terminado (`extra_pedido`).
class ExtraPedido {
  const ExtraPedido({
    required this.pedidoId,
    required this.mesa,
    required this.tipo,
    required this.items,
    required this.recibido,
    this.comensal,
  });

  factory ExtraPedido.fromJson(Map<String, dynamic> json, {DateTime? recibido}) => ExtraPedido(
        pedidoId: leerEntero(json['pedido_id']),
        mesa: leerEntero(json['mesa']),
        tipo: TipoPedido.desde(json['tipo']?.toString()),
        comensal: leerTextoOpcional(json['comensal']),
        recibido: recibido ?? DateTime.tryParse(json['recibido']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        items: [
          for (final item in (json['items'] as List? ?? const []))
            if (item is Map<String, dynamic>) PedidoItem.fromJson(item),
        ],
      );

  final int pedidoId;
  final int mesa;
  final TipoPedido tipo;
  final String? comensal;
  final List<PedidoItem> items;
  final DateTime recibido;

  /// Identifica el extra en el almacenamiento local de cocina.
  String get clave => '$pedidoId-${recibido.microsecondsSinceEpoch}';

  Map<String, dynamic> toJson() => {
        'pedido_id': pedidoId,
        'mesa': mesa,
        'tipo': tipo.name,
        'comensal': comensal,
        'recibido': recibido.toUtc().toIso8601String(),
        'items': [for (final i in items) i.toJson()],
      };
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
  const LineaCarrito({required this.producto, this.cantidad = 1, this.nota, this.llevar = false});

  final Producto producto;
  final int cantidad;

  /// Solo el texto que escribe el mesero; la marca de llevar va aparte.
  final String? nota;

  /// Este producto se empaca para llevar aunque el pedido sea para aquí.
  final bool llevar;

  double get subtotal => producto.precio * cantidad;

  LineaCarrito copyWith({int? cantidad, String? nota, bool borrarNota = false, bool? llevar}) => LineaCarrito(
        producto: producto,
        cantidad: cantidad ?? this.cantidad,
        nota: borrarNota ? null : (nota ?? this.nota),
        llevar: llevar ?? this.llevar,
      );

  Map<String, dynamic> toJson() {
    final nota = componerNota(llevar: llevar, nota: this.nota);
    return {'producto_id': producto.id, 'cantidad': cantidad, 'nota': ?nota};
  }
}
