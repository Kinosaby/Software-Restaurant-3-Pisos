import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'diario.dart';
import 'seguridad.dart';

/// Error de negocio; se responde como `{success: false, code, error}`.
class ErrorCentral implements Exception {
  ErrorCentral(this.status, this.codigo, this.mensaje);

  final int status;
  final String codigo;
  final String mensaje;

  Map<String, dynamic> toJson() => {'success': false, 'code': codigo, 'error': mensaje};

  @override
  String toString() => mensaje;
}

typedef Emisor = void Function(String evento, Map<String, dynamic> datos);

const rolesValidos = ['admin', 'mesero', 'cocina'];
const estadosValidos = ['pendiente', 'preparando', 'listo', 'pagado', 'cancelado'];

class UsuarioCentral {
  UsuarioCentral({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.rol,
    required this.creadoEn,
    this.versionToken = 0,
  });

  factory UsuarioCentral.fromJson(Map<String, dynamic> j) => UsuarioCentral(
        id: j['id'] as int,
        username: j['username'] as String,
        passwordHash: j['password'] as String,
        rol: j['role'] as String,
        creadoEn: DateTime.parse(j['created_at'] as String),
        versionToken: j['ver'] as int? ?? 0,
      );

  final int id;
  final String username;
  final String passwordHash;
  final String rol;
  final DateTime creadoEn;

  /// Sube al cambiar contraseña o rol: invalida los tokens emitidos antes.
  final int versionToken;

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'password': passwordHash,
        'role': rol,
        'created_at': creadoEn.toUtc().toIso8601String(),
        'ver': versionToken,
      };

  Map<String, dynamic> publico() => {
        'id': id,
        'username': username,
        'role': rol,
        'created_at': creadoEn.toUtc().toIso8601String(),
      };
}

class ProductoCentral {
  ProductoCentral({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.categoria,
    required this.activo,
    required this.creadoEn,
  });

  factory ProductoCentral.fromJson(Map<String, dynamic> j) => ProductoCentral(
        id: j['id'] as int,
        nombre: j['nombre'] as String,
        precio: (j['precio'] as num).toDouble(),
        categoria: j['categoria'] as String? ?? 'General',
        activo: j['activo'] as bool? ?? true,
        creadoEn: DateTime.parse(j['created_at'] as String),
      );

  final int id;
  final String nombre;
  final double precio;
  final String categoria;
  final bool activo;
  final DateTime creadoEn;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'precio': precio,
        'categoria': categoria,
        'activo': activo,
        'created_at': creadoEn.toUtc().toIso8601String(),
      };
}

/// Renglón de un pedido. Guarda nombre y precio del momento en que se pidió.
class ItemCentral {
  ItemCentral({
    required this.id,
    required this.productoId,
    required this.nombre,
    required this.precio,
    required this.cantidad,
    this.nota,
  });

  factory ItemCentral.fromJson(Map<String, dynamic> j) => ItemCentral(
        id: j['id'] as int,
        productoId: j['producto_id'] as int,
        nombre: j['nombre'] as String,
        precio: (j['precio'] as num).toDouble(),
        cantidad: j['cantidad'] as int,
        nota: j['nota'] as String?,
      );

  final int id;
  final int productoId;
  final String nombre;
  final double precio;
  final int cantidad;
  final String? nota;

  ItemCentral copyWith({int? cantidad, String? nota, bool borrarNota = false}) => ItemCentral(
        id: id,
        productoId: productoId,
        nombre: nombre,
        precio: precio,
        cantidad: cantidad ?? this.cantidad,
        nota: borrarNota ? null : (nota ?? this.nota),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'producto_id': productoId,
        'nombre': nombre,
        'cantidad': cantidad,
        'nota': nota,
        'precio': precio,
      };
}

class PedidoCentral {
  PedidoCentral({
    required this.id,
    required this.mesa,
    required this.estado,
    required this.tipo,
    required this.creadoEn,
    required this.items,
    this.comensal,
    this.usuarioId,
    this.mesero,
  });

  factory PedidoCentral.fromJson(Map<String, dynamic> j) => PedidoCentral(
        id: j['id'] as int,
        mesa: j['mesa'] as int,
        estado: j['estado'] as String,
        tipo: j['tipo'] as String,
        comensal: j['comensal'] as String?,
        usuarioId: j['usuario_id'] as int?,
        mesero: j['mesero'] as String?,
        creadoEn: DateTime.parse(j['creado_en'] as String),
        items: [for (final i in j['productos'] as List) ItemCentral.fromJson(i as Map<String, dynamic>)],
      );

  final int id;
  final int mesa;
  final String estado;
  final String tipo;
  final String? comensal;
  final int? usuarioId;
  final String? mesero;
  final DateTime creadoEn;
  final List<ItemCentral> items;

  double get total => items.fold(0, (s, i) => s + i.precio * i.cantidad);

