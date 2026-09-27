import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'central.dart';

/// Puertos de la central en la red local.
const puertoCentral = 8787;
const puertoAnuncio = 8788;

/// Código con el que la central cierra un WebSocket cuya sesión ya no vale
/// (token caducado, contraseña o rol cambiados, usuario borrado, enlace renovado).
/// La tablet reconecta con su token actual; si la central lo rechaza (401), cierra sesión.
const cierreSesionInvalida = 4401;

/// Dirección de la red local: privadas (10/8, 172.16/12, 192.168/16), loopback
/// (127/8), enlace local (169.254/16) y sus equivalentes IPv6 (::1, fc00::/7,
/// fe80::/10). Las de datos móviles o de internet no lo son.
bool esIpLocal(InternetAddress ip) {
  var b = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv6) {
    final mapeada = b.length == 16 && b.take(10).every((x) => x == 0) && b[10] == 0xff && b[11] == 0xff;
    if (!mapeada) {
      if (ip.isLoopback) return true;
      return (b[0] & 0xfe) == 0xfc || (b[0] == 0xfe && (b[1] & 0xc0) == 0x80);
    }
    b = b.sublist(12); // IPv4 dentro de IPv6 (::ffff:a.b.c.d).
  } else if (ip.type != InternetAddressType.IPv4) {
    return false;
  }
  if (b.length != 4) return false;
  return b[0] == 10 ||
      b[0] == 127 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 169 && b[1] == 254);
}

/// [esIpLocal] para una IP escrita como texto; `false` si no es una IP.
bool esIpLocalTexto(String texto) {
  final ip = InternetAddress.tryParse(texto.trim());
  return ip != null && esIpLocal(ip);
}

typedef _Intentos = ({int fallos, DateTime desde});

/// Sesión con la que se abrió un WebSocket, para cerrarlo cuando deje de valer.
typedef _SesionSocket = ({String token, int usuario, int ver});

