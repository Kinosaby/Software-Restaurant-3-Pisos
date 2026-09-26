import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'central.dart';

/// Puertos de la central en la red local.
const puertoCentral = 8787;
const puertoAnuncio = 8788;

/// Servidor HTTP + WebSocket de la central en la red local (`/api/...` y `/ws`).
///
/// Todas las peticiones llevan el código de enlace (`X-Enlace`): sin él, un
/// dispositivo en el mismo Wi-Fi no puede ni intentar iniciar sesión.
/// Además anuncia la central por UDP cada pocos segundos para que las tablets
/// de los meseros la encuentren sin teclear la IP.
class ServidorCentral {
  ServidorCentral(this.central, {this.puerto = puertoCentral, this.anunciar = true});

  final Central central;
  final int puerto;
  final bool anunciar;

  HttpServer? _http;
  RawDatagramSocket? _udp;
  Timer? _temporizadorAnuncio;
  final _clientes = <WebSocket>{};
  final _intentosLogin = <String, ({int fallos, DateTime desde})>{};

  int get puertoEnUso => _http?.port ?? puerto;
  int get clientesConectados => _clientes.length;

  Future<void> iniciar() async {
    central.emitir = _difundir;
    _http = await HttpServer.bind(InternetAddress.anyIPv4, puerto, shared: true);
    _http!.listen((peticion) => unawaited(_atender(peticion)));
    if (anunciar) await _iniciarAnuncio();
  }

  Future<void> detener() async {
    _temporizadorAnuncio?.cancel();
    _udp?.close();
    for (final ws in [..._clientes]) {
      await ws.close(WebSocketStatus.goingAway);
    }
    await _http?.close(force: true);
    central.emitir = null;
  }

  // ── Anuncio en la red local ──────────────────────────────

