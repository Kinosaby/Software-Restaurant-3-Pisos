import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pedidos/modelos.dart';

/// Una persona de la mesa con sus productos. Al enviar, cada comensal con
/// productos se convierte en un pedido aparte, igual que en la web.
class Comensal {
  const Comensal({required this.nombre, this.lineas = const []});

  final String nombre;
  final List<LineaCarrito> lineas;

  /// Nombre automático ("C1", "C2"...) que no se manda si solo hay un comensal.
  bool get nombreAutomatico => RegExp(r'^C\d+$').hasMatch(nombre);

  Comensal copyWith({String? nombre, List<LineaCarrito>? lineas}) =>
      Comensal(nombre: nombre ?? this.nombre, lineas: lineas ?? this.lineas);
}

class EstadoCarrito {
  const EstadoCarrito({required this.comensales, required this.activo});

  static const inicial = EstadoCarrito(comensales: [Comensal(nombre: 'C1')], activo: 0);

  final List<Comensal> comensales;
  final int activo;

  Comensal get comensalActivo => comensales[activo];
  List<LineaCarrito> get lineasActivas => comensalActivo.lineas;
  List<LineaCarrito> get todasLasLineas => [for (final c in comensales) ...c.lineas];
  bool get vacio => comensales.every((c) => c.lineas.isEmpty);

  List<Comensal> get porEnviar => [for (final c in comensales) if (c.lineas.isNotEmpty) c];

  /// Nombre con el que se crea el pedido del comensal. Con un solo comensal
  /// solo se manda si se cambió a mano (p. ej. el cliente de un pedido para llevar).
  String? nombreParaEnvio(Comensal comensal) =>
      comensales.length == 1 && comensal.nombreAutomatico ? null : comensal.nombre;

  EstadoCarrito copyWith({List<Comensal>? comensales, int? activo}) =>
      EstadoCarrito(comensales: comensales ?? this.comensales, activo: activo ?? this.activo);
}

/// Productos elegidos en la pantalla de captura. Se descarta al salir de la pantalla.
final carritoProvider = NotifierProvider.autoDispose<Carrito, EstadoCarrito>(Carrito.new);

class Carrito extends Notifier<EstadoCarrito> {
  @override
  EstadoCarrito build() => EstadoCarrito.inicial;

  int cantidadDe(int productoId) {
    for (final linea in state.lineasActivas) {
      if (linea.producto.id == productoId) return linea.cantidad;
    }
    return 0;
  }

  /// Aplica `cambio` a las líneas del comensal `en` (por defecto, el activo).
  void _editar(int? en, List<LineaCarrito> Function(List<LineaCarrito>) cambio) {
    final indice = en ?? state.activo;
    final comensales = [...state.comensales];
    comensales[indice] = comensales[indice].copyWith(lineas: cambio(comensales[indice].lineas));
    state = state.copyWith(comensales: comensales);
  }

  void agregar(Producto producto) {
    if (cantidadDe(producto.id) == 0) {
      _editar(null, (lineas) => [...lineas, LineaCarrito(producto: producto)]);
    } else {
      cambiarCantidad(producto.id, 1);
    }
  }

  /// Suma `delta` a la cantidad; si llega a cero, quita la línea.
  void cambiarCantidad(int productoId, int delta, {int? en}) {
    _editar(en, (lineas) => [
          for (final linea in lineas)
            if (linea.producto.id != productoId)
              linea
            else if (linea.cantidad + delta > 0)
              linea.copyWith(cantidad: linea.cantidad + delta),
        ]);
  }

  void fijarNota(int productoId, String nota, {int? en}) {
    final limpia = nota.trim();
    _editar(en, (lineas) => [
          for (final linea in lineas)
            if (linea.producto.id == productoId) linea.copyWith(nota: limpia, borrarNota: limpia.isEmpty) else linea,
        ]);
  }

  void alternarLlevar(int productoId, {int? en}) {
    _editar(en, (lineas) => [
          for (final linea in lineas)
            if (linea.producto.id == productoId) linea.copyWith(llevar: !linea.llevar) else linea,
        ]);
  }

  /// Carga una plantilla (p. ej. "repetir pedido"): reemplaza al comensal activo.
  void cargar(List<LineaCarrito> lineas) => _editar(null, (_) => [...lineas]);

  void agregarComensal() {
    final comensales = [...state.comensales, Comensal(nombre: 'C${state.comensales.length + 1}')];
    state = EstadoCarrito(comensales: comensales, activo: comensales.length - 1);
  }

  void seleccionarComensal(int indice) => state = state.copyWith(activo: indice);

  void renombrarComensal(int indice, String nombre) {
    final limpio = nombre.trim();
    final comensales = [...state.comensales];
    comensales[indice] = comensales[indice].copyWith(nombre: limpio.isEmpty ? 'C${indice + 1}' : limpio);
    state = state.copyWith(comensales: comensales);
  }

  /// Quita un comensal y renumera los que conservan nombre automático.
  void quitarComensal(int indice) {
    if (state.comensales.length == 1) {
      state = EstadoCarrito.inicial;
      return;
    }
    final restantes = [...state.comensales]..removeAt(indice);
    final renumerados = [
      for (var i = 0; i < restantes.length; i++)
        restantes[i].nombreAutomatico ? restantes[i].copyWith(nombre: 'C${i + 1}') : restantes[i],
    ];
    final activo = state.activo >= restantes.length ? restantes.length - 1 : state.activo;
    state = EstadoCarrito(comensales: renumerados, activo: activo);
  }

  /// Vacía un comensal ya enviado sin quitarlo, para que un reintento no lo duplique.
  void marcarEnviado(Comensal comensal) {
    state = state.copyWith(comensales: [
      for (final c in state.comensales) identical(c, comensal) ? c.copyWith(lineas: const []) : c,
    ]);
  }
}

/// Pedido de partida para la captura ("repetir pedido").
class PlantillaPedido {
  const PlantillaPedido({required this.lineas, this.mesa, this.tipo = TipoPedido.aqui, this.comensal});

  /// Arma la plantilla con los productos de un pedido anterior que siguen en el menú,
  /// al precio actual. Los que ya no existen o están desactivados se omiten.
  factory PlantillaPedido.desde(Pedido pedido, List<Producto> catalogo) {
    final porId = {for (final p in catalogo) p.id: p};
    return PlantillaPedido(
      mesa: pedido.tipo == TipoPedido.aqui ? pedido.mesa : null,
      tipo: pedido.tipo,
      comensal: pedido.comensal,
      lineas: [
        for (final i in pedido.items)
          if (porId[i.productoId] case final producto?)
            LineaCarrito(producto: producto, cantidad: i.cantidad, nota: i.notaVisible, llevar: i.llevar),
      ],
    );
  }

  final List<LineaCarrito> lineas;
  final int? mesa;
  final TipoPedido tipo;
  final String? comensal;
}

extension ResumenCarrito on List<LineaCarrito> {
  double get total => fold(0, (suma, l) => suma + l.subtotal);
  int get piezas => fold(0, (suma, l) => suma + l.cantidad);
}
