import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/features/auth/sesion.dart';
import 'package:tres_pisos_app/features/mesero/editar_pedido_page.dart';
import 'package:tres_pisos_app/features/mesero/pedido_detalle_page.dart';
import 'package:tres_pisos_app/features/pedidos/modelos.dart';

import 'modelos_test.dart' show pedidoJson;

void main() {
  Pedido pedido(String estado, {bool pagado = false}) => Pedido.fromJson({
        ...pedidoJson(estado: estado),
        if (pagado) 'pago': {'efectivo': 132, 'tarjeta': 0, 'fecha': '2026-09-22T18:40:00.000Z'},
      });

  test('una cuenta lista y sin cobrar se puede editar y cancelar, igual que en cocina', () {
    for (final estado in ['pendiente', 'preparando', 'listo']) {
      for (final rol in [Rol.mesero, Rol.admin]) {
        expect(puedeEditarPedido(pedido(estado), rol), isTrue, reason: '$estado · $rol');
        expect(puedeCancelarPedido(pedido(estado), rol), isTrue, reason: '$estado · $rol');
      }
      expect(puedeEditarse(pedido(estado)), isTrue, reason: estado);
      expect(puedeEditarPedido(pedido(estado), Rol.cocina), isFalse);
      expect(puedeCancelarPedido(pedido(estado), Rol.cocina), isFalse);
      expect(puedeEditarPedido(pedido(estado), null), isFalse);
    }
  });

  test('ya cobrada no se edita, y solo el administrador la cancela (devolviendo el dinero)', () {
    // Cobrada por adelantado (sigue en cocina) o lista con un extra pendiente.
    for (final estado in ['pendiente', 'preparando', 'listo']) {
      final cobrada = pedido(estado, pagado: true);
      expect(puedeEditarPedido(cobrada, Rol.mesero), isFalse, reason: estado);
      expect(puedeEditarPedido(cobrada, Rol.admin), isFalse, reason: estado);
      expect(puedeEditarse(cobrada), isFalse, reason: estado);
      expect(puedeCancelarPedido(cobrada, Rol.mesero), isFalse, reason: estado);
      expect(puedeCancelarPedido(cobrada, Rol.admin), isTrue, reason: estado);
    }
  });

  test('cerrada o cancelada ya no ofrece editar ni cancelar', () {
    for (final estado in ['pagado', 'cancelado']) {
      expect(puedeEditarPedido(pedido(estado), Rol.admin), isFalse, reason: estado);
      expect(puedeCancelarPedido(pedido(estado), Rol.admin), isFalse, reason: estado);
      expect(puedeEditarse(pedido(estado)), isFalse, reason: estado);
    }
  });
}