  Future<void> _iniciarAnuncio() async {
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)..broadcastEnabled = true;
    } on SocketException {
      return; // Sin red: se puede conectar tecleando la IP.
    }
    void enviar() {
      final mensaje = utf8.encode(jsonEncode({'app': 'tres_pisos', 'nombre': central.nombre, 'puerto': puertoEnUso}));
      try {
        _udp?.send(mensaje, InternetAddress('255.255.255.255'), puertoAnuncio);
      } on SocketException {
        // Wi-Fi caído momentáneamente.
      }
    }

    enviar();
    _temporizadorAnuncio = Timer.periodic(const Duration(seconds: 3), (_) => enviar());
  }

  // ── Tiempo real ──────────────────────────────────────────

  void _difundir(String evento, Map<String, dynamic> datos) {
    final mensaje = jsonEncode({'evento': evento, 'datos': datos});
    for (final ws in [..._clientes]) {
      ws.add(mensaje);
    }
  }

  Future<void> _abrirWebSocket(HttpRequest peticion) async {
    final token = peticion.uri.queryParameters['token'] ?? '';
    if (central.autenticar(token) == null) {
      throw ErrorCentral(401, 'INVALID_TOKEN', 'Token inválido.');
    }
    final ws = await WebSocketTransformer.upgrade(peticion);
    ws.pingInterval = const Duration(seconds: 15);
    _clientes.add(ws);
    ws.listen((_) {}, onDone: () => _clientes.remove(ws), onError: (_) => _clientes.remove(ws));
  }

  // ── HTTP ─────────────────────────────────────────────────

  Future<void> _atender(HttpRequest peticion) async {
    try {
      final ruta = peticion.uri.path;
      if (ruta == '/health' || ruta == '/api/health') {
        return await _responder(peticion, 200, {'success': true, 'status': 'ok', 'central': true});
      }
      final enlace = peticion.headers.value('x-enlace') ?? peticion.uri.queryParameters['enlace'];
      if (!central.enlaceValido(enlace)) {
        throw ErrorCentral(403, 'ENLACE', 'Código de enlace incorrecto. Pídelo en la tablet de cocina.');
      }
      if (ruta == '/ws') return await _abrirWebSocket(peticion);

      final (status, cuerpo) = await _rutear(peticion, await _leerCuerpo(peticion));
      await _responder(peticion, status, {'success': true, ...cuerpo});
    } on ErrorCentral catch (e) {
      await _responder(peticion, e.status, e.toJson());
    } on Object catch (e) {
      stderr.writeln('Central: error no controlado en ${peticion.method} ${peticion.uri.path}: $e');
      await _responder(peticion, 500, ErrorCentral(500, 'INTERNAL_ERROR', 'Error interno de la central.').toJson());
    }
  }

  Future<Map<String, dynamic>> _leerCuerpo(HttpRequest peticion) async {
    if (peticion.method == 'GET' || peticion.method == 'DELETE') return const {};
    final bytes = <int>[];
    await for (final trozo in peticion) {
      bytes.addAll(trozo);
      if (bytes.length > 1024 * 1024) throw ErrorCentral(413, 'TOO_LARGE', 'Petición demasiado grande.');
    }
    if (bytes.isEmpty) return const {};
    try {
      final datos = jsonDecode(utf8.decode(bytes));
      if (datos is Map<String, dynamic>) return datos;
    } on FormatException {
      // cae al error de abajo
    }
    throw ErrorCentral(400, 'BAD_JSON', 'Cuerpo JSON inválido.');
  }

  Future<void> _responder(HttpRequest peticion, int status, Map<String, dynamic> cuerpo) async {
    try {
      peticion.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(cuerpo));
      await peticion.response.close();
    } on Object {
      // El cliente se desconectó antes de recibir la respuesta.
    }
  }

  UsuarioCentral _usuario(HttpRequest peticion, [List<String>? roles]) {
    final cabecera = peticion.headers.value(HttpHeaders.authorizationHeader);
    if (cabecera == null) throw ErrorCentral(401, 'NO_TOKEN', 'Acceso denegado. No hay token de autenticación.');
    final token = cabecera.startsWith('Bearer ') ? cabecera.substring(7).trim() : cabecera.trim();
    final usuario = central.autenticar(token) ??
        (throw ErrorCentral(401, 'INVALID_TOKEN', 'La sesión caducó o se cerró. Inicia sesión de nuevo.'));
    if (roles != null && !roles.contains(usuario.rol)) {
      throw ErrorCentral(403, 'FORBIDDEN', 'Acceso denegado. Se requiere rol: ${roles.join(' o ')}.');
    }
    return usuario;
  }

  int _id(String texto) =>
      int.tryParse(texto) ?? (throw ErrorCentral(400, 'VALIDATION_ERROR', 'ID inválido.'));

  Future<(int, Map<String, dynamic>)> _rutear(HttpRequest peticion, Map<String, dynamic> cuerpo) async {
    final metodo = peticion.method;
    final s = peticion.uri.pathSegments;
    if (s.length < 2 || s[0] != 'api') throw ErrorCentral(404, 'NOT_FOUND', 'Ruta no encontrada.');
    final operacion = peticion.headers.value('x-operacion');
    const todos = ['admin', 'mesero', 'cocina'];
    const salon = ['admin', 'mesero'];
    const admin = ['admin'];

    switch ((metodo, s.sublist(1))) {
      case ('GET', ['central', 'info']):
        return (200, {'nombre': central.nombre, 'version': 1});

      // Autenticación y usuarios
      case ('POST', ['auth', 'login']):
        return (200, await _login(peticion, cuerpo));
      case ('GET', ['auth', 'me']):
        return (200, {'user': _usuario(peticion).publico()});
      case ('POST', ['auth', 'register']):
        _usuario(peticion, admin);
        return (201, {'mensaje': 'Usuario creado', 'user': await central.crearUsuario(cuerpo)});
      case ('GET', ['auth', 'usuarios']):
        _usuario(peticion, admin);
        return (200, {'usuarios': central.listarUsuarios()});
      case ('PUT', ['auth', final id]):
        _usuario(peticion, admin);
        return (200, {'user': await central.actualizarUsuario(_id(id), cuerpo)});
      case ('DELETE', ['auth', final id]):
        final actor = _usuario(peticion, admin);
        return (200, {'mensaje': 'Usuario eliminado', 'user': await central.eliminarUsuario(_id(id), actorId: actor.id)});

      // Productos
      case ('GET', ['productos']):
        _usuario(peticion);
        return (200, {'productos': central.listarProductos()});
      case ('POST', ['productos']):
        _usuario(peticion, admin);
        return (201, {'producto': await central.crearProducto(cuerpo)});
      case ('PUT', ['productos', final id]):
        _usuario(peticion, admin);
        return (200, {'producto': await central.actualizarProducto(_id(id), cuerpo)});
      case ('DELETE', ['productos', final id]):
        _usuario(peticion, admin);
        return (200, {'mensaje': 'Producto eliminado', 'producto': await central.eliminarProducto(_id(id))});

      // Pedidos
      case ('GET', ['pedidos']):
        _usuario(peticion, todos);
        return (200, {'pedidos': central.listarPedidos(estado: peticion.uri.queryParameters['estado'])});
      case ('GET', ['pedidos', final id]):
        _usuario(peticion, todos);
        return (200, {'pedido': central.obtenerPedido(_id(id))});
      case ('POST', ['pedidos']):
        final usuario = _usuario(peticion, salon);
        final pedido = await central.crearPedido(cuerpo, usuario: usuario, operacion: operacion);
        return (201, {'mensaje': 'Pedido creado', 'pedido': pedido});
      case ('PUT', ['pedidos', final id, 'estado']):
        final usuario = _usuario(peticion, todos);
        final estado = cuerpo['estado']?.toString() ?? '';
        return (200, {'mensaje': 'Estado actualizado', 'pedido': await central.cambiarEstado(_id(id), estado, usuario: usuario)});
      case ('PATCH', ['pedidos', final id, 'cancelar']):
        final usuario = _usuario(peticion, salon);
        return (200, {'mensaje': 'Pedido cancelado', 'pedido': await central.cambiarEstado(_id(id), 'cancelado', usuario: usuario)});
      case ('PATCH', ['pedidos', final id, 'agregar']):
        final usuario = _usuario(peticion, salon);
        final pedido = await central.agregarProductos(_id(id), cuerpo, usuario: usuario, operacion: operacion);
        return (200, {'mensaje': 'Productos agregados al pedido', 'pedido': pedido});
      case ('PATCH', ['pedidos', final id, 'editar']):
        _usuario(peticion, salon);
        return (200, {'mensaje': 'Pedido editado', 'pedido': await central.editarPedido(_id(id), cuerpo)});
      case ('DELETE', ['pedidos', final id]):
        _usuario(peticion, admin);
        return (200, {'mensaje': 'Pedido eliminado', 'pedido': await central.eliminarPedido(_id(id))});

      // Métricas
      case ('GET', ['metricas', 'resumen']):
        _usuario(peticion, admin);
        return (200, central.resumen());
      case ('GET', ['metricas', 'ventas']):
        _usuario(peticion, admin);
        final dias = (int.tryParse(peticion.uri.queryParameters['dias'] ?? '') ?? 7).clamp(1, 366);
        return (200, {'ventas': central.ventasPorDia(dias)});
    }
    throw ErrorCentral(404, 'NOT_FOUND', 'Ruta no encontrada.');
  }

  /// Tras 5 intentos fallidos desde la misma IP, bloquea el login 30 segundos.
  Future<Map<String, dynamic>> _login(HttpRequest peticion, Map<String, dynamic> cuerpo) async {
    final ip = peticion.connectionInfo?.remoteAddress.address ?? '?';
    final previo = _intentosLogin[ip];
    final ahora = DateTime.now();
    if (previo != null && previo.fallos >= 5 && ahora.difference(previo.desde) < const Duration(seconds: 30)) {
      throw ErrorCentral(429, 'TOO_MANY_ATTEMPTS', 'Demasiados intentos. Espera 30 segundos.');
    }
    try {
      final resultado = await central.login(cuerpo['username']?.toString() ?? '', cuerpo['password']?.toString() ?? '');
      _intentosLogin.remove(ip);
      return resultado;
    } on ErrorCentral {
      final fallos = (previo != null && ahora.difference(previo.desde) < const Duration(seconds: 30)) ? previo.fallos + 1 : 1;
      _intentosLogin[ip] = (fallos: fallos, desde: fallos == 1 ? ahora : previo!.desde);
      rethrow;
    }
  }
}

