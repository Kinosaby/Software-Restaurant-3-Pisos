import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/features/pedidos/modelos.dart';
import 'package:tres_pisos_app/features/pedidos/pedidos_controller.dart';

/// Forma exacta en que el backend devuelve un pedido (QUERY_DETALLE en pedidos.service.js).
Map<String, dynamic> pedidoJson({
  int id = 7,
  String estado = 'pendiente',
  String creadoEn = '2026-09-22T18:30:00.000Z',
}) =>
    {
      'id': id,
      'mesa': 4,
      'estado': estado,
      'total': '132.00',
      'tipo': 'aqui',
      'comensal': null,
      'usuario_id': 2,
      'creado_en': creadoEn,
      'productos': [
        {'id': 11, 'producto_id': 2, 'nombre': 'Tacos de Pastor', 'cantidad': 2, 'nota': '', 'precio': '42.00'},
        {'id': 12, 'producto_id': 4, 'nombre': 'Agua de Jamaica', 'cantidad': 1, 'nota': 'sin hielo', 'precio': 48},
      ],
    };

void main() {
  test('Pedido.fromJson lee importes como texto y normaliza notas vacías', () {
    final pedido = Pedido.fromJson(pedidoJson());

    expect(pedido.id, 7);
    expect(pedido.mesa, 4);
    expect(pedido.estado, EstadoPedido.pendiente);
    expect(pedido.tipo, TipoPedido.aqui);
    expect(pedido.total, 132.0);
    expect(pedido.comensal, isNull);
    expect(pedido.piezas, 3);
    expect(pedido.items.first.subtotal, 84.0);
    expect(pedido.items.first.nota, isNull, reason: 'una nota vacía no debe mostrarse');
    expect(pedido.items.last.nota, 'sin hielo');
    expect(pedido.titulo, 'Mesa 4');
  });

  test('título de pedido para llevar con nombre del cliente', () {
    final pedido = Pedido.fromJson({...pedidoJson(), 'tipo': 'llevar', 'comensal': 'Ana'});
    expect(pedido.titulo, 'Para llevar · Ana');
  });

  test('ExtraPedido.fromJson lee el evento extra_pedido', () {
    final extra = ExtraPedido.fromJson({
      'pedido_id': '9',
      'mesa': 3,
      'tipo': 'aqui',
      'items': [
        {'nombre': 'Refresco', 'cantidad': 2, 'nota': null, 'precio': '22.00'},
      ],
      'total_extra': 44,
    });
    expect(extra.pedidoId, 9);
    expect(extra.items.single.nombre, 'Refresco');
    expect(extra.items.single.subtotal, 44.0);
  });

  test('estados activos y modificables', () {
    expect(EstadoPedido.listo.activo, isTrue);
    expect(EstadoPedido.pagado.activo, isFalse);
    expect(EstadoPedido.cancelado.activo, isFalse);
    expect(EstadoPedido.preparando.modificable, isTrue);
    expect(EstadoPedido.listo.modificable, isFalse);
  });

  group('reemplazarPedido', () {
    final antiguo = Pedido.fromJson(pedidoJson(id: 1, creadoEn: '2026-09-22T18:00:00Z'));
    final reciente = Pedido.fromJson(pedidoJson(id: 2, creadoEn: '2026-09-22T19:00:00Z'));

    test('mantiene orden FIFO al insertar', () {
      final lista = reemplazarPedido([reciente], antiguo);
      expect(lista.map((p) => p.id), [1, 2]);
    });

    test('actualiza un pedido existente sin duplicarlo', () {
      final preparando = Pedido.fromJson(pedidoJson(id: 1, estado: 'preparando', creadoEn: '2026-09-22T18:00:00Z'));
      final lista = reemplazarPedido([antiguo, reciente], preparando);
      expect(lista.map((p) => p.id), [1, 2]);
      expect(lista.first.estado, EstadoPedido.preparando);
    });

    test('quita los pedidos pagados o cancelados', () {
      final pagado = Pedido.fromJson(pedidoJson(id: 2, estado: 'pagado'));
      expect(reemplazarPedido([antiguo, reciente], pagado).map((p) => p.id), [1]);
    });
  });
}
