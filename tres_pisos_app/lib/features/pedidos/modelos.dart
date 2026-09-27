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

/// Parte de un platillo dividido entre cuentas (p. ej. la 1 de 3).
typedef Parte = ({int grupo, int parte, int partes});

Parte? leerParte(Object? valor) {
  if (valor is! Map) return null;
  final partes = leerEntero(valor['partes']);
  if (partes < 2) return null;
  return (grupo: leerEntero(valor['grupo']), parte: leerEntero(valor['parte']), partes: partes);
}

class PedidoItem {
  const PedidoItem({
    required this.detalleId,
    required this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.precio,
    this.nota,
    this.extraDesde,
    this.compartido,
  });

  factory PedidoItem.fromJson(Map<String, dynamic> json) => PedidoItem(
        detalleId: leerEntero(json['id']),
        productoId: leerEntero(json['producto_id']),
        nombre: json['nombre']?.toString() ?? 'Producto',
        cantidad: leerEntero(json['cantidad']),
        precio: leerDinero(json['precio']),
        nota: leerTextoOpcional(json['nota']),
        extraDesde: DateTime.tryParse(json['extra_desde']?.toString() ?? '')?.toLocal(),
        compartido: leerParte(json['compartido']),
      );

  final int detalleId;
  final int productoId;
  final String nombre;
  final int cantidad;
  final double precio;

  /// Nota tal como está en el servidor (puede empezar por [prefijoLlevar]).
  final String? nota;

  /// Extra agregado a un pedido ya listo que cocina aún no termina (`extra_desde`).
  final DateTime? extraDesde;

  /// Solo si este renglón es una parte de un platillo dividido entre cuentas.
  final Parte? compartido;

  double get subtotal => precio * cantidad;
  bool get llevar => leerNota(nota).llevar;
  String? get notaVisible => leerNota(nota).nota;
  bool get extraPendiente => extraDesde != null;

  /// Cocina ve un platillo dividido una sola vez: en su parte 1.
  bool get paraCocina => compartido == null || compartido!.parte == 1;

  /// "Compartido 1/3", o `null` si no está dividido.
  String? get etiquetaCompartido => compartido == null ? null : 'Compartido ${compartido!.parte}/${compartido!.partes}';

  Map<String, dynamic> toJson() => {
        'id': detalleId,
        'producto_id': productoId,
        'nombre': nombre,
        'cantidad': cantidad,
        'nota': nota,
        'precio': precio,
        if (extraDesde != null) 'extra_desde': extraDesde!.toUtc().toIso8601String(),
        if (compartido case final c?) 'compartido': {'grupo': c.grupo, 'parte': c.parte, 'partes': c.partes},
      };
}

/// Resultado de mover o dividir productos: las cuentas que cambiaron y, si la
/// de origen se quedó sin productos, su id (la central la borra).
typedef Reparto = ({List<Pedido> pedidos, int? eliminado});

/// Otras cuentas abiertas de la misma mesa a las que se pueden pasar productos de [pedido].
List<Pedido> cuentasHermanas(Iterable<Pedido> activos, Pedido pedido) => [
      for (final p in activos)
        if (p.id != pedido.id && p.mesa == pedido.mesa && p.estado.activo && !p.cobrado) p,
    ];

/// Redondea a centavos para comparar y repartir importes sin errores de coma flotante.
double aCentavos(double valor) => (valor * 100).round() / 100;

/// Cómo se pagó una cuenta: parte en efectivo y parte con tarjeta (o transferencia).
///
/// La central lo guarda en `pago` del pedido como `{efectivo, tarjeta, fecha}`.
/// Los pedidos cobrados antes del pago mixto no traen `pago` (sin desglose).
class Pago {
  const Pago({this.efectivo = 0, this.tarjeta = 0, this.recibido, this.fecha});

  factory Pago.fromJson(Map<String, dynamic> json) => Pago(
        efectivo: leerDinero(json['efectivo']),
        tarjeta: leerDinero(json['tarjeta']),
        recibido: json['recibido'] == null ? null : leerDinero(json['recibido']),
        fecha: DateTime.tryParse(json['fecha']?.toString() ?? '')?.toLocal(),
      );

  /// Suma los pagos de varias cuentas (p. ej. una mesa cobrada junta).
  factory Pago.sumar(Iterable<Pago> pagos) {
    var efectivo = 0.0;
    var tarjeta = 0.0;
    for (final p in pagos) {
      efectivo += p.efectivo;
      tarjeta += p.tarjeta;
    }
    return Pago(efectivo: aCentavos(efectivo), tarjeta: aCentavos(tarjeta));
  }

  /// Parte de la cuenta pagada en efectivo.
  final double efectivo;

  /// Parte de la cuenta pagada con tarjeta o transferencia.
  final double tarjeta;

  /// Billetes que entregó el cliente para la parte en efectivo (solo en la tablet que cobra).
  final double? recibido;
  final DateTime? fecha;

  double get total => aCentavos(efectivo + tarjeta);

  /// El cambio se calcula solo sobre la parte en efectivo.
  double? get cambio => recibido == null ? null : aCentavos(recibido! - efectivo);

  bool get mixto => efectivo >= 0.005 && tarjeta >= 0.005;

  String get metodo => mixto ? 'Mixto' : (tarjeta >= 0.005 ? 'Tarjeta' : 'Efectivo');

  Map<String, dynamic> toJson() => {
        'efectivo': efectivo,
        'tarjeta': tarjeta,
        'recibido': ?recibido,
        if (fecha != null) 'fecha': fecha!.toUtc().toIso8601String(),
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
    this.pago,
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
        pago: json['pago'] is Map<String, dynamic> ? Pago.fromJson(json['pago'] as Map<String, dynamic>) : null,
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

  /// Desglose del cobro; `null` si no se ha cobrado o se cobró antes del pago mixto.
  final Pago? pago;

  /// Ya se cobró, aunque cocina todavía lo esté preparando (el cliente pagó por adelantado).
  bool get cobrado => estado == EstadoPedido.pagado || pago != null;

  int get piezas => items.fold(0, (suma, item) => suma + item.cantidad);

  /// Renglones agregados a un pedido listo que cocina todavía está preparando.
  List<PedidoItem> get extrasPendientes => [for (final i in items) if (i.extraPendiente) i];

  /// Listo, pero con algún extra que cocina aún no termina.
  bool get conExtrasPendientes => estado == EstadoPedido.listo && items.any((i) => i.extraPendiente);

  /// Listo y sin extras pendientes: se puede servir todo.
  bool get paraServir => estado == EstadoPedido.listo && !conExtrasPendientes;

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
        if (pago != null) 'pago': pago!.toJson(),
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