/// Central encontrada en la red por su anuncio UDP.
class CentralEncontrada {
  const CentralEncontrada({required this.ip, required this.puerto, required this.nombre});

  final String ip;
  final int puerto;
  final String nombre;

  String get url => 'http://$ip:$puerto';
}

/// Escucha los anuncios de centrales durante [duracion].
Future<List<CentralEncontrada>> buscarCentrales({Duration duracion = const Duration(seconds: 4)}) async {
  final encontradas = <String, CentralEncontrada>{};
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, puertoAnuncio, reuseAddress: true);
  } on SocketException {
    return const [];
  }
  final suscripcion = socket.listen((evento) {
    if (evento != RawSocketEvent.read) return;
    final datagrama = socket!.receive();
    if (datagrama == null) return;
    try {
      final datos = jsonDecode(utf8.decode(datagrama.data)) as Map<String, dynamic>;
      if (datos['app'] != 'tres_pisos') return;
      final ip = datagrama.address.address;
      encontradas[ip] = CentralEncontrada(
        ip: ip,
        puerto: datos['puerto'] as int? ?? puertoCentral,
        nombre: datos['nombre']?.toString() ?? 'Central',
      );
    } on Object {
      // Otro programa usando el mismo puerto.
    }
  });
  await Future<void>.delayed(duracion);
  await suscripcion.cancel();
  socket.close();
  return encontradas.values.toList();
}

/// IPs de esta tablet en la red local, para mostrarlas en la pantalla de la central.
Future<List<String>> ipsLocales() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLoopback) a.address,
    ];
  } on SocketException {
    return const [];
  }
}
