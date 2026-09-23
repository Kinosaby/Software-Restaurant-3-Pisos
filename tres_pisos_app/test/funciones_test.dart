import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/features/admin/metricas_page.dart';
import 'package:tres_pisos_app/features/auth/sesion.dart';
import 'package:tres_pisos_app/features/avisos/avisos.dart';
import 'package:tres_pisos_app/features/caja/cobro.dart';
import 'package:tres_pisos_app/features/cocina/cocina_page.dart';
import 'package:tres_pisos_app/features/mesas/mesas.dart';
import 'package:tres_pisos_app/features/mesero/carrito.dart';
import 'package:tres_pisos_app/features/pedidos/modelos.dart';
import 'package:tres_pisos_app/features/pedidos/tiempo_real.dart';

Pedido pedido({
  required int id,
  int mesa = 1,
  String estado = 'pendiente',
  String tipo = 'aqui',
  int? usuarioId,
  String? comensal,
  String creadoEn = '2026-09-22T18:00:00Z',
  List<Map<String, dynamic>>? productos,
}) =>
    Pedido.fromJson({
      'id': id,
      'mesa': mesa,
      'estado': estado,
      'tipo': tipo,
      'total': '50.00',
      'comensal': comensal,
      'usuario_id': usuarioId,
      'creado_en': creadoEn,
      'productos': productos ??
          [
            {'id': id * 10, 'producto_id': 1, 'nombre': 'Tacos', 'cantidad': 1, 'nota': null, 'precio': '50.00'},
          ],
    });

