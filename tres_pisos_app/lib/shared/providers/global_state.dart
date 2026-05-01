// lib/shared/providers/global_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/pedido.dart';
import '../../core/models/producto.dart';
import '../../core/models/user.dart';

// ─── Carrito ───────────────────────────────────────────────
class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void add(Producto p) {
    final idx = state.indexWhere((i) => i.productoId == p.id);
    if (idx >= 0) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == idx) CartItem(productoId: state[i].productoId, nombre: state[i].nombre, precio: state[i].precio, cantidad: state[i].cantidad + 1, nota: state[i].nota)
          else state[i]
      ];
    } else {
      state = [...state, CartItem(productoId: p.id, nombre: p.nombre, precio: p.precio)];
    }
  }

  void changeQty(int productoId, int delta) {
    state = state
        .map((i) => i.productoId == productoId
            ? (CartItem(productoId: i.productoId, nombre: i.nombre, precio: i.precio, cantidad: i.cantidad + delta, nota: i.nota))
            : i)
        .where((i) => i.cantidad > 0)
        .toList();
  }

  void setNota(int productoId, String nota) {
    state = state.map((i) => i.productoId == productoId
        ? CartItem(productoId: i.productoId, nombre: i.nombre, precio: i.precio, cantidad: i.cantidad, nota: nota)
        : i).toList();
  }

  void clear() => state = [];

  double get total => state.fold(0, (sum, i) => sum + i.subtotal);
  int    get count => state.fold(0, (sum, i) => sum + i.cantidad);
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) => CartNotifier());

// ─── Pedidos ───────────────────────────────────────────────
final pedidosProvider = StateProvider<List<Pedido>>((ref) => []);

// ─── Productos ────────────────────────────────────────────
final productosProvider = StateProvider<List<Producto>>((ref) => []);

// ─── Usuarios ─────────────────────────────────────────────
final usuariosProvider = StateProvider<List<UserModel>>((ref) => []);

// ─── Loading ──────────────────────────────────────────────
final loadingProvider = StateProvider<bool>((ref) => false);

// ─── Socket status ────────────────────────────────────────
final socketConnectedProvider = StateProvider<bool>((ref) => false);