/// Servidor HTTP + WebSocket de la central en la red local (`/api/...` y `/ws`).
///
/// Solo atiende a direcciones de la red local ([esIpLocal]): aunque la tablet
/// tenga datos móviles, desde internet no se puede ni intentar entrar.
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
  Timer? _revision;
  final _clientes = <WebSocket, _SesionSocket>{};
  final _intentosLogin = <String, _Intentos>{};
  final _intentosEnlace = <String, _Intentos>{};
  final _loginsEnCurso = <String, int>{};
  var _loginsTotales = 0;

  /// Tras 5 contraseñas incorrectas desde la misma IP, el login se bloquea 30 segundos.
  static const maxFallosLogin = 5;
  static const ventanaLogin = Duration(seconds: 30);

  /// Logins que calculan PBKDF2 a la vez (por IP y en total): sin límite, muchas
  /// peticiones en paralelo saturarían la tablet.
  static const maxLoginsPorIp = 2;
  static const maxLoginsTotales = 6;

  /// Tras 30 códigos de enlace incorrectos en un minuto desde la misma IP, se bloquea
  /// hasta que termine el minuto. Una tablet con el código viejo reintenta mucho menos.
  static const maxFallosEnlace = 30;
  static const ventanaEnlace = Duration(minutes: 1);

  int get puertoEnUso => _http?.port ?? puerto;
  int get clientesConectados => _clientes.length;

  Future<void> iniciar() async {
    central
      ..emitir = _difundir
      ..alRevocarSesiones = revisarSesiones;
    _http = await HttpServer.bind(InternetAddress.anyIPv4, puerto, shared: true);
    _http!.listen((peticion) => unawaited(_atender(peticion)));
    // Los tokens caducan aunque nadie haga nada: se revisan cada poco.
    _revision = Timer.periodic(const Duration(seconds: 30), (_) => revisarSesiones());
    if (anunciar) await _iniciarAnuncio();
  }

  Future<void> detener() async {
    _temporizadorAnuncio?.cancel();
    _revision?.cancel();
    _udp?.close();
    final clientes = [..._clientes.keys];
    _clientes.clear();
    for (final ws in clientes) {
      await ws.close(WebSocketStatus.goingAway);
    }
    await _http?.close(force: true);
    central
      ..emitir = null
      ..alRevocarSesiones = null;
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
    for (final ws in [..._clientes.keys]) {
      ws.add(mensaje);
    }
  }

  /// Cierra los WebSockets cuya sesión ya no vale: token caducado, contraseña o
  /// rol cambiados (`ver`), usuario borrado o código de enlace renovado.
  void revisarSesiones() {
    for (final MapEntry(key: ws, value: sesion) in [..._clientes.entries]) {
      final usuario = central.autenticar(sesion.token);
      if (usuario == null || usuario.id != sesion.usuario || usuario.versionToken != sesion.ver) {
        _clientes.remove(ws);
        unawaited(ws.close(cierreSesionInvalida, 'Sesion cerrada'));
      }
    }
  }

  Future<void> _abrirWebSocket(HttpRequest peticion) async {
    final token = peticion.uri.queryParameters['token'] ?? '';
    final usuario = central.autenticar(token) ??
        (throw ErrorCentral(401, 'INVALID_TOKEN', 'La sesión caducó o se cerró. Inicia sesión de nuevo.'));
    final ws = await WebSocketTransformer.upgrade(peticion);
    ws.pingInterval = const Duration(seconds: 15);
    _clientes[ws] = (token: token, usuario: usuario.id, ver: usuario.versionToken);
    ws.listen((_) {}, onDone: () => _clientes.remove(ws), onError: (_) => _clientes.remove(ws));
    // Pudo revocarse mientras se completaba el upgrade.
    revisarSesiones();
  }

  // ── HTTP ─────────────────────────────────────────────────

  /// Entrada vigente de [mapa] para [ip] (dentro de [ventana]); borra las vencidas.
  _Intentos? _vigente(Map<String, _Intentos> mapa, String ip, DateTime ahora, Duration ventana) {
    if (mapa.length > 500) mapa.removeWhere((_, i) => ahora.difference(i.desde) >= ventana);
    final previo = mapa[ip];
    if (previo == null || ahora.difference(previo.desde) < ventana) return previo;
    mapa.remove(ip);
    return null;
  }

  String? _token(HttpRequest peticion) {
    final cabecera = peticion.headers.value(HttpHeaders.authorizationHeader);
    if (cabecera != null) return cabecera.startsWith('Bearer ') ? cabecera.substring(7).trim() : cabecera.trim();
    return peticion.uri.queryParameters['token'];
  }

  /// Exige el código de enlace, limitando los intentos fallidos por IP.
  void _comprobarEnlace(HttpRequest peticion, String ip) {
    final ahora = DateTime.now();
    final previo = _vigente(_intentosEnlace, ip, ahora, ventanaEnlace);
    if (previo != null && previo.fallos >= maxFallosEnlace) {
      throw ErrorCentral(429, 'TOO_MANY_ATTEMPTS', 'Demasiados códigos de enlace incorrectos. Espera un minuto.');
    }
    final enlace = peticion.headers.value('x-enlace') ?? peticion.uri.queryParameters['enlace'];
    if (central.enlaceValido(enlace)) return;
    _intentosEnlace[ip] = (fallos: (previo?.fallos ?? 0) + 1, desde: previo?.desde ?? ahora);
    // Tablet con el código anterior a una renovación: su sesión también murió.
    // Con 401 cierra sesión y, al volver a entrar, se le pide enlazarse de nuevo.
    final token = _token(peticion);
    if (token != null && token.isNotEmpty && central.autenticar(token) == null) {
      throw ErrorCentral(401, 'INVALID_TOKEN', 'La sesión caducó o se cerró. Inicia sesión de nuevo.');
    }
    throw ErrorCentral(403, 'ENLACE', 'Código de enlace incorrecto. Pídelo en la tablet de cocina.');
  }

  Future<void> _atender(HttpRequest peticion) async {
    try {
      final remota = peticion.connectionInfo?.remoteAddress;
      if (remota == null || !esIpLocal(remota)) {
        throw ErrorCentral(403, 'RED_NO_PERMITIDA', 'La central solo atiende a la red local del restaurante.');
      }
      final ruta = peticion.uri.path;
      if (ruta == '/health' || ruta == '/api/health') {
        return await _responder(peticion, 200, {'success': true, 'status': 'ok', 'central': true});
      }
      _comprobarEnlace(peticion, remota.address);
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
      case ('POST', ['auth', 'renovar']):
        return (200, central.renovarSesion(_usuario(peticion)));
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
      case ('POST', ['pedidos', 'cobrar']):
        _usuario(peticion, salon);
        return (200, {'mensaje': 'Cobro registrado', 'pedidos': await central.cobrar(cuerpo)});
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
      case ('PATCH', ['pedidos', final id, 'mover']):
        _usuario(peticion, salon);
        return (200, {'mensaje': 'Producto movido', ...await central.moverProducto(_id(id), cuerpo)});
      case ('PATCH', ['pedidos', final id, 'dividir']):
        _usuario(peticion, salon);
        return (200, {'mensaje': 'Producto dividido', ...await central.dividirProducto(_id(id), cuerpo)});
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

  /// Tras [maxFallosLogin] intentos fallidos desde la misma IP, bloquea el login
  /// [ventanaLogin]. El intento se cuenta como fallo *antes* de comprobar la
  /// contraseña (y se descuenta si acierta), así que peticiones en paralelo no
  /// pueden esquivar el límite; además solo [maxLoginsPorIp] a la vez por IP.
  Future<Map<String, dynamic>> _login(HttpRequest peticion, Map<String, dynamic> cuerpo) async {
    final ip = peticion.connectionInfo?.remoteAddress.address ?? '?';
    final ahora = DateTime.now();
    final previo = _vigente(_intentosLogin, ip, ahora, ventanaLogin);
    if (previo != null && previo.fallos >= maxFallosLogin) {
      throw ErrorCentral(429, 'TOO_MANY_ATTEMPTS', 'Demasiados intentos. Espera 30 segundos.');
    }
    if ((_loginsEnCurso[ip] ?? 0) >= maxLoginsPorIp || _loginsTotales >= maxLoginsTotales) {
      throw ErrorCentral(429, 'LOGIN_OCUPADO', 'Hay otro inicio de sesión en curso. Intenta de nuevo en un momento.');
    }
    _intentosLogin[ip] = (fallos: (previo?.fallos ?? 0) + 1, desde: previo?.desde ?? ahora);
    _loginsEnCurso[ip] = (_loginsEnCurso[ip] ?? 0) + 1;
    _loginsTotales++;
    try {
      final resultado = await central.login(cuerpo['username']?.toString() ?? '', cuerpo['password']?.toString() ?? '');
      _intentosLogin.remove(ip);
      return resultado;
    } finally {
      _loginsTotales--;
      final enCurso = (_loginsEnCurso[ip] ?? 1) - 1;
      if (enCurso <= 0) {
        _loginsEnCurso.remove(ip);
      } else {
        _loginsEnCurso[ip] = enCurso;
      }
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
    if (datagrama == null || !esIpLocal(datagrama.address)) return;
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
/// Omite las de datos móviles (públicas): la central no las atiende.
Future<List<String>> ipsLocales() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLoopback && esIpLocal(a)) a.address,
    ];
  } on SocketException {
    return const [];
  }
}
