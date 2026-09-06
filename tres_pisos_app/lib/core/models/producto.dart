// lib/core/models/producto.dart
class Producto {
  final int    id;
  final String nombre;
  final double precio;
  final String categoria;
  final bool   activo;

  Producto({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.categoria,
    required this.activo,
  });

  factory Producto.fromJson(Map<String, dynamic> j) => Producto(
    id:     j['id'],
    nombre: j['nombre'] ?? '',
    precio: double.tryParse(j['precio'].toString()) ?? 0,
    categoria: j['categoria']?.toString() ?? 'General',
    activo: j['activo'] == true || j['activo'] == 1,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'precio': precio,
    'categoria': categoria,
    'activo': activo,
  };
}
