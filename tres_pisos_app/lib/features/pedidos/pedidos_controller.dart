import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../central/seguridad.dart';
import '../../core/almacen_local.dart';
import '../../core/api_client.dart';
import '../../core/formato.dart';
import '../auth/auth_controller.dart';
import 'modelos.dart';
import 'pedidos_repository.dart';
import 'tiempo_real.dart';

// ── Estado de la conexión ───────────────────────────────────

/// `true` cuando la última petición no llegó al servidor y se muestran datos guardados.
final sinConexionProvider = NotifierProvider<SinConexion, bool>(SinConexion.new);

class SinConexion extends Notifier<bool> {
  @override
  bool build() => false;

  void fijar(bool valor) {
    if (state != valor) state = valor;
  }
}

// ── Catálogo ────────────────────────────────────────────────

/// Catálogo de productos activos. Sin conexión usa el último que se descargó.
final productosProvider = FutureProvider.autoDispose<List<Producto>>((ref) async {
  final repo = ref.watch(pedidosRepositoryProvider);
  final almacen = ref.watch(almacenLocalProvider);
  // Se toma antes de esperar: si la pantalla se cierra durante la descarga, este
  // provider se libera y ya no puede usar `ref`.
  final sinConexion = ref.read(sinConexionProvider.notifier);
  List<Producto> productos;
  try {
    productos = await repo.productos();
    unawaited(almacen.guardarLista('productos', [for (final p in productos) p.toJson()]));
    sinConexion.fijar(false);
  } on ApiException catch (e) {
    final guardados = almacen.lista('productos');
    if (!e.sinConexion || guardados == null) rethrow;
    sinConexion.fijar(true);
    productos = [for (final p in guardados) Producto.fromJson(p)];
  }
  return productos.where((p) => p.activo).toList();
});

// ── Pedidos activos ─────────────────────────────────────────

/// Resultado de mandar un pedido: llegó, o quedó en la cola para enviarse al reconectar.
sealed class ResultadoEnvio {
  const ResultadoEnvio();
}

class Enviado extends ResultadoEnvio {
  const Enviado(this.pedido);
  final Pedido pedido;
}

class EnCola extends ResultadoEnvio {
  const EnCola(this.envio);
  final EnvioPendiente envio;
}

// autoDispose: al cerrar sesión ninguna pantalla lo escucha y se libera junto con el socket.
final pedidosActivosProvider =
    AsyncNotifierProvider.autoDispose<PedidosActivos, List<Pedido>>(PedidosActivos.new);

/// Pedidos pendientes, en preparación y listos, sincronizados en tiempo real.
/// Orden FIFO: el más antiguo primero, igual que en el backend. Sin conexión
/// muestra la última copia guardada.
class PedidosActivos extends AsyncNotifier<List<Pedido>> {
  @override
  Future<List<Pedido>> build() async {
    final repo = ref.watch(pedidosRepositoryProvider);
    final almacen = ref.watch(almacenLocalProvider);
    final sinConexion = ref.read(sinConexionProvider.notifier);
    final suscripcion = ref.watch(tiempoRealProvider).eventos.listen(_alEvento);
    ref.onDispose(suscripcion.cancel);
    try {
      final pedidos = ordenarPedidos(await repo.pedidosActivos());
      unawaited(almacen.guardarLista('pedidos', [for (final p in pedidos) p.toJson()]));
      sinConexion.fijar(false);
      return pedidos;
    } on ApiException catch (e) {
      final copia = almacen.lista('pedidos');
      if (!e.sinConexion || copia == null) rethrow;
      sinConexion.fijar(true);
      return ordenarPedidos([for (final p in copia) Pedido.fromJson(p)]);
    }
  }

  void _guardarCopia(List<Pedido> pedidos) =>
      unawaited(ref.read(almacenLocalProvider).guardarLista('pedidos', [for (final p in pedidos) p.toJson()]));

  void _alEvento(EventoTiempoReal evento) {
    switch (evento) {
      case PedidoCambiado(:final pedido):
        aplicar(pedido);
      case PedidoEliminado(:final id):
        final actuales = state.value;
        if (actuales != null) _fijar([for (final p in actuales) if (p.id != id) p]);
      // La central manda también `pedido_actualizado` con el pedido completo.
      case ExtraRecibido():
        break;
      // Tras una reconexión pudimos perder eventos: recargamos.
      case Conectado():
        unawaited(recargar());
    }
  }

  void _fijar(List<Pedido> pedidos) {
    state = AsyncData(pedidos);
    _guardarCopia(pedidos);
  }