  PedidoCentral copyWith({
    int? mesa,
    String? estado,
    String? tipo,
    String? comensal,
    bool borrarComensal = false,
    List<ItemCentral>? items,
  }) =>
      PedidoCentral(
        id: id,
        mesa: mesa ?? this.mesa,
        estado: estado ?? this.estado,
        tipo: tipo ?? this.tipo,
        comensal: borrarComensal ? null : (comensal ?? this.comensal),
        usuarioId: usuarioId,
        mesero: mesero,
        creadoEn: creadoEn,
        items: items ?? this.items,
      );

  /// Forma con la que viaja el pedido a las tablets.
  Map<String, dynamic> toJson() => {
        'id': id,
        'mesa': mesa,
        'estado': estado,
        'total': double.parse(total.toStringAsFixed(2)),
        'tipo': tipo,
        'comensal': comensal,
        'usuario_id': usuarioId,
        'mesero': mesero,
        'creado_en': creadoEn.toUtc().toIso8601String(),
        'productos': [for (final i in items) i.toJson()],
      };
}

class VentaCentral {
  VentaCentral({required this.id, required this.pedidoId, required this.total, required this.fecha});

  factory VentaCentral.fromJson(Map<String, dynamic> j) => VentaCentral(
        id: j['id'] as int,
        pedidoId: j['pedido_id'] as int,
        total: (j['total'] as num).toDouble(),
        fecha: DateTime.parse(j['fecha'] as String),
      );

  final int id;
  final int pedidoId;
  final double total;
  final DateTime fecha;

  Map<String, dynamic> toJson() =>
      {'id': id, 'pedido_id': pedidoId, 'total': total, 'fecha': fecha.toUtc().toIso8601String()};
}

/// La central del restaurante: guarda usuarios, menú, pedidos y ventas en la
/// tablet de cocina y aplica las reglas del negocio. Funciona sin internet.
///
/// Todas las escrituras pasan por [_confirmar]: se escriben primero en el
/// [Diario] y solo después se aplican en memoria, en serie, para que dos
/// peticiones simultáneas no se pisen.
class Central {
  Central._(this._diario, this._iteraciones, this._reloj);

  final Diario _diario;
  final int _iteraciones;
  final DateTime Function() _reloj;

  /// Avisos en tiempo real (`nuevo_pedido`, `pedido_actualizado`, `extra_pedido`, `pedido_eliminado`).
  Emisor? emitir;

  final _usuarios = <int, UsuarioCentral>{};
  final _productos = <int, ProductoCentral>{};
  final _pedidos = <int, PedidoCentral>{};
  final _ventas = <int, VentaCentral>{};

  /// Identificador de operación del cliente → pedido resultante (evita duplicados en reintentos).
  final _operaciones = <String, ({int pedidoId, DateTime fecha})>{};
  final _secuencias = <String, int>{};
  Map<String, dynamic> _config = {};
  Future<void> _cola = Future.value();

  static const _lineasParaCompactar = 3000;

  static Future<Central> abrir(
    Directory carpeta, {
    int iteraciones = 60000,
    DateTime Function()? reloj,
  }) async {
    final central = Central._(Diario(carpeta), iteraciones, reloj ?? DateTime.now);
    final lotes = await central._diario.cargar();
    for (final lote in lotes) {
      central._aplicar(lote);
    }
    if (central._diario.lineas > _lineasParaCompactar) await central._compactar();
    return central;
  }

  bool get inicializada => _usuarios.values.any((u) => u.rol == 'admin');
  String get codigoEnlace => _config['enlace'] as String? ?? '';
  String get nombre => _config['nombre'] as String? ?? 'Restaurante 3 Pisos';
  String get _secreto => _config['secreto'] as String;

  Future<void> cerrar() => _diario.cerrar();

  // ── Persistencia ─────────────────────────────────────────

  void _aplicar(List<Map<String, dynamic>> lote) {
    for (final r in lote) {
      final v = r['v'] as Map<String, dynamic>?;
      switch (r['t']) {
        case 'config':
          _config = {..._config, ...v!};
        case 'usuario':
          final u = UsuarioCentral.fromJson(v!);
          _usuarios[u.id] = u;
          _verId('usuario', u.id);
        case 'producto':
          final p = ProductoCentral.fromJson(v!);
          _productos[p.id] = p;
          _verId('producto', p.id);
        case 'pedido':
          final p = PedidoCentral.fromJson(v!);
          _pedidos[p.id] = p;
          _verId('pedido', p.id);
          for (final i in p.items) {
            _verId('item', i.id);
          }
        case 'venta':
          final venta = VentaCentral.fromJson(v!);
          _ventas[venta.id] = venta;
          _verId('venta', venta.id);
        case 'borrar':
          final id = r['id'] as int;
          switch (r['tabla']) {
            case 'usuario':
              _usuarios.remove(id);
            case 'producto':
              _productos.remove(id);
            case 'pedido':
              _pedidos.remove(id);
          }
        case 'op':
          _operaciones[r['id'] as String] = (
            pedidoId: r['pedido'] as int,
            fecha: DateTime.parse(r['fecha'] as String),
          );
        case 'seq':
          for (final MapEntry(:key, :value) in v!.entries) {
            _verId(key, value as int);
          }
      }
    }
  }

