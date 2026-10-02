import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/core/formato.dart';
import 'package:tres_pisos_app/features/mesero/editar_pedido_page.dart';
import 'package:tres_pisos_app/features/pedidos/modelos.dart';

import 'modelos_test.dart' show pedidoJson;

void main() {
  // Renglones 11: 2× Tacos de Pastor sin nota; 12: 1× Agua de Jamaica "sin hielo".
  final pedido = Pedido.fromJson(pedidoJson());

  Map<int, RenglonEditado> sinCambios() => {
        for (final item in pedido.items) item.detalleId: (cantidad: item.cantidad, nota: item.nota),
      };

  test('sin cambios no manda items', () {
    expect(calcularCambios(pedido, sinCambios()), isEmpty);
  });

  test('manda solo los renglones cambiados, conservando su nota', () {
    final editado = sinCambios()..[12] = (cantidad: 3, nota: 'sin hielo');
    final cambios = calcularCambios(pedido, editado);

    expect(cambios, hasLength(1));
    expect(cambios.single.toJson(), {'detalle_id': 12, 'cantidad': 3, 'nota': 'sin hielo'});
  });

  test('cantidad 0 quita el renglón y un cambio de nota también cuenta', () {
    final editado = sinCambios()
      ..[11] = (cantidad: 0, nota: null)
      ..[12] = (cantidad: 1, nota: null);
    final cambios = calcularCambios(pedido, editado);

    expect(cambios.map((c) => c.toJson()), [
      {'detalle_id': 11, 'cantidad': 0, 'nota': null},
      {'detalle_id': 12, 'cantidad': 1, 'nota': null},
    ]);
  });

  test('la mesa interna para llevar se muestra como "Para llevar"', () {
    expect(etiquetaMesa(mesaParaLlevar), 'Para llevar');
    expect(etiquetaMesa(mesaParaLlevar, llevar: true), 'Para llevar');
    expect(etiquetaMesa(4), 'Mesa 4');
    expect(etiquetaMesa(4, llevar: true), 'Para llevar (mesa 4)');
  });

  group('mesa al guardar', () {
    final llevar = Pedido.fromJson({...pedidoJson(), 'mesa': mesaParaLlevar, 'tipo': 'llevar'});

    test('para llevar no pide mesa y usa la interna', () {
      expect(mesaAlGuardar(llevar, TipoPedido.llevar, ''), mesaParaLlevar);
      expect(mesaAlGuardar(pedido, TipoPedido.llevar, ''), mesaParaLlevar);
    });

    test('pasar de llevar a aquí exige una mesa real', () {
      expect(mesaAlGuardar(llevar, TipoPedido.aqui, ''), isNull);
      expect(mesaAlGuardar(llevar, TipoPedido.aqui, '99'), isNull);
      expect(mesaAlGuardar(llevar, TipoPedido.aqui, '0'), isNull);
      expect(mesaAlGuardar(llevar, TipoPedido.aqui, ' 7 '), 7);
    });
  });
}