  /// Inserta o reemplaza un pedido; si ya no está activo, lo quita de la lista.
  void aplicar(Pedido pedido) {
    final actuales = state.value;
    if (actuales == null) return;
    _fijar(reemplazarPedido(actuales, pedido));
  }

  /// Recarga sin tapar la lista actual con un indicador de carga.
  Future<void> recargar() async {
    try {
      final pedidos = await ref.read(pedidosRepositoryProvider).pedidosActivos();
      if (!ref.mounted) return;
      _fijar(ordenarPedidos(pedidos));
      ref.read(sinConexionProvider.notifier).fijar(false);
    } on Object catch (e, st) {
      if (!ref.mounted) return;
      if (e is ApiException && e.sinConexion) ref.read(sinConexionProvider.notifier).fijar(true);
      // Si ya teníamos datos, preferimos mostrarlos a mostrar un error por un fallo puntual.
      if (!state.hasValue) state = AsyncError(e, st);
    }
  }

  /// Crea un pedido. Si no hay conexión lo deja en la cola para enviarlo después.
  Future<ResultadoEnvio> crear({
    required int mesa,
    required TipoPedido tipo,
    String? comensal,
    required List<LineaCarrito> lineas,
  }) {
    final cuerpo = PedidosRepository.cuerpoCrear(mesa: mesa, tipo: tipo, comensal: comensal, lineas: lineas);
    final base = tipo == TipoPedido.llevar ? 'Para llevar (mesa $mesa)' : 'Mesa $mesa';
    return _enviar(
      tipo: 'crear',
      cuerpo: cuerpo,
      lineas: lineas,
      resumen: comensal == null || comensal.isEmpty ? base : '$base · $comensal',
    );
  }

  Future<ResultadoEnvio> agregar(Pedido pedido, List<LineaCarrito> lineas) => _enviar(
        tipo: 'agregar',
        pedidoId: pedido.id,
        cuerpo: PedidosRepository.cuerpoAgregar(lineas),
        lineas: lineas,
        resumen: 'Agregar a ${pedido.titulo} (#${pedido.id})',
      );

  Future<ResultadoEnvio> _enviar({
    required String tipo,
    int? pedidoId,
    required Map<String, dynamic> cuerpo,
    required List<LineaCarrito> lineas,
    required String resumen,
  }) async {
    final operacion = idAleatorio();
    // Todo lo que se usa después de esperar se toma antes, por si el provider se libera entretanto.
    final repo = ref.read(pedidosRepositoryProvider);
    final favoritos = ref.read(favoritosProvider.notifier);
    final cola = ref.read(colaEnviosProvider.notifier);
    final sinConexion = ref.read(sinConexionProvider.notifier);
    try {
      final pedido = tipo == 'crear'
          ? await repo.crear(cuerpo, operacion: operacion)
          : await repo.agregar(pedidoId!, cuerpo, operacion: operacion);
      if (ref.mounted) aplicar(pedido);
      favoritos.registrar(cuerpo);
      return Enviado(pedido);
    } on ApiException catch (e) {
      if (!e.sinConexion) rethrow;
      // Aunque la petición hubiera llegado, reintentarla es seguro: la central
      // reconoce la operación y no la procesa dos veces.
      sinConexion.fijar(true);
      final envio = EnvioPendiente(
        operacion: operacion,
        tipo: tipo,
        pedidoId: pedidoId,
        cuerpo: cuerpo,
        creado: DateTime.now(),
        resumen: '$resumen · ${lineas.fold(0, (s, l) => s + l.cantidad)} productos',
        total: lineas.fold(0, (s, l) => s + l.subtotal),
      );
      await cola.encolar(envio);
      return EnCola(envio);
    }
  }

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

  /// Cambia varios pedidos a la vez (p. ej. "todo listo" de una mesa o cobrar la mesa completa).
  Future<void> cambiarEstadoVarios(Iterable<int> ids, EstadoPedido estado) async {
    for (final id in ids) {
      await cambiarEstado(id, estado);
    }
  }

  Future<Pedido> cancelar(int pedidoId) => _ejecutar((repo) => repo.cancelar(pedidoId));