  void _verId(String tabla, int id) {
    if (id > (_secuencias[tabla] ?? 0)) _secuencias[tabla] = id;
  }

  int _siguiente(String tabla) => _secuencias[tabla] = (_secuencias[tabla] ?? 0) + 1;

  /// Serializa las operaciones que modifican datos.
  Future<T> _enSerie<T>(Future<T> Function() operacion) {
    final resultado = _cola.then((_) => operacion());
    _cola = resultado.then((_) {}, onError: (_) {});
    return resultado;
  }

  Future<void> _confirmar(List<Map<String, dynamic>> lote) async {
    await _diario.escribir(lote);
    _aplicar(lote);
    if (_diario.lineas > _lineasParaCompactar) await _compactar();
  }

  List<Map<String, dynamic>> _estadoCompleto() => [
        {'t': 'config', 'v': _config},
        {'t': 'seq', 'v': _secuencias},
        for (final u in _usuarios.values) {'t': 'usuario', 'v': u.toJson()},
        for (final p in _productos.values) {'t': 'producto', 'v': p.toJson()},
        for (final p in _pedidos.values) {'t': 'pedido', 'v': p.toJson()},
        for (final v in _ventas.values) {'t': 'venta', 'v': v.toJson()},
        for (final MapEntry(:key, :value) in _operaciones.entries)
          {'t': 'op', 'id': key, 'pedido': value.pedidoId, 'fecha': value.fecha.toUtc().toIso8601String()},
      ];

  Future<void> _compactar() async {
    final limite = _reloj().subtract(const Duration(days: 7));
    _operaciones.removeWhere((_, op) => op.fecha.isBefore(limite));
    await _diario.compactar(_estadoCompleto());
  }

  // ── Respaldo ─────────────────────────────────────────────

  /// Copia de todo lo que guarda la central, para cifrarla en un archivo de respaldo.
  Future<List<Map<String, dynamic>>> exportar() => _enSerie(() async => _estadoCompleto());

  /// Carga un respaldo en una central **vacía** (tablet nueva). Nunca sobrescribe
  /// datos existentes. Conserva el código de enlace, así las tablets de los
  /// meseros solo tienen que buscar la nueva IP; las sesiones se cierran porque
  /// se genera un secreto nuevo.
  Future<void> restaurar(List<Map<String, dynamic>> registros) => _enSerie(() async {
        if (_usuarios.isNotEmpty || _pedidos.isNotEmpty) {
          throw ErrorCentral(409, 'CENTRAL_CON_DATOS', 'Esta tablet ya tiene datos de una central; no se sobrescriben.');
        }
        final validado = _validarRespaldo(registros);
        final lote = [
          for (final r in validado)
            if (r['t'] == 'config') {'t': 'config', 'v': {...r['v'] as Map<String, dynamic>, 'secreto': idAleatorio(32)}} else r,
        ];
        await _diario.compactar(lote);
        _aplicar(lote);
      });

  /// Comprueba que el respaldo se pueda cargar entero antes de tocar nada.
  static List<Map<String, dynamic>> _validarRespaldo(List<Map<String, dynamic>> registros) {
    try {
      final prueba = Central._(Diario(Directory.systemTemp), 1, DateTime.now).._aplicar(registros);
      if (!prueba.inicializada || prueba.codigoEnlace.isEmpty) {
        throw ErrorCentral(400, 'RESPALDO_INVALIDO', 'El respaldo no tiene administrador ni configuración.');
      }
      return registros;
    } on ErrorCentral {
      rethrow;
    } on Object {
      throw ErrorCentral(400, 'RESPALDO_INVALIDO', 'El respaldo tiene datos inválidos.');
    }
  }

  // ── Instalación y enlace ─────────────────────────────────

