import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/features/mesero/carrito.dart';
import 'package:tres_pisos_app/features/pedidos/modelos.dart';

const tacos = Producto(id: 1, nombre: 'Tacos', precio: 45, categoria: 'Tacos', activo: true);
const agua = Producto(id: 2, nombre: 'Agua', precio: 18, categoria: 'Bebidas', activo: true);

void main() {
  late ProviderContainer container;
  late Carrito carrito;

  setUp(() {
    container = ProviderContainer();
    // Mantiene vivo el provider autoDispose durante la prueba.
    container.listen(carritoProvider, (_, _) {});
    carrito = container.read(carritoProvider.notifier);
  });
  tearDown(() => container.dispose());

  EstadoCarrito estado() => container.read(carritoProvider);

  test('agregar el mismo producto suma cantidad en una sola línea', () {
    carrito
      ..agregar(tacos)
      ..agregar(tacos)
      ..agregar(agua);

    expect(estado().lineasActivas, hasLength(2));
    expect(carrito.cantidadDe(tacos.id), 2);
    expect(estado().todasLasLineas.piezas, 3);
    expect(estado().todasLasLineas.total, 45 * 2 + 18);
  });

  test('bajar la cantidad a cero quita la línea', () {
    carrito
      ..agregar(tacos)
      ..cambiarCantidad(tacos.id, -1);
    expect(estado().vacio, isTrue);
  });

  test('las notas se recortan y una nota vacía se elimina', () {
    carrito
      ..agregar(tacos)
      ..fijarNota(tacos.id, '  sin cebolla ');
    expect(estado().lineasActivas.single.nota, 'sin cebolla');
    expect(estado().lineasActivas.single.toJson(), {'producto_id': 1, 'cantidad': 1, 'nota': 'sin cebolla'});

    carrito.fijarNota(tacos.id, '   ');
    expect(estado().lineasActivas.single.nota, isNull);
    expect(estado().lineasActivas.single.toJson().containsKey('nota'), isFalse);
  });

  group('comensales', () {
    test('un solo comensal sin renombrar se envía sin nombre', () {
      carrito.agregar(tacos);
      final solo = estado().porEnviar.single;
      expect(estado().nombreParaEnvio(solo), isNull);

      carrito.renombrarComensal(0, 'Ana');
      expect(estado().nombreParaEnvio(estado().porEnviar.single), 'Ana');
    });

    test('cada comensal lleva sus productos y su nombre', () {
      carrito
        ..agregar(tacos)
        ..agregarComensal()
        ..agregar(agua)
        ..agregar(agua);

      expect(estado().activo, 1);
      final envios = estado().porEnviar;
      expect(envios.map((c) => estado().nombreParaEnvio(c)), ['C1', 'C2']);
      expect(envios[0].lineas.single.producto.id, tacos.id);
      expect(envios[1].lineas.single.cantidad, 2);
      expect(estado().todasLasLineas.total, 45 + 18 * 2);
    });

    test('los comensales sin productos no se envían', () {
      carrito
        ..agregar(tacos)
        ..agregarComensal();
      expect(estado().porEnviar, hasLength(1));
    });

    test('quitar un comensal renumera los nombres automáticos', () {
      carrito
        ..agregarComensal()
        ..agregarComensal()
        ..renombrarComensal(2, 'Luis')
        ..quitarComensal(0);

      expect(estado().comensales.map((c) => c.nombre), ['C1', 'Luis']);
      expect(estado().activo, 1);
    });

    test('marcarEnviado vacía solo ese comensal para no duplicarlo al reintentar', () {
      carrito
        ..agregar(tacos)
        ..agregarComensal()
        ..agregar(agua);

      carrito.marcarEnviado(estado().comensales.first);
      expect(estado().porEnviar.single.nombre, 'C2');
      expect(estado().comensales, hasLength(2), reason: 'los nombres C1/C2 no deben cambiar');
    });

    test('editar un comensal que no es el activo', () {
      carrito
        ..agregar(tacos)
        ..agregarComensal()
        ..cambiarCantidad(tacos.id, 2, en: 0)
        ..fijarNota(tacos.id, 'dorados', en: 0);

      expect(estado().comensales[0].lineas.single.cantidad, 3);
      expect(estado().comensales[0].lineas.single.nota, 'dorados');
      expect(estado().comensales[1].lineas, isEmpty);
    });
  });
}
