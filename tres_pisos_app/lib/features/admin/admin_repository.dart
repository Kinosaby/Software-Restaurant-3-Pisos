import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../auth/auth_controller.dart';
import '../auth/sesion.dart';
import '../pedidos/modelos.dart';

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(apiClientProvider)),
);

class ResumenMetricas {
  const ResumenMetricas({
    required this.ventasHoy,
    required this.pedidosHoy,
    required this.ventasSemana,
    required this.porEstado,
    required this.productosTop,
  });

  /// Forma de `GET /api/metricas/resumen`.
  factory ResumenMetricas.fromJson(Map<String, dynamic> json) {
    final dia = json['dia'] as Map<String, dynamic>? ?? const {};
    return ResumenMetricas(
      ventasHoy: leerDinero(dia['total_ventas']),
      pedidosHoy: leerEntero(dia['total_pedidos']),
      ventasSemana: leerDinero(json['semana']),
      porEstado: {
        for (final e in (json['estados'] as List? ?? const []))
          if (e is Map) EstadoPedido.desde(e['estado']?.toString()): leerEntero(e['cantidad']),
      },
      productosTop: [
        for (final p in (json['productosTop'] as List? ?? const []))
          if (p is Map) (nombre: p['nombre']?.toString() ?? '', cantidad: leerEntero(p['total_pedido'])),
      ],
    );
  }

  final double ventasHoy;
  final int pedidosHoy;
  final double ventasSemana;
  final Map<EstadoPedido, int> porEstado;
  final List<({String nombre, int cantidad})> productosTop;
}

class VentaDia {
  const VentaDia({required this.fecha, required this.pedidos, required this.total});

  /// `fecha` llega como "AAAA-MM-DD" (día local de la central). Se lee solo esa
  /// parte: convertir una fecha con hora a local podría moverla al día anterior.
  factory VentaDia.fromJson(Map<String, dynamic> json) {
    final texto = json['fecha']?.toString() ?? '';
    final soloFecha = texto.length >= 10 ? texto.substring(0, 10) : texto;
    return VentaDia(
      fecha: DateTime.tryParse(soloFecha) ?? DateTime(1970),
      pedidos: leerEntero(json['pedidos']),
      total: leerDinero(json['total']),
    );
  }

  final DateTime fecha;
  final int pedidos;
  final double total;
}

/// Endpoints de administración: productos, usuarios y métricas (todos requieren rol admin).
class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  // ── Productos ──────────────────────────────────────────────
  Future<List<Producto>> productos() async {
    final datos = await _api.get('/api/productos');
    return [
      for (final p in (datos['productos'] as List? ?? const []))
        if (p is Map<String, dynamic>) Producto.fromJson(p),
    ];
  }

  Future<Producto> guardarProducto({
    int? id,
    required String nombre,
    required double precio,
    required String categoria,
    required bool activo,
  }) async {
    final cuerpo = {'nombre': nombre, 'precio': precio, 'categoria': categoria, 'activo': activo};
    final datos = id == null
        ? await _api.post('/api/productos', cuerpo)
        : await _api.put('/api/productos/$id', cuerpo);
    return Producto.fromJson(datos['producto'] as Map<String, dynamic>);
  }

  Future<void> eliminarProducto(int id) => _api.delete('/api/productos/$id');

  // ── Usuarios ───────────────────────────────────────────────
  Future<List<Usuario>> usuarios() async {
    final datos = await _api.get('/api/auth/usuarios');
    return [
      for (final u in (datos['usuarios'] as List? ?? const []))
        if (u is Map<String, dynamic>) Usuario.fromJson(u),
    ];
  }

  /// Crea (sin [id]) o actualiza un usuario. Al editar, una contraseña vacía la deja igual.
  Future<void> guardarUsuario({int? id, required String username, required Rol rol, String? password}) async {
    final cuerpo = {
      'username': username,
      'role': rol.name,
      if (password != null && password.isNotEmpty) 'password': password,
    };
    if (id == null) {
      await _api.post('/api/auth/register', cuerpo);
    } else {
      await _api.put('/api/auth/$id', cuerpo);
    }
  }

  Future<void> eliminarUsuario(int id) => _api.delete('/api/auth/$id');

  // ── Métricas ───────────────────────────────────────────────
  Future<ResumenMetricas> resumen() async => ResumenMetricas.fromJson(await _api.get('/api/metricas/resumen'));

  Future<List<VentaDia>> ventas({int dias = 7}) async {
    final datos = await _api.get('/api/metricas/ventas', query: {'dias': dias});
    return [
      for (final v in (datos['ventas'] as List? ?? const []))
        if (v is Map<String, dynamic>) VentaDia.fromJson(v),
    ];
  }
}