  /// Primera puesta en marcha: crea el administrador y carga el menú del restaurante.
  Future<void> inicializar({
    required String admin,
    required String password,
    String? nombreRestaurante,
    List<Map<String, dynamic>> menu = const [],
  }) =>
      _enSerie(() async {
        if (inicializada) throw ErrorCentral(409, 'YA_INICIADA', 'La central ya está configurada.');
        final usuario = _validarUsuario(admin);
        _validarPassword(password);
        final ahora = _reloj();
        await _confirmar([
          {
            't': 'config',
            'v': {
              'secreto': idAleatorio(32),
              'enlace': nuevoCodigoEnlace(),
              'nombre': (nombreRestaurante?.trim().isNotEmpty ?? false) ? nombreRestaurante!.trim() : 'Restaurante 3 Pisos',
            },
          },
          {
            't': 'usuario',
            'v': UsuarioCentral(
              id: _siguiente('usuario'),
              username: usuario,
              passwordHash: await _hash(password),
              rol: 'admin',
              creadoEn: ahora,
            ).toJson(),
          },
          for (final p in menu)
            {
              't': 'producto',
              'v': ProductoCentral(
                id: _siguiente('producto'),
                nombre: p['nombre'].toString(),
                precio: double.parse(p['precio'].toString()),
                categoria: p['categoria']?.toString() ?? 'General',
                activo: p['activo'] != false,
                creadoEn: ahora,
              ).toJson(),
            },
        ]);
      });

  /// Cambia el código de enlace y cierra todas las sesiones (tablet perdida o código filtrado).
  Future<String> renovarEnlace() => _enSerie(() async {
        final nuevo = nuevoCodigoEnlace();
        await _confirmar([
          {
            't': 'config',
            'v': {'enlace': nuevo, 'secreto': idAleatorio(32)},
          },
        ]);
        return nuevo;
      });

  bool enlaceValido(String? codigo) =>
      codigo != null && codigoEnlace.isNotEmpty && normalizarCodigo(codigo) == codigoEnlace;

  // ── Sesiones y usuarios ──────────────────────────────────

  /// PBKDF2 va en otro isolate para no congelar la central (y su pantalla) durante el cálculo.
  Future<Map<String, dynamic>> login(String username, String password) async {
    final usuario = _usuarios.values.where((u) => u.username.toLowerCase() == username.trim().toLowerCase()).firstOrNull;
    final hash = usuario?.passwordHash;
    final valida = hash != null && await Isolate.run(() => verificarPassword(password, hash));
    if (usuario == null || !valida) {
      throw ErrorCentral(401, 'INVALID_CREDENTIALS', 'Usuario o contraseña incorrectos.');
    }
    final token = firmarToken(
      {'id': usuario.id, 'username': usuario.username, 'role': usuario.rol, 'ver': usuario.versionToken},
      _secreto,
    );
    return {'token': token, 'user': usuario.publico()};
  }

  /// Usuario vigente del token, o `null` si caducó, se revocó o el usuario ya no existe.
  UsuarioCentral? autenticar(String token) {
    final datos = verificarToken(token, _secreto, ahora: _reloj());
    if (datos == null) return null;
    final usuario = _usuarios[datos['id']];
    if (usuario == null || usuario.versionToken != datos['ver']) return null;
    return usuario;
  }

  List<Map<String, dynamic>> listarUsuarios() =>
      [for (final u in _usuarios.values.toList()..sort((a, b) => a.id.compareTo(b.id))) u.publico()];

  String _validarUsuario(Object? valor, {int? excepto}) {
    final username = valor?.toString().trim() ?? '';
    if (username.length < 3 || username.length > 30) {
      throw ErrorCentral(400, 'VALIDATION_ERROR', 'El nombre debe tener entre 3 y 30 caracteres.');
    }
    final repetido = _usuarios.values.any((u) => u.id != excepto && u.username.toLowerCase() == username.toLowerCase());
    if (repetido) throw ErrorCentral(409, 'DUPLICATE_USER', 'El nombre de usuario ya existe.');
    return username;
  }

  void _validarPassword(Object? valor) {
    if ((valor?.toString() ?? '').length < 6) {
      throw ErrorCentral(400, 'VALIDATION_ERROR', 'La contraseña debe tener al menos 6 caracteres.');
    }
  }

  String _validarRol(Object? valor) {
    final rol = valor?.toString() ?? 'mesero';
    if (!rolesValidos.contains(rol)) {
      throw ErrorCentral(400, 'VALIDATION_ERROR', 'Rol inválido. Valores: admin, mesero, cocina.');
    }
    return rol;
  }

  Future<Map<String, dynamic>> crearUsuario(Map<String, dynamic> datos) => _enSerie(() async {
        final username = _validarUsuario(datos['username']);
        _validarPassword(datos['password']);
        final usuario = UsuarioCentral(
          id: _siguiente('usuario'),
          username: username,
          passwordHash: await _hash(datos['password'].toString()),
          rol: _validarRol(datos['role']),
          creadoEn: _reloj(),
        );
        await _confirmar([
          {'t': 'usuario', 'v': usuario.toJson()},
        ]);
        return usuario.publico();
      });