  Future<Pedido> _ejecutar(Future<Pedido> Function(PedidosRepository repo) accion) async {
    try {
      final pedido = await accion(ref.read(pedidosRepositoryProvider));
      if (ref.mounted) aplicar(pedido);
      return pedido;
    } on ApiException catch (e) {
      // Cobros y cambios de estado no se encolan: deben confirmarse en el momento.
      if (e.sinConexion) {
        throw ApiException('Sin conexión con la central: los cobros y cambios de estado necesitan '
            'que la tablet de cocina esté encendida y en el mismo Wi-Fi.');
      }
      rethrow;
    }
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

/// Pedidos cobrados hoy (para el historial del día del mesero y "repetir pedido").
final pagadosHoyProvider = FutureProvider.autoDispose<List<Pedido>>((ref) async {
  // Se refresca cuando cambia algún pedido activo (p. ej. al cobrar).
  ref.watch(pedidosActivosProvider.select((p) => p.value?.length));
  final pagados = await ref.watch(pedidosRepositoryProvider).pedidos(estado: EstadoPedido.pagado);
  final hoy = DateTime.now();
  bool esHoy(DateTime f) => f.year == hoy.year && f.month == hoy.month && f.day == hoy.day;
  return pagados.where((p) => esHoy(p.creadoEn)).toList().reversed.toList();
});

// ── Cola de envíos sin conexión ─────────────────────────────

/// Pedido o ampliación guardado en la tablet mientras no había conexión.
class EnvioPendiente {
  const EnvioPendiente({
    required this.operacion,
    required this.tipo,
    required this.cuerpo,
    required this.creado,
    required this.resumen,
    required this.total,
    this.pedidoId,
    this.error,
  });

  factory EnvioPendiente.fromJson(Map<String, dynamic> j) => EnvioPendiente(
        operacion: j['operacion'] as String,
        tipo: j['tipo'] as String,
        pedidoId: j['pedido_id'] as int?,
        cuerpo: j['cuerpo'] as Map<String, dynamic>,
        creado: DateTime.parse(j['creado'] as String),
        resumen: j['resumen'] as String,
        total: leerDinero(j['total']),
        error: j['error'] as String?,
      );

  /// Identificador que viaja en `X-Operacion`: la central no lo procesa dos veces.
  final String operacion;

  /// `crear` o `agregar`.
  final String tipo;
  final int? pedidoId;
  final Map<String, dynamic> cuerpo;
  final DateTime creado;
  final String resumen;
  final double total;

  /// Motivo por el que el servidor lo rechazó; hasta que se reintente a mano no se reenvía.
  final String? error;

  String get descripcion => '$resumen · ${dinero(total)}';

  EnvioPendiente conError(String? error) => EnvioPendiente(
        operacion: operacion,
        tipo: tipo,
        pedidoId: pedidoId,
        cuerpo: cuerpo,
        creado: creado,
        resumen: resumen,
        total: total,
        error: error,
      );

  Map<String, dynamic> toJson() => {
        'operacion': operacion,
        'tipo': tipo,
        'pedido_id': pedidoId,
        'cuerpo': cuerpo,
        'creado': creado.toUtc().toIso8601String(),
        'resumen': resumen,
        'total': total,
        'error': error,
      };
}

final colaEnviosProvider = NotifierProvider.autoDispose<ColaEnvios, List<EnvioPendiente>>(ColaEnvios.new);

/// Envía en orden lo que quedó guardado sin conexión: al recuperar el tiempo
/// real y cada pocos segundos. Los rechazos del servidor (producto desactivado,
/// sesión caducada) quedan marcados hasta que alguien los reintente o descarte.
class ColaEnvios extends Notifier<List<EnvioPendiente>> {
  bool _procesando = false;

  @override
  List<EnvioPendiente> build() {
    final guardados = ref.watch(almacenLocalProvider).lista('cola') ?? const [];
    if (ref.watch(authControllerProvider) != null) {
      final reloj = Timer.periodic(const Duration(seconds: 8), (_) => unawaited(procesar()));
      ref.onDispose(reloj.cancel);
      ref.listen(conexionTiempoRealProvider, (_, conectado) {
        if (conectado.value ?? false) unawaited(procesar());
      });
    }
    return [for (final e in guardados) EnvioPendiente.fromJson(e)];
  }

  void _guardar(List<EnvioPendiente> cola) {
    state = cola;
    unawaited(ref.read(almacenLocalProvider).guardarLista('cola', [for (final e in cola) e.toJson()]));
  }

  Future<void> encolar(EnvioPendiente envio) async => _guardar([...state, envio]);

  void descartar(EnvioPendiente envio) => _guardar([for (final e in state) if (e.operacion != envio.operacion) e]);

  Future<void> reintentar(EnvioPendiente envio) async {
    _guardar([for (final e in state) e.operacion == envio.operacion ? e.conError(null) : e]);
    await procesar();
  }

  Future<void> procesar() async {
    if (_procesando || state.isEmpty || ref.read(authControllerProvider) == null) return;
    _procesando = true;
    try {
      final repo = ref.read(pedidosRepositoryProvider);
      for (final envio in [...state]) {
        if (envio.error != null) continue;
        try {
          final pedido = envio.tipo == 'crear'
              ? await repo.crear(envio.cuerpo, operacion: envio.operacion)
              : await repo.agregar(envio.pedidoId!, envio.cuerpo, operacion: envio.operacion);
          if (!ref.mounted) return;
          _guardar([for (final e in state) if (e.operacion != envio.operacion) e]);
          ref.read(favoritosProvider.notifier).registrar(envio.cuerpo);
          ref.read(sinConexionProvider.notifier).fijar(false);
          if (ref.exists(pedidosActivosProvider)) ref.read(pedidosActivosProvider.notifier).aplicar(pedido);
        } on ApiException catch (e) {
          if (!ref.mounted) return;
          // Sin conexión o sin sesión: se reintenta más tarde con la misma operación.
          if (e.noAutorizado || e.sinConexion) break;
          _guardar([for (final x in state) x.operacion == envio.operacion ? x.conError(e.mensaje) : x]);
        }
      }
    } finally {
      _procesando = false;
    }
  }
}

// ── Favoritos ───────────────────────────────────────────────

/// Cuántas veces se ha pedido cada producto desde esta tablet.
final favoritosProvider = NotifierProvider<Favoritos, Map<int, int>>(Favoritos.new);

class Favoritos extends Notifier<Map<int, int>> {
  @override
  Map<int, int> build() => {
        for (final MapEntry(:key, :value) in ref.watch(almacenLocalProvider).mapa('favoritos').entries)
          int.parse(key): leerEntero(value),
      };

  void registrar(Map<String, dynamic> cuerpo) {
    final conteo = {...state};
    for (final p in (cuerpo['productos'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final id = leerEntero(p['producto_id']);
      conteo[id] = (conteo[id] ?? 0) + leerEntero(p['cantidad']);
    }
    state = conteo;
    unawaited(ref
        .read(almacenLocalProvider)
        .guardarMapa('favoritos', {for (final MapEntry(:key, :value) in conteo.entries) '$key': value}));
  }

  /// Los [cuantos] productos más pedidos, del más al menos pedido.
  List<int> top([int cuantos = 8]) {
    final orden = state.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in orden.take(cuantos)) e.key];
  }
}

// ── Cocina ──────────────────────────────────────────────────

final extrasCocinaProvider =
    NotifierProvider.autoDispose<ExtrasCocina, List<ExtraPedido>>(ExtrasCocina.new);

/// Extras que llegan a cocina para pedidos ya terminados. El servidor no los
/// guarda por separado, así que se conservan en la tablet (sobreviven a un
/// reinicio) hasta que cocina los marca como hechos.
class ExtrasCocina extends Notifier<List<ExtraPedido>> {
  @override
  List<ExtraPedido> build() {
    final suscripcion = ref.watch(tiempoRealProvider).eventos.listen((evento) {
      if (evento is ExtraRecibido) _guardar([...state, evento.extra]);
    });
    ref.onDispose(suscripcion.cancel);
    return [for (final e in ref.read(almacenLocalProvider).lista('extras') ?? const []) ExtraPedido.fromJson(e)];
  }

  void _guardar(List<ExtraPedido> extras) {
    state = extras;
    unawaited(ref.read(almacenLocalProvider).guardarLista('extras', [for (final e in extras) e.toJson()]));
  }

  void marcarHecho(ExtraPedido extra) => _guardar([for (final e in state) if (e.clave != extra.clave) e]);
}

/// Casillas de cocina: renglones ya preparados de cada pedido o extra (clave → índices).
final marcasCocinaProvider = NotifierProvider.autoDispose<MarcasCocina, Map<String, Set<int>>>(MarcasCocina.new);

class MarcasCocina extends Notifier<Map<String, Set<int>>> {
  @override
  Map<String, Set<int>> build() => {
        for (final MapEntry(:key, :value) in ref.read(almacenLocalProvider).mapa('marcas').entries)
          key: {for (final i in value as List) leerEntero(i)},
      };

  void alternar(String clave, int indice) {
    final actual = {...?state[clave]};
    actual.contains(indice) ? actual.remove(indice) : actual.add(indice);
    _guardar({...state, clave: actual});
  }

  /// Olvida las marcas de pedidos que ya salieron de cocina.
  void limpiar(Set<String> vigentes) {
    if (state.keys.every(vigentes.contains)) return;
    _guardar({for (final e in state.entries) if (vigentes.contains(e.key)) e.key: e.value});
  }

  void _guardar(Map<String, Set<int>> marcas) {
    state = marcas;
    unawaited(ref
        .read(almacenLocalProvider)
        .guardarMapa('marcas', {for (final e in marcas.entries) e.key: e.value.toList()}));
  }
}
