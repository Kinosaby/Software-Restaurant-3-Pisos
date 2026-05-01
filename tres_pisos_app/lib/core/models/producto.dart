// lib/core/models/producto.dart
class Producto {
  final int    id;
  final String nombre;
  final double precio;
  final bool   activo;

  Producto({required this.id, required this.nombre, required this.precio, required this.activo});

  factory Producto.fromJson(Map<String, dynamic> j) => Producto(
    id:     j['id'],
    nombre: j['nombre'] ?? '',
    precio: double.tryParse(j['precio'].toString()) ?? 0,
    activo: j['activo'] == true || j['activo'] == 1,
  );

  Map<String, dynamic> toJson() => {'id': id, 'nombre': nombre, 'precio': precio, 'activo': activo};
}