  Future<Map<String, dynamic>> actualizarUsuario(int id, Map<String, dynamic> datos) => _enSerie(() async {
        final actual = _usuarios[id] ?? (throw ErrorCentral(404, 'USER_NOT_FOUND', 'Usuario no encontrado.'));
        final username = _validarUsuario(datos['username'], excepto: id);
        final rol = _validarRol(datos['role']);
        final password = datos['password']?.toString() ?? '';
        if (password.isNotEmpty) _validarPassword(password);
        if (actual.rol == 'admin' && rol != 'admin' && _admins() == 1) {
          throw ErrorCentral(400, 'LAST_ADMIN', 'Debe quedar al menos un administrador.');
        }
        final cambiaAcceso = password.isNotEmpty || rol != actual.rol;
        final usuario = UsuarioCentral(
          id: id,
          username: username,
          passwordHash: password.isNotEmpty ? await _hash(password) : actual.passwordHash,
          rol: rol,
          creadoEn: actual.creadoEn,
          versionToken: cambiaAcceso ? actual.versionToken + 1 : actual.versionToken,
        );
        await _confirmar([
          {'t': 'usuario', 'v': usuario.toJson()},
        ]);
        return usuario.publico();
      });

  Future<Map<String, dynamic>> eliminarUsuario(int id, {required int actorId}) => _enSerie(() async {
        final usuario = _usuarios[id] ?? (throw ErrorCentral(404, 'USER_NOT_FOUND', 'Usuario no encontrado.'));
        if (id == actorId) throw ErrorCentral(400, 'SELF_DELETE', 'No puedes eliminar tu propia cuenta.');
        if (usuario.rol == 'admin' && _admins() == 1) {
          throw ErrorCentral(400, 'LAST_ADMIN', 'Debe quedar al menos un administrador.');
        }
        await _confirmar([
          {'t': 'borrar', 'tabla': 'usuario', 'id': id},
        ]);
        return usuario.publico();
      });

  Future<String> _hash(String password) {
    final iteraciones = _iteraciones;
    return Isolate.run(() => hashPassword(password, iteraciones: iteraciones));
  }

  int _admins() => _usuarios.values.where((u) => u.rol == 'admin').length;

  // ── Productos ────────────────────────────────────────────

  List<Map<String, dynamic>> listarProductos() {
    final lista = _productos.values.toList()
      ..sort((a, b) {
        final c = a.categoria.compareTo(b.categoria);
        return c != 0 ? c : a.nombre.compareTo(b.nombre);
      });
    return [for (final p in lista) p.toJson()];
  }

  ProductoCentral _productoValidado(Map<String, dynamic> datos, {required int id, required DateTime creadoEn}) {
    final nombre = datos['nombre']?.toString().trim() ?? '';
    if (nombre.isEmpty || nombre.length > 100) {
      throw ErrorCentral(400, 'VALIDATION_ERROR', 'El nombre del producto es requerido (máximo 100 caracteres).');
    }
    final precio = double.tryParse(datos['precio']?.toString() ?? '');
    if (precio == null || precio <= 0) {
      throw ErrorCentral(400, 'VALIDATION_ERROR', 'El precio debe ser un número positivo.');
    }
    final categoria = datos['categoria']?.toString().trim();
    return ProductoCentral(
      id: id,
      nombre: nombre,
      precio: double.parse(precio.toStringAsFixed(2)),
      categoria: (categoria == null || categoria.isEmpty) ? 'General' : categoria,
      activo: datos['activo'] != false,
      creadoEn: creadoEn,
    );
  }

  Future<Map<String, dynamic>> crearProducto(Map<String, dynamic> datos) => _enSerie(() async {
        final producto = _productoValidado(datos, id: _siguiente('producto'), creadoEn: _reloj());
        await _confirmar([
          {'t': 'producto', 'v': producto.toJson()},
        ]);
        return producto.toJson();
      });

  Future<Map<String, dynamic>> actualizarProducto(int id, Map<String, dynamic> datos) => _enSerie(() async {
        final actual = _productos[id] ?? (throw ErrorCentral(404, 'PRODUCT_NOT_FOUND', 'Producto no encontrado.'));
        final producto = _productoValidado(datos, id: id, creadoEn: actual.creadoEn);
        await _confirmar([
          {'t': 'producto', 'v': producto.toJson()},
        ]);
        return producto.toJson();
      });

  /// Los pedidos guardan nombre y precio de cada renglón, así que borrar un
  /// producto no altera cuentas ni historial.
  Future<Map<String, dynamic>> eliminarProducto(int id) => _enSerie(() async {
        final producto = _productos[id] ?? (throw ErrorCentral(404, 'PRODUCT_NOT_FOUND', 'Producto no encontrado.'));
        await _confirmar([
          {'t': 'borrar', 'tabla': 'producto', 'id': id},
        ]);
        return producto.toJson();
      });

  // ── Pedidos ──────────────────────────────────────────────

