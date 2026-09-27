import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/features/admin/historial_page.dart';
import 'package:tres_pisos_app/features/admin/metricas_page.dart';
import 'package:tres_pisos_app/features/auth/sesion.dart';
import 'package:tres_pisos_app/features/avisos/avisos.dart';
import 'package:tres_pisos_app/features/caja/cobro.dart';
import 'package:tres_pisos_app/features/caja/ticket.dart';
import 'package:tres_pisos_app/features/cocina/cocina_page.dart';
import 'package:tres_pisos_app/features/mesas/mesas.dart';
import 'package:tres_pisos_app/features/mesero/carrito.dart';
import 'package:tres_pisos_app/features/pedidos/modelos.dart';
import 'package:tres_pisos_app/features/pedidos/pedidos_controller.dart';
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

  group('pago mixto', () {
    test('en efectivo el cambio sale del total', () {
      final c = calcularCobro(total: 137, forma: FormaPago.efectivo, recibido: 200);
      expect((c.efectivo, c.tarjeta, c.cambio, c.valido), (137.0, 0.0, 63.0, true));
      expect(calcularCobro(total: 137, forma: FormaPago.efectivo, recibido: 100).valido, isFalse);
      expect(calcularCobro(total: 137, forma: FormaPago.efectivo).valido, isFalse, reason: 'falta lo recibido');
    });

    test('con tarjeta no pide efectivo', () {
      final c = calcularCobro(total: 137, forma: FormaPago.tarjeta, recibido: 500);
      expect((c.efectivo, c.tarjeta, c.recibido, c.valido), (0.0, 137.0, null, true));
      expect(c.pago.metodo, 'Tarjeta');
    });

    test('mixto: el cambio se calcula solo sobre la parte en efectivo', () {
      final c = calcularCobro(total: 350.50, forma: FormaPago.mixto, tarjeta: 200, recibido: 200);
      expect(c.efectivo, 150.5);
      expect(c.cambio, 49.5);
      expect(c.valido, isTrue);
      expect(c.pago.mixto, isTrue);
      expect(c.pago.metodo, 'Mixto');
      expect(c.pago.total, 350.5);

      expect(calcularCobro(total: 350.50, forma: FormaPago.mixto, tarjeta: 200, recibido: 100).valido, isFalse);
      expect(calcularCobro(total: 100, forma: FormaPago.mixto).valido, isFalse, reason: 'falta la parte con tarjeta');
      expect(calcularCobro(total: 100, forma: FormaPago.mixto, tarjeta: 120, recibido: 0).valido, isFalse);
      // Si la tarjeta cubre todo, no hace falta efectivo.
      expect(calcularCobro(total: 100, forma: FormaPago.mixto, tarjeta: 100).valido, isTrue);
    });

    test('sin errores de coma flotante', () {
      final c = calcularCobro(total: 0.1 + 0.2, forma: FormaPago.mixto, tarjeta: 0.1, recibido: 0.2);
      expect(c.efectivo, 0.2);
      expect(c.cambio, 0);
      expect(c.valido, isTrue);
    });

    test('el ticket muestra el desglose', () {
      expect(lineasPago(const Pago(efectivo: 150.5, tarjeta: 200, recibido: 200)), [
        ('Efectivo', 150.5),
        ('Tarjeta', 200.0),
        ('Recibido en efectivo', 200.0),
        ('Cambio', 49.5),
      ]);
      expect(lineasPago(const Pago(tarjeta: 80)), [('Tarjeta', 80.0)]);
    });

    test('ticket e historial de cuentas cobradas antes del pago mixto', () {
      final antiguo = pedido(id: 1, estado: 'pagado');
      final nuevo = Pedido.fromJson({
        ...pedido(id: 2, estado: 'pagado').toJson(),
        'pago': {'efectivo': 20, 'tarjeta': 30, 'fecha': '2026-09-26T20:00:00Z'},
      });
      expect(antiguo.pago, isNull);
      expect(antiguo.cobrado, isTrue);
      expect(pagoDelTicket([antiguo], null), isNull, reason: 'sin desglose no se inventa');
      expect(pagoDelTicket([nuevo], null)?.tarjeta, 30);
      expect(pagoDelTicket([antiguo, nuevo], null), isNull);

      final resumen = resumenCobro([antiguo, nuevo, pedido(id: 3)]);
      expect(resumen, (total: 100.0, efectivo: 20.0, tarjeta: 30.0, sinDesglose: 50.0));
    });
  });

  group('cobrar pedidos que cocina no ha terminado', () {
    test('las cuentas en cocina se pueden cobrar con advertencia', () {
      expect(avisoEnCocina([pedido(id: 1, estado: 'listo')]), isNull);
      expect(avisoEnCocina([pedido(id: 1, estado: 'preparando')]), startsWith('Este pedido aún está en cocina.'));
      expect(
        avisoEnCocina([pedido(id: 1, estado: 'pendiente'), pedido(id: 2, estado: 'listo')]),
        startsWith('Una de las cuentas'),
      );
      // Lista, pero con un extra que cocina aún prepara.
      final conExtra = pedido(id: 3, estado: 'listo', productos: [
        {'id': 30, 'producto_id': 1, 'nombre': 'Tacos', 'cantidad': 1, 'nota': null, 'precio': '50.00'},
        {
          'id': 31,
          'producto_id': 2,
          'nombre': 'Refresco',
          'cantidad': 1,
          'nota': null,
          'precio': '22.00',
          'extra_desde': '2026-09-22T18:30:00Z',
        },
      ]);
      expect(avisoEnCocina([conExtra]), startsWith('Este pedido aún está en cocina.'));
    });

    test('una cuenta pagada por adelantado sigue en cocina pero ya no está por cobrar', () {
      final pagada = Pedido.fromJson({
        ...pedido(id: 1, mesa: 2, estado: 'preparando').toJson(),
        'pago': {'efectivo': 50, 'tarjeta': 0, 'fecha': '2026-09-26T20:00:00Z'},
      });
      final mesa = estadoMesas([pagada, pedido(id: 2, mesa: 2)]).firstWhere((m) => m.numero == 2);
      expect(mesa.porCobrar.map((p) => p.id), [2]);
      expect(agruparCocina([pagada]).single.pedidos.single.id, 1, reason: 'cocina la sigue viendo');
    });

    test('al terminarla cocina se avisa al mesero que la entregue', () {
      const mesero = Usuario(id: 5, username: 'luis', rol: Rol.mesero);
      final reglas = ReglasAviso(mesero);
      final cerrada = pedido(id: 8, estado: 'pagado', usuarioId: 5);
      expect(reglas.evaluar(PedidoCambiado(cerrada, nuevo: false)), isNull, reason: 'un cobro normal no avisa');
      final aviso = reglas.evaluar(PedidoCambiado(cerrada, nuevo: false, accion: 'listo_pagado'));
      expect(aviso?.aviso.mensaje, contains('ya pagada'));
      expect(reglas.evaluar(PedidoCambiado(cerrada, nuevo: false, accion: 'listo_pagado')), isNull);
    });
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
    // Se puede cobrar aunque cocina no haya terminado.
    expect(mesas.firstWhere((m) => m.numero == 2).porCobrar.map((p) => p.id), [1, 2]);
    expect(mesas.firstWhere((m) => m.numero == 5).situacion, SituacionMesa.enCocina);
    expect(mesas.firstWhere((m) => m.numero == 1).situacion, SituacionMesa.libre);
  });

  group('extras de un pedido listo', () {
    List<Map<String, dynamic>> conExtra({bool pendiente = true}) => [
          {'id': 1, 'producto_id': 1, 'nombre': 'Tacos', 'cantidad': 2, 'nota': null, 'precio': '40'},
          {
            'id': 2,
            'producto_id': 2,
            'nombre': 'Refresco',
            'cantidad': 1,
            'nota': null,
            'precio': '22',
            if (pendiente) 'extra_desde': '2026-09-22T18:30:00Z',
          },
        ];

    test('la mesa pasa a "En cocina" mientras el extra no esté terminado', () {
      final extra = pedido(id: 1, mesa: 4, estado: 'listo', productos: conExtra());
      expect(extra.conExtrasPendientes, isTrue);
      expect(extra.extrasPendientes.single.nombre, 'Refresco');
      expect(estadoMesas([extra]).firstWhere((m) => m.numero == 4).situacion, SituacionMesa.enCocina);

      // Cocina lo termina: la central quita la marca y la mesa vuelve a estar lista.
      final terminado = pedido(id: 1, mesa: 4, estado: 'listo', productos: conExtra(pendiente: false));
      expect(estadoMesas([terminado]).firstWhere((m) => m.numero == 4).situacion, SituacionMesa.lista);
    });

    test('otra cuenta ya lista de la misma mesa sigue mandando', () {
      final mesas = estadoMesas([
        pedido(id: 1, mesa: 4, estado: 'listo', productos: conExtra()),
        pedido(id: 2, mesa: 4, estado: 'listo'),
      ]);
      expect(mesas.firstWhere((m) => m.numero == 4).situacion, SituacionMesa.lista);
    });

    test('cocina ve el extra aparte y no vuelve a ver el pedido completo', () {
      final activos = [
        pedido(id: 1, mesa: 4, estado: 'listo', productos: conExtra()),
        pedido(id: 2, mesa: 5, estado: 'listo'),
      ];
      expect(extrasCocina(activos).map((p) => p.id), [1]);
      expect(agruparCocina(activos), isEmpty);
    });

    test('el mesero recibe "lista para servir" solo cuando el extra está terminado', () {
      final reglas = ReglasAviso(const Usuario(id: 5, username: 'luis', rol: Rol.mesero));
      PedidoCambiado cambio(List<Map<String, dynamic>> productos) =>
          PedidoCambiado(pedido(id: 1, estado: 'listo', usuarioId: 5, productos: productos), nuevo: false);

      expect(reglas.evaluar(cambio(conExtra())), isNull, reason: 'aún falta el extra');
      expect(reglas.evaluar(cambio(conExtra(pendiente: false)))?.sonido, 'listo');
      expect(reglas.evaluar(cambio(conExtra(pendiente: false))), isNull, reason: 'no se repite');
    });

    test('el renglón conserva la marca en la copia local', () {
      final item = PedidoItem.fromJson(conExtra()[1]);
      expect(PedidoItem.fromJson(item.toJson()).extraPendiente, isTrue);
      expect(PedidoItem.fromJson(conExtra()[0]).toJson().containsKey('extra_desde'), isFalse);
    });
  });

  group('pedidos en la cola sin conexión', () {
    EnvioPendiente envio({required int mesa, String tipo = 'aqui', String operacion = 'op-1', String accion = 'crear'}) =>
        EnvioPendiente(
          operacion: operacion,
          tipo: accion,
          pedidoId: accion == 'agregar' ? 9 : null,
          cuerpo: {
            'mesa': mesa,
            'tipo': tipo,
            'productos': [
              {'producto_id': 1, 'cantidad': 1},
            ],
          },
          creado: DateTime(2026, 9, 22, 18),
          resumen: 'Mesa $mesa',
          total: 50,
        );

    test('la mesa de un pedido que no se ha enviado ya no aparece libre', () {
      final mesas = estadoMesas(const [], cola: [envio(mesa: 3)]);
      final mesa3 = mesas.firstWhere((m) => m.numero == 3);
      expect(mesa3.situacion, SituacionMesa.sinEnviar);
      expect(mesa3.situacion, isNot(SituacionMesa.libre));
      expect(mesa3.sinEnviar, hasLength(1));
      expect(mesas.firstWhere((m) => m.numero == 1).situacion, SituacionMesa.libre);
    });

    test('para llevar y ampliaciones no ocupan mesa; una mesa fuera del salón sí aparece', () {
      final mesas = estadoMesas(const [], cola: [
        envio(mesa: 2, tipo: 'llevar'),
        envio(mesa: 6, accion: 'agregar', operacion: 'op-2'),
        envio(mesa: 20, operacion: 'op-3'),
      ]);
      expect(mesas.firstWhere((m) => m.numero == 2).situacion, SituacionMesa.libre);
      expect(mesas.firstWhere((m) => m.numero == 6).situacion, SituacionMesa.libre);
      expect(mesas.firstWhere((m) => m.numero == 20).situacion, SituacionMesa.sinEnviar);
    });

    test('si la mesa ya tiene cuentas, manda el estado de cocina', () {
      final mesas = estadoMesas([pedido(id: 1, mesa: 3, estado: 'preparando')], cola: [envio(mesa: 3)]);
      final mesa3 = mesas.firstWhere((m) => m.numero == 3);
      expect(mesa3.situacion, SituacionMesa.enCocina);
      expect(mesa3.sinEnviar, hasLength(1));
    });
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