void main() {
  group('para llevar dentro de la nota', () {
    test('se lee y se compone igual que en la web', () {
      expect(leerNota('[LLEVAR] sin cebolla'), (llevar: true, nota: 'sin cebolla'));
      expect(leerNota('[LLEVAR]'), (llevar: true, nota: null));
      expect(leerNota('sin cebolla'), (llevar: false, nota: 'sin cebolla'));
      expect(componerNota(llevar: true, nota: ' dorados '), '[LLEVAR] dorados');
      expect(componerNota(llevar: true), '[LLEVAR]');
      expect(componerNota(llevar: false, nota: '  '), isNull);
    });

    test('la línea del carrito manda la marca en la nota', () {
      const producto = Producto(id: 4, nombre: 'Agua', precio: 18, categoria: 'Bebidas', activo: true);
      const linea = LineaCarrito(producto: producto, cantidad: 2, llevar: true, nota: 'sin hielo');
      expect(linea.toJson(), {'producto_id': 4, 'cantidad': 2, 'nota': '[LLEVAR] sin hielo'});
    });
  });

  test('jueves a domingo como en la web', () {
    List<int> dias(DateTime hoy) => diasFinDeSemana(hoy).map((d) => d.day).toList();
    // Septiembre 2026: jueves 17, domingo 20, lunes 21, miércoles 23, jueves 24.
    expect(dias(DateTime(2026, 9, 21)), [17, 18, 19, 20], reason: 'lunes: fin de semana pasado');
    expect(dias(DateTime(2026, 9, 23)), [17, 18, 19, 20], reason: 'miércoles: fin de semana pasado');
    expect(dias(DateTime(2026, 9, 24)), [24, 25, 26, 27], reason: 'jueves: el actual');
    expect(dias(DateTime(2026, 9, 27)), [24, 25, 26, 27], reason: 'domingo: el actual');
  });

  test('montos sugeridos para cobrar en efectivo', () {
    expect(montosSugeridos(137), [140, 150, 200, 500]);
    // Con un total "redondo" solo tiene sentido un billete mayor.
    expect(montosSugeridos(200), [500, 1000]);
  });

  test('estado de las mesas: manda la cuenta más urgente', () {
    final mesas = estadoMesas([
      pedido(id: 1, mesa: 2, estado: 'pendiente'),
      pedido(id: 2, mesa: 2, estado: 'listo'),
      pedido(id: 3, mesa: 5, estado: 'preparando'),
      pedido(id: 4, mesa: 20),
    ]);
    expect(mesas.length, 14, reason: '13 mesas y la 20, que tiene cuenta');
    expect(mesas.firstWhere((m) => m.numero == 2).situacion, SituacionMesa.lista);
    expect(mesas.firstWhere((m) => m.numero == 2).porCobrar.single.id, 2);
    expect(mesas.firstWhere((m) => m.numero == 5).situacion, SituacionMesa.enCocina);
    expect(mesas.firstWhere((m) => m.numero == 1).situacion, SituacionMesa.libre);
  });

  test('cocina agrupa por mesa y deja cada pedido para llevar aparte', () {
    final grupos = agruparCocina([
      pedido(id: 1, mesa: 3, creadoEn: '2026-09-22T18:10:00Z'),
      pedido(id: 2, mesa: 3, estado: 'preparando', creadoEn: '2026-09-22T18:20:00Z'),
      pedido(id: 3, tipo: 'llevar', comensal: 'Ana', creadoEn: '2026-09-22T18:00:00Z'),
      pedido(id: 4, tipo: 'llevar', creadoEn: '2026-09-22T18:30:00Z'),
      pedido(id: 5, mesa: 4, estado: 'listo'),
    ]);
    expect(grupos.map((g) => g.titulo), ['Para llevar · Ana', 'Mesa 3', 'Para llevar']);
    expect(grupos[1].pedidos.map((p) => p.id), [1, 2]);
    expect(grupos[1].hayPendientes, isTrue);
  });

  test('repetir pedido: precio actual y sin productos que ya no existen', () {
    final anterior = pedido(id: 7, mesa: 6, productos: [
      {'id': 1, 'producto_id': 1, 'nombre': 'Tacos', 'cantidad': 3, 'nota': '[LLEVAR] dorados', 'precio': '40'},
      {'id': 2, 'producto_id': 99, 'nombre': 'Ya no existe', 'cantidad': 1, 'nota': null, 'precio': '10'},
    ]);
    final plantilla = PlantillaPedido.desde(anterior, const [
      Producto(id: 1, nombre: 'Tacos', precio: 45, categoria: 'Tacos', activo: true),
    ]);
    expect(plantilla.mesa, 6);
    expect(plantilla.lineas.single.cantidad, 3);
    expect(plantilla.lineas.single.subtotal, 135, reason: 'al precio de hoy');
    expect(plantilla.lineas.single.llevar, isTrue);
    expect(plantilla.lineas.single.nota, 'dorados');
  });

  group('avisos', () {
    const mesero = Usuario(id: 5, username: 'luis', rol: Rol.mesero);
    const cocina = Usuario(id: 9, username: 'chef', rol: Rol.cocina);

    test('cocina: pedidos nuevos y extras, una sola vez por pedido', () {
      final reglas = ReglasAviso(cocina);
      final nuevo = PedidoCambiado(pedido(id: 1, mesa: 4), nuevo: true);
      expect(reglas.evaluar(nuevo)?.sonido, 'pedido');
      expect(reglas.evaluar(nuevo), isNull);
      expect(
        reglas.evaluar(ExtraRecibido(ExtraPedido.fromJson({'pedido_id': 1, 'mesa': 4, 'items': []}))),
        isNotNull,
      );
      expect(reglas.evaluar(PedidoCambiado(pedido(id: 1, estado: 'listo'), nuevo: false)), isNull);
    });

    test('mesero: solo sus pedidos listos o cancelados', () {
      final reglas = ReglasAviso(mesero);
      expect(reglas.evaluar(PedidoCambiado(pedido(id: 1, estado: 'listo', usuarioId: 6), nuevo: false)), isNull);
      final listo = PedidoCambiado(pedido(id: 2, estado: 'listo', usuarioId: 5), nuevo: false);
      expect(reglas.evaluar(listo)?.sonido, 'listo');
      expect(reglas.evaluar(listo), isNull, reason: 'no se repite');
      expect(reglas.evaluar(PedidoCambiado(pedido(id: 3, estado: 'cancelado', usuarioId: 5), nuevo: false))?.aviso.urgente,
          isTrue);
      expect(reglas.evaluar(PedidoCambiado(pedido(id: 4, usuarioId: 5), nuevo: true)), isNull);
    });
  });
}