  List<Map<String, dynamic>> listarPedidos({String? estado}) {
    final lista = _pedidos.values.where((p) => estado == null || !estadosValidos.contains(estado) || p.estado == estado).toList()
      ..sort((a, b) {
        final c = a.creadoEn.compareTo(b.creadoEn);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return [for (final p in lista) p.toJson()];
  }

  PedidoCentral _pedido(int id) =>
      _pedidos[id] ?? (throw ErrorCentral(404, 'ORDER_NOT_FOUND', 'Pedido no encontrado.'));

  Map<String, dynamic> obtenerPedido(int id) => _pedido(id).toJson();

  String? _nota(Object? valor) {
    final nota = valor?.toString().trim();
    if (nota == null || nota.isEmpty) return null;
    if (nota.length > 200) throw ErrorCentral(400, 'VALIDATION_ERROR', 'La nota no puede superar 200 caracteres.');
    return nota;
  }

  /// Convierte `[{producto_id, cantidad, nota}]` en renglones con precio vigente.
  List<ItemCentral> _itemsNuevos(Object? productos) {
    if (productos is! List || productos.isEmpty) {
      throw ErrorCentral(400, 'EMPTY_ORDER', 'Debe incluir al menos un producto.');
    }
    return [
      for (final p in productos.cast<Map<String, dynamic>>())
        () {
          final id = int.tryParse(p['producto_id'].toString());
          final cantidad = int.tryParse(p['cantidad'].toString()) ?? 0;
          if (cantidad < 1) throw ErrorCentral(400, 'VALIDATION_ERROR', 'La cantidad debe ser al menos 1.');
          final producto = _productos[id];
          if (producto == null || !producto.activo) {
            throw ErrorCentral(400, 'PRODUCT_NOT_FOUND', 'Producto $id no existe o está inactivo.');
          }
          return ItemCentral(
            id: 0, // se asigna al confirmar
            productoId: producto.id,
            nombre: producto.nombre,
            precio: producto.precio,
            cantidad: cantidad,
            nota: _nota(p['nota']),
          );
        }(),
    ];
  }

  List<ItemCentral> _numerar(List<ItemCentral> items) => [
        for (final i in items)
          ItemCentral(
            id: _siguiente('item'),
            productoId: i.productoId,
            nombre: i.nombre,
            precio: i.precio,
            cantidad: i.cantidad,
            nota: i.nota,
          ),
      ];

  int _mesa(Object? valor) {
    final mesa = int.tryParse(valor?.toString() ?? '');
    if (mesa == null || mesa < 1) {
      throw ErrorCentral(400, 'VALIDATION_ERROR', 'La mesa debe ser un número entero positivo.');
    }
    return mesa;
  }

  String _tipo(Object? valor) {
    final tipo = valor?.toString() ?? 'aqui';
    if (tipo != 'aqui' && tipo != 'llevar') {
      throw ErrorCentral(400, 'VALIDATION_ERROR', 'Tipo inválido. Valores: aqui, llevar.');
    }
    return tipo;
  }

  String? _comensal(Object? valor) {
    final comensal = valor?.toString().trim();
    if (comensal == null || comensal.isEmpty) return null;
    if (comensal.length > 50) {
      throw ErrorCentral(400, 'VALIDATION_ERROR', 'El comensal no puede superar 50 caracteres.');
    }
    return comensal;
  }

  /// Si la operación ya se procesó (reintento tras perder la respuesta), devuelve su pedido.
  Map<String, dynamic>? _yaProcesada(String? operacion) {
    if (operacion == null) return null;
    final previa = _operaciones[operacion];
    if (previa == null) return null;
    return _pedidos[previa.pedidoId]?.toJson();
  }

  Map<String, dynamic> _registroOperacion(String operacion, int pedidoId) =>
      {'t': 'op', 'id': operacion, 'pedido': pedidoId, 'fecha': _reloj().toUtc().toIso8601String()};

  Future<Map<String, dynamic>> crearPedido(
    Map<String, dynamic> datos, {
    required UsuarioCentral usuario,
    String? operacion,
  }) =>
      _enSerie(() async {
        final repetida = _yaProcesada(operacion);
        if (repetida != null) return repetida;

        final pedido = PedidoCentral(
          id: _siguiente('pedido'),
          mesa: _mesa(datos['mesa']),
          estado: 'pendiente',
          tipo: _tipo(datos['tipo']),
          comensal: _comensal(datos['comensal']),
          usuarioId: usuario.id,
          mesero: usuario.username,
          creadoEn: _reloj(),
          items: _numerar(_itemsNuevos(datos['productos'])),
        );
        await _confirmar([
          {'t': 'pedido', 'v': pedido.toJson()},
          if (operacion != null) _registroOperacion(operacion, pedido.id),
        ]);
        final json = pedido.toJson();
        emitir?.call('nuevo_pedido', json);
        return json;
      });

  /// Agrega productos. Sobre una cuenta pagada abre una cuenta nueva; sobre una
  /// lista, avisa a cocina solo con lo nuevo (`extra_pedido`).
  Future<Map<String, dynamic>> agregarProductos(
    int id,
    Map<String, dynamic> datos, {
    required UsuarioCentral usuario,
    String? operacion,
  }) =>
      _enSerie(() async {
        final repetida = _yaProcesada(operacion);
        if (repetida != null) return repetida;

        final pedido = _pedido(id);
        if (pedido.estado == 'cancelado') {
          throw ErrorCentral(400, 'INVALID_STATUS', 'No se puede modificar un pedido cancelado.');
        }
        final nuevos = _numerar(_itemsNuevos(datos['productos']));

        if (pedido.estado == 'pagado') {
          final cuenta = PedidoCentral(
            id: _siguiente('pedido'),
            mesa: pedido.mesa,
            estado: 'pendiente',
            tipo: pedido.tipo,
            comensal: pedido.comensal,
            usuarioId: usuario.id,
            mesero: usuario.username,
            creadoEn: _reloj(),
            items: nuevos,
          );
          await _confirmar([
            {'t': 'pedido', 'v': cuenta.toJson()},
            if (operacion != null) _registroOperacion(operacion, cuenta.id),
          ]);
          final json = cuenta.toJson();
          emitir?.call('nuevo_pedido', json);
          return json;
        }

        // Mismo producto y misma nota se suman; con otra nota va en renglón aparte.
        final items = [...pedido.items];
        for (final nuevo in nuevos) {
          final i = items.indexWhere((x) => x.productoId == nuevo.productoId && x.nota == nuevo.nota);
          if (i >= 0) {
            items[i] = items[i].copyWith(cantidad: items[i].cantidad + nuevo.cantidad);
          } else {
            items.add(nuevo);
          }
        }
        final actualizado = pedido.copyWith(items: items);
        await _confirmar([
          {'t': 'pedido', 'v': actualizado.toJson()},
          if (operacion != null) _registroOperacion(operacion, id),
        ]);

        final json = actualizado.toJson();
        if (pedido.estado == 'listo') {
          emitir?.call('extra_pedido', {
            'pedido_id': id,
            'mesa': pedido.mesa,
            'tipo': pedido.tipo,
            'comensal': pedido.comensal,
            'items': [
              for (final n in nuevos) {'nombre': n.nombre, 'cantidad': n.cantidad, 'nota': n.nota, 'precio': n.precio},
            ],
            'total_extra': nuevos.fold<double>(0, (s, n) => s + n.precio * n.cantidad),
          });
        }
        emitir?.call('pedido_actualizado', {...json, '_accion': 'productos_agregados'});
        return json;
      });

  Future<Map<String, dynamic>> editarPedido(int id, Map<String, dynamic> datos) => _enSerie(() async {
        final pedido = _pedido(id);
        if (pedido.estado != 'pendiente' && pedido.estado != 'preparando') {
          throw ErrorCentral(400, 'INVALID_STATUS', 'Solo se pueden editar pedidos pendientes o en preparación.');
        }
        final cambios = datos['items'];
        final hayMetadatos = datos.containsKey('mesa') || datos.containsKey('tipo') || datos.containsKey('comensal');
        if ((cambios is! List || cambios.isEmpty) && !hayMetadatos) {
          throw ErrorCentral(400, 'EMPTY_FIELDS', 'Debe enviar al menos un campo a editar.');
        }

        var items = [...pedido.items];
        if (cambios is List) {
          for (final c in cambios.cast<Map<String, dynamic>>()) {
            final detalleId = int.tryParse(c['detalle_id'].toString());
            final cantidad = int.tryParse(c['cantidad'].toString()) ?? -1;
            if (cantidad < 0) throw ErrorCentral(400, 'VALIDATION_ERROR', 'Cantidad debe ser 0 o mayor.');
            if (cantidad == 0) {
              items = [for (final i in items) if (i.id != detalleId) i];
            } else {
              final nota = _nota(c['nota']);
              items = [
                for (final i in items)
                  if (i.id == detalleId) i.copyWith(cantidad: cantidad, nota: nota, borrarNota: nota == null) else i,
              ];
            }
          }
        }
        if (items.isEmpty) throw ErrorCentral(400, 'EMPTY_ORDER', 'El pedido no puede quedar sin productos.');

        final comensal = datos.containsKey('comensal') ? _comensal(datos['comensal']) : pedido.comensal;
        final actualizado = pedido.copyWith(
          mesa: datos.containsKey('mesa') ? _mesa(datos['mesa']) : null,
          tipo: datos.containsKey('tipo') ? _tipo(datos['tipo']) : null,
          comensal: comensal,
          borrarComensal: comensal == null,
          items: items,
        );
        await _confirmar([
          {'t': 'pedido', 'v': actualizado.toJson()},
        ]);
        final json = actualizado.toJson();
        emitir?.call('pedido_actualizado', {...json, '_accion': 'pedido_editado'});
        return json;
      });

  /// Cocina solo avanza la preparación o cancela lo que aún no termina; el cobro
  /// es de mesero y admin. Un pedido pagado o cancelado ya no cambia de estado.
  Future<Map<String, dynamic>> cambiarEstado(int id, String estado, {required UsuarioCentral usuario}) =>
      _enSerie(() async {
        if (!estadosValidos.contains(estado)) {
          throw ErrorCentral(400, 'INVALID_STATUS', 'Estado inválido. Valores: ${estadosValidos.join(', ')}.');
        }
        final pedido = _pedido(id);
        if (pedido.estado == 'pagado' || pedido.estado == 'cancelado') {
          throw ErrorCentral(400, 'INVALID_STATUS', 'El pedido ya está ${pedido.estado}.');
        }
        if (usuario.rol == 'cocina') {
          final permitido = estado == 'preparando' ||
              estado == 'listo' ||
              (estado == 'cancelado' && (pedido.estado == 'pendiente' || pedido.estado == 'preparando'));
          if (!permitido) throw ErrorCentral(403, 'FORBIDDEN', 'Cocina no puede cambiar el pedido a "$estado".');
        }
        final actualizado = pedido.copyWith(estado: estado);
        await _confirmar([
          {'t': 'pedido', 'v': actualizado.toJson()},
          if (estado == 'pagado')
            {
              't': 'venta',
              'v': VentaCentral(id: _siguiente('venta'), pedidoId: id, total: actualizado.total, fecha: _reloj())
                  .toJson(),
            },
        ]);
        final json = actualizado.toJson();
        emitir?.call('pedido_actualizado', json);
        return json;
      });

  /// Eliminar no es un reembolso: la venta registrada se conserva.
  Future<Map<String, dynamic>> eliminarPedido(int id) => _enSerie(() async {
        final pedido = _pedido(id);
        await _confirmar([
          {'t': 'borrar', 'tabla': 'pedido', 'id': id},
        ]);
        emitir?.call('pedido_eliminado', {'id': id});
        return pedido.toJson();
      });

  // ── Métricas (en hora local de la tablet) ────────────────

  DateTime _dia(DateTime f) {
    final l = f.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  Map<String, dynamic> resumen() {
    final hoy = _dia(_reloj());
    final lunes = hoy.subtract(Duration(days: hoy.weekday - 1));
    final ventasHoy = _ventas.values.where((v) => _dia(v.fecha) == hoy).fold<double>(0, (s, v) => s + v.total);
    final ventasSemana =
        _ventas.values.where((v) => !_dia(v.fecha).isBefore(lunes)).fold<double>(0, (s, v) => s + v.total);
    final pedidosHoy = _pedidos.values.where((p) => p.estado != 'cancelado' && _dia(p.creadoEn) == hoy).length;

    final estados = <String, int>{};
    for (final p in _pedidos.values) {
      estados[p.estado] = (estados[p.estado] ?? 0) + 1;
    }
    final porProducto = <String, int>{};
    for (final p in _pedidos.values.where((p) => p.estado != 'cancelado')) {
      for (final i in p.items) {
        porProducto[i.nombre] = (porProducto[i.nombre] ?? 0) + i.cantidad;
      }
    }
    final top = porProducto.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return {
      'dia': {'total_ventas': ventasHoy, 'total_pedidos': pedidosHoy},
      'semana': ventasSemana,
      'estados': [
        for (final e in (estados.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
          {'estado': e.key, 'cantidad': e.value},
      ],
      'productosTop': [
        for (final e in top.take(5)) {'nombre': e.key, 'total_pedido': e.value},
      ],
    };
  }

  /// Ventas cobradas agrupadas por día local: `[{fecha: 'AAAA-MM-DD', pedidos, total}]`.
  List<Map<String, dynamic>> ventasPorDia(int dias) {
    final desde = _dia(_reloj()).subtract(Duration(days: dias));
    final grupos = <DateTime, ({int pedidos, double total})>{};
    for (final v in _ventas.values) {
      final dia = _dia(v.fecha);
      if (dia.isBefore(desde)) continue;
      final previo = grupos[dia] ?? (pedidos: 0, total: 0.0);
      grupos[dia] = (pedidos: previo.pedidos + 1, total: previo.total + v.total);
    }
    final dias0 = grupos.keys.toList()..sort();
    String dosDigitos(int n) => n.toString().padLeft(2, '0');
    return [
      for (final d in dias0)
        {
          'fecha': '${d.year}-${dosDigitos(d.month)}-${dosDigitos(d.day)}',
          'pedidos': grupos[d]!.pedidos,
          'total': double.parse(grupos[d]!.total.toStringAsFixed(2)),
        },
    ];
  }
}
