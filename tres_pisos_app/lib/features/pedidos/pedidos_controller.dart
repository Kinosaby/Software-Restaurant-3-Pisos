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

/// Lista recién descargada de la central junto con la que se tenía antes.
typedef ListaRecargada = ({List<Pedido> antes, List<Pedido> ahora});

/// Última descarga completa de los pedidos activos. Comparando con lo que había
/// se sabe qué cambió mientras la tablet no recibía eventos (sin Wi-Fi o con la
/// app cerrada); con eso se dan los avisos que se perdieron.
final listaRecargadaProvider = NotifierProvider<UltimaRecarga, ListaRecargada?>(UltimaRecarga.new);

class UltimaRecarga extends Notifier<ListaRecargada?> {
  @override
  ListaRecargada? build() => null;

  void publicar(List<Pedido> antes, List<Pedido> ahora) => state = (antes: antes, ahora: ahora);
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
    final recarga = ref.read(listaRecargadaProvider.notifier);
    final suscripcion = ref.watch(tiempoRealProvider).eventos.listen(_alEvento);
    ref.onDispose(suscripcion.cancel);
    _cargas++;
    try {
      // Lo que se creó mientras se cargaba la lista pudo quedar fuera de la respuesta.
      final pedidos = _conLoQueLlegoMientras(ordenarPedidos(await repo.pedidosActivos()));
      // Lo que esta tablet vio por última vez (antes de cerrarse o de perder la red).
      final antes = _copiaGuardada(almacen);
      unawaited(almacen.guardarLista('pedidos', [for (final p in pedidos) p.toJson()]));
      sinConexion.fijar(false);
      if (antes != null) recarga.publicar(antes, pedidos);
      return pedidos;
    } on ApiException catch (e) {
      _terminarCarga();
      final copia = almacen.lista('pedidos');
      if (!e.sinConexion || copia == null) rethrow;
      sinConexion.fijar(true);
      return ordenarPedidos([for (final p in copia) Pedido.fromJson(p)]);
    }
  }

  /// `null` si nunca se guardó una copia o no se puede leer.
  static List<Pedido>? _copiaGuardada(AlmacenLocal almacen) {
    try {
      final copia = almacen.lista('pedidos');
      return copia == null ? null : [for (final p in copia) Pedido.fromJson(p)];
    } on Object {
      return null;
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

  /// Pedidos que llegaron (creados aquí o por tiempo real) antes de terminar de
  /// cargar la lista; se suman al terminar para que no se pierdan.
  final _mientrasCarga = <Pedido>[];

  /// Inserta o reemplaza un pedido; si ya no está activo, lo quita de la lista.
  void aplicar(Pedido pedido) {
    // También durante una recarga: su respuesta pudo salir de la central antes de este cambio.
    if (_cargas > 0) _mientrasCarga.add(pedido);
    final actuales = state.value;
    if (actuales == null) return;
    _fijar(reemplazarPedido(actuales, pedido));
  }

  /// Descargas de la lista en curso (la inicial y las recargas pueden cruzarse).
  int _cargas = 0;

  /// Suma a lo recién descargado los cambios que llegaron durante la descarga:
  /// cuentas nuevas que la respuesta no incluía y las que ya se cerraron.
  List<Pedido> _conLoQueLlegoMientras(List<Pedido> descargados) {
    var pedidos = descargados;
    for (final p in _mientrasCarga) {
      if (!p.estado.activo || !pedidos.any((x) => x.id == p.id)) pedidos = reemplazarPedido(pedidos, p);
    }
    _terminarCarga();
    return pedidos;
  }

  /// Solo se olvida lo recibido cuando ya no queda ninguna descarga que pudiera no traerlo.
  void _terminarCarga() {
    if (_cargas > 0) _cargas--;
    if (_cargas == 0) _mientrasCarga.clear();
  }

  /// Recarga sin tapar la lista actual con un indicador de carga.
  Future<void> recargar() async {
    _cargas++;
    try {
      final pedidos = await ref.read(pedidosRepositoryProvider).pedidosActivos();
      if (!ref.mounted) return;
      final antes = state.value;
      final ahora = _conLoQueLlegoMientras(ordenarPedidos(pedidos));
      _fijar(ahora);
      ref.read(sinConexionProvider.notifier).fijar(false);
      if (antes != null) ref.read(listaRecargadaProvider.notifier).publicar(antes, ahora);
    } on Object catch (e, st) {
      _terminarCarga();
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
    final base = etiquetaMesa(mesa, llevar: tipo == TipoPedido.llevar);
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
        cuerpo: PedidosRepository.cuerpoAgregar(lineas, paraLlevar: pedido.tipo == TipoPedido.llevar),
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
      _ejecutar('guardar los cambios del pedido',
          (repo) => repo.editar(pedidoId, items: items, mesa: mesa, tipo: tipo, comensal: comensal));

  Future<Pedido> cambiarEstado(int pedidoId, EstadoPedido estado) => _ejecutar(
      estado == EstadoPedido.cancelado ? 'cancelar el pedido' : 'cambiar el estado del pedido',
      (repo) => repo.cambiarEstado(pedidoId, estado));

  /// Cambia varios pedidos a la vez (p. ej. "todo listo" de una mesa o cobrar la mesa completa).
  /// Si la conexión se corta a la mitad, el aviso dice cuántos sí cambiaron.
  Future<void> cambiarEstadoVarios(Iterable<int> ids, EstadoPedido estado) async {
    final lista = ids.toList();
    var hechos = 0;
    for (final id in lista) {
      try {
        await cambiarEstado(id, estado);
      } on ApiException catch (e) {
        if (hechos == 0) rethrow;
        throw ApiException('${e.mensaje}\nDe ${lista.length} pedidos, $hechos sí se cambiaron.',
            status: e.status, codigo: e.codigo, sinConexion: e.sinConexion, entregaIncierta: e.entregaIncierta);
      }
      hechos++;
    }
  }

  Future<Pedido> cancelar(int pedidoId) => _ejecutar('cancelar el pedido', (repo) => repo.cancelar(pedidoId));

  /// Pasa [cantidad] piezas de un renglón a otra cuenta de la misma mesa.
  /// [operacion] identifica la acción: si se reintenta con el mismo, la central no la repite.
  Future<Reparto> moverProducto(
    Pedido origen,
    PedidoItem item, {
    required int cantidad,
    required Pedido destino,
    String? operacion,
  }) =>
      _repartir((repo) => repo.mover(origen.id,
          detalleId: item.detalleId, cantidad: cantidad, destino: destino.id, operacion: operacion));

  /// Divide una pieza de un renglón en partes iguales entre [origen] y [destinos].
  Future<Reparto> dividirProducto(Pedido origen, PedidoItem item, List<Pedido> destinos, {String? operacion}) =>
      _repartir((repo) => repo.dividir(origen.id,
          detalleId: item.detalleId, destinos: [for (final d in destinos) d.id], operacion: operacion));

  Future<Reparto> _repartir(Future<Reparto> Function(PedidosRepository repo) accion) async {
    final Reparto reparto;
    try {
      reparto = await accion(ref.read(pedidosRepositoryProvider));
    } on ApiException catch (e) {
      throw _sinCentral(e, 'mover o dividir el producto');
    }
    final actuales = state.value;
    if (ref.mounted && actuales != null) _fijar(aplicarReparto(actuales, reparto));
    return reparto;
  }

  /// Cobra varias cuentas de una vez con su forma de pago (efectivo, tarjeta o mixto).
  /// Como los demás cobros, no se encola: sin conexión falla con el mismo aviso.
  Future<List<Pedido>> cobrar(Iterable<int> ids, Pago pago, {String? operacion}) async {
    final cobrados = <Pedido>[];
    await _ejecutar('registrar el cobro', (repo) async {
      cobrados.addAll(await repo.cobrar(ids.toList(), pago, operacion: operacion));
      return cobrados.last;
    });
    if (ref.mounted) {
      for (final p in cobrados) {
        aplicar(p);
      }
    }
    return cobrados;
  }

  Future<Pedido> _ejecutar(String que, Future<Pedido> Function(PedidosRepository repo) accion) async {
    try {
      final pedido = await accion(ref.read(pedidosRepositoryProvider));
      if (ref.mounted) aplicar(pedido);
      return pedido;
    } on ApiException catch (e) {
      throw _sinCentral(e, que);
    }
  }

  /// Cobros, cambios de estado, ediciones, cancelaciones y repartos no se
  /// encolan: deben confirmarse en el momento. Sin conexión se explica qué
  /// pasó; si la central pudo recibirlo sin contestar, se recarga la lista para
  /// que se vea cómo quedó y nadie lo repita a ciegas.
  ApiException _sinCentral(ApiException e, String que) {
    if (!e.sinConexion) return e;
    if (e.entregaIncierta) {
      if (ref.mounted) unawaited(recargar());
      return ApiException('La central no respondió a tiempo: no se sabe si se alcanzó a $que. '
          'Revisa el pedido cuando vuelva la conexión antes de repetirlo.',
          sinConexion: true, entregaIncierta: true);
    }
    return ApiException('Sin conexión con la central: no se pudo $que (no quedó registrado). Esto no '
        'se guarda para después; hazlo cuando la tablet de cocina esté encendida y en el mismo Wi-Fi.',
        sinConexion: true);
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

/// Quita la cuenta que se quedó vacía y reemplaza las que cambiaron al mover o dividir.
List<Pedido> aplicarReparto(List<Pedido> actuales, Reparto reparto) {
  var lista = [for (final p in actuales) if (p.id != reparto.eliminado) p];
  for (final p in reparto.pedidos) {
    lista = reemplazarPedido(lista, p);
  }
  return lista;
}

/// Pedidos cobrados hoy (para el historial del día del mesero y "repetir pedido").
final pagadosHoyProvider = FutureProvider.autoDispose<List<Pedido>>((ref) async {
  // Se refresca cuando cambia algún pedido activo (p. ej. al cobrar).
  ref.watch(pedidosActivosProvider.select((p) => p.value?.length));
  final hoy = DateTime.now();
  // Solo los de hoy: sin el filtro se descargaba todo el historial de pagados.
  final pagados = await ref
      .watch(pedidosRepositoryProvider)
      .pedidos(estado: EstadoPedido.pagado, desde: DateTime(hoy.year, hoy.month, hoy.day));
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

  /// Lleva tanto tiempo guardado que ya no se manda solo a cocina (ver [esperaMaximaCola]).
  bool caducado([DateTime? ahora]) => (ahora ?? DateTime.now()).difference(creado) > esperaMaximaCola;

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

/// Lo que lleve más de este tiempo en la cola ya no se envía solo. Un corte de
/// Wi-Fi durante el servicio dura minutos, y aun uno largo cabe en tres horas;
/// en cambio, entre el cierre y la apertura siempre pasan más. Se mide por
/// tiempo transcurrido y no por fecha para que un pedido de las 23:50 siga
/// saliendo pasada la medianoche.
const esperaMaximaCola = Duration(hours: 3);

final colaEnviosProvider = NotifierProvider.autoDispose<ColaEnvios, List<EnvioPendiente>>(ColaEnvios.new);

/// Envía en orden lo que quedó guardado sin conexión: al recuperar el tiempo
/// real y cada pocos segundos. Los rechazos del servidor (producto desactivado,
/// sesión caducada) quedan marcados hasta que alguien los reintente o descarte.
/// Lo que lleva guardado más de [esperaMaximaCola] (p. ej. la tablet se apagó y
/// se abre al día siguiente) tampoco sale solo: el mesero decide si lo envía.
class ColaEnvios extends Notifier<List<EnvioPendiente>> {
  bool _procesando = false;

  /// Envíos viejos que el mesero ya pidió mandar de todos modos.
  final _confirmados = <String>{};

  @override
  List<EnvioPendiente> build() {
    final guardados = ref.watch(almacenLocalProvider).lista('cola') ?? const [];
    // Solo si hay sesión o no: renovar el token no reinicia la cola.
    if (ref.watch(authControllerProvider.select((s) => s != null))) {
      final reloj = Timer.periodic(const Duration(seconds: 8), (_) => unawaited(procesar()));
      ref.onDispose(reloj.cancel);
      ref.listen(conexionTiempoRealProvider, (_, conectado) {
        if (conectado.value ?? false) unawaited(procesar());
      });
    }
    return [for (final e in guardados) EnvioPendiente.fromJson(e)];
  }

  Future<void> _guardar(List<EnvioPendiente> cola) {
    state = cola;
    return ref.read(almacenLocalProvider).guardarLista('cola', [for (final e in cola) e.toJson()]);
  }

  /// Se espera a que quede escrito: si la app se cierra justo después, el envío no se pierde.
  Future<void> encolar(EnvioPendiente envio) => _guardar([...state, envio]);

  void descartar(EnvioPendiente envio) {
    _confirmados.remove(envio.operacion);
    unawaited(_guardar([for (final e in state) if (e.operacion != envio.operacion) e]));
  }

  /// Envío pedido a mano: también vale para lo rechazado y para lo que ya no sale solo por viejo.
  Future<void> reintentar(EnvioPendiente envio) async {
    _confirmados.add(envio.operacion);
    await _guardar([for (final e in state) e.operacion == envio.operacion ? e.conError(null) : e]);
    await procesar();
  }

  Future<void> procesar() async {
    if (_procesando || state.isEmpty || ref.read(authControllerProvider) == null) return;
    _procesando = true;
    try {
      final repo = ref.read(pedidosRepositoryProvider);
      for (final envio in [...state]) {
        if (envio.error != null) continue;
        // Un pedido de hace horas (o de ayer) no llega a cocina sin que alguien lo confirme.
        if (envio.caducado() && !_confirmados.contains(envio.operacion)) continue;
        try {
          final pedido = envio.tipo == 'crear'
              ? await repo.crear(envio.cuerpo, operacion: envio.operacion)
              : await repo.agregar(envio.pedidoId!, envio.cuerpo, operacion: envio.operacion);
          if (!ref.mounted) return;
          _confirmados.remove(envio.operacion);
          unawaited(_guardar([for (final e in state) if (e.operacion != envio.operacion) e]));
          ref.read(favoritosProvider.notifier).registrar(envio.cuerpo);
          ref.read(sinConexionProvider.notifier).fijar(false);
          if (ref.exists(pedidosActivosProvider)) ref.read(pedidosActivosProvider.notifier).aplicar(pedido);
        } on ApiException catch (e) {
          if (!ref.mounted) return;
          // Sin conexión o sin sesión: se reintenta más tarde con la misma operación.
          if (e.noAutorizado || e.sinConexion) break;
          unawaited(_guardar([for (final x in state) x.operacion == envio.operacion ? x.conError(e.mensaje) : x]));
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

// Los extras de pedidos ya listos los marca la central en cada renglón
// (`extra_desde`), así que cocina los ve en `pedidosActivosProvider` aunque la
// pantalla no estuviera abierta cuando llegaron.

/// Casillas de cocina: renglones ya preparados de cada pedido o extra (clave → ids de renglón).
final marcasCocinaProvider = NotifierProvider.autoDispose<MarcasCocina, Map<String, Set<int>>>(MarcasCocina.new);

class MarcasCocina extends Notifier<Map<String, Set<int>>> {
  // Antes se guardaban por posición del renglón ('marcas'); con la clave nueva
  // esas marcas viejas no se leen como ids.
  static const _clave = 'marcas_renglon';

  @override
  Map<String, Set<int>> build() => {
        for (final MapEntry(:key, :value) in ref.read(almacenLocalProvider).mapa(_clave).entries)
          key: {for (final i in value as List) leerEntero(i)},
      };

  void alternar(String clave, int detalleId) {
    final actual = {...?state[clave]};
    actual.contains(detalleId) ? actual.remove(detalleId) : actual.add(detalleId);
    _guardar({...state, clave: actual});
  }

  /// Devuelve las casillas de pedidos que regresaron a cocina ("Deshacer").
  void restaurar(Map<String, Set<int>> marcas) {
    if (marcas.isNotEmpty) _guardar({...state, ...marcas});
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
        .guardarMapa(_clave, {for (final e in marcas.entries) e.key: e.value.toList()}));
  }
}
