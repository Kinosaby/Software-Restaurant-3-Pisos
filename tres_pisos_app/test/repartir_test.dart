import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/central/central.dart';
import 'package:tres_pisos_app/central/servidor_central.dart';
import 'package:tres_pisos_app/features/pedidos/modelos.dart';
import 'package:tres_pisos_app/features/pedidos/pedidos_controller.dart';

const menu = [
  {'nombre': 'Pizza', 'precio': '100.00', 'categoria': 'Platillos', 'activo': true},
  {'nombre': 'Refresco', 'precio': '22.00', 'categoria': 'Bebidas', 'activo': true},
  {'nombre': 'Postre', 'precio': '0.02', 'categoria': 'Postres', 'activo': true},
];

double suma(Iterable<double> montos) => montos.fold(0, (s, m) => s + m);

void main() {
  group('repartirCentavos', () {
    test('reparte en centavos exactos y la suma cuadra', () {
      expect(repartirCentavos(100, 3), [33.34, 33.33, 33.33]);
      expect(repartirCentavos(100, 2), [50.0, 50.0]);
      expect(repartirCentavos(0.05, 3), [0.02, 0.02, 0.01]);
      for (final (monto, partes) in [(99.99, 7), (45.5, 3), (1234.56, 11), (0.1, 4), (89.9, 6)]) {
        final montos = repartirCentavos(monto, partes);
        expect(montos, hasLength(partes));
        expect((suma(montos) * 100).round(), (monto * 100).round(), reason: '$monto / $partes');
        expect(montos.first - montos.last, lessThanOrEqualTo(0.011), reason: 'partes iguales ±1 centavo');
      }
    });
  });

  group('modelos del cliente', () {
    test('PedidoItem lee la parte compartida y los datos viejos siguen sin ella', () {
      final viejo = PedidoItem.fromJson({'id': 1, 'producto_id': 1, 'nombre': 'Pizza', 'cantidad': 1, 'precio': 100});
      expect(viejo.compartido, isNull);
      expect(viejo.paraCocina, isTrue);
      expect(viejo.toJson().containsKey('compartido'), isFalse);

      final parte = PedidoItem.fromJson({
        'id': 2,
        'producto_id': 1,
        'nombre': 'Pizza',
        'cantidad': 1,
        'precio': '33.33',
        'compartido': {'grupo': 1, 'parte': 2, 'partes': 3},
      });
      expect(parte.compartido, (grupo: 1, parte: 2, partes: 3));
      expect(parte.paraCocina, isFalse);
      expect(parte.etiquetaCompartido, 'Compartido 2/3');
      expect(PedidoItem.fromJson(parte.toJson()).compartido, parte.compartido);
    });

    Pedido pedido(int id, {int mesa = 3, String estado = 'listo'}) => Pedido.fromJson({
          'id': id,
          'mesa': mesa,
          'estado': estado,
          'tipo': 'aqui',
          'total': 10,
          'creado_en': '2026-09-26T18:00:00.000Z',
          'productos': [
            {'id': id * 10, 'producto_id': 1, 'nombre': 'Pizza', 'cantidad': 1, 'precio': 10},
          ],
        });

    test('cuentasHermanas: solo otras cuentas abiertas de la misma mesa', () {
      final activos = [pedido(1), pedido(2), pedido(3, mesa: 5), pedido(4, estado: 'pagado')];
      expect(cuentasHermanas(activos, activos.first).map((p) => p.id), [2]);
    });

    test('aplicarReparto quita la cuenta vacía y reemplaza las que cambiaron', () {
      final activos = [pedido(1), pedido(2), pedido(3)];
      final cambiado = pedido(2, estado: 'preparando');
      final lista = aplicarReparto(activos, (pedidos: [cambiado], eliminado: 1));
      expect(lista.map((p) => p.id), [2, 3]);
      expect(lista.first.estado, EstadoPedido.preparando);
    });
  });

  group('central', () {
    late Directory carpeta;
    late Central central;
    late UsuarioCentral mesero;
    late UsuarioCentral cocina;
    final eventos = <(String, Map<String, dynamic>)>[];

    Future<Central> abrir() async {
      final c = await Central.abrir(carpeta, iteraciones: 1000);
      c.emitir = (evento, datos) => eventos.add((evento, datos));
      return c;
    }

    Future<UsuarioCentral> usuario(String nombre, String rol) async {
      await central.crearUsuario({'username': nombre, 'password': 'clave123', 'role': rol});
      return central.autenticar((await central.login(nombre, 'clave123'))['token'] as String)!;
    }

    Future<Map<String, dynamic>> cuenta(String comensal, List<(int, int)> productos, {int mesa = 3}) =>
        central.crearPedido({
          'mesa': mesa,
          'tipo': 'aqui',
          'comensal': comensal,
          'productos': [
            for (final (id, cantidad) in productos) {'producto_id': id, 'cantidad': cantidad},
          ],
        }, usuario: mesero);

    List<Map<String, dynamic>> items(int pedidoId) =>
        (central.obtenerPedido(pedidoId)['productos'] as List).cast<Map<String, dynamic>>();
    double total(int pedidoId) => central.obtenerPedido(pedidoId)['total'] as double;

    setUp(() async {
      carpeta = await Directory.systemTemp.createTemp('repartir_test');
      eventos.clear();
      central = await abrir();
      await central.inicializar(admin: 'admin', password: 'secreto1', menu: menu);
      mesero = await usuario('luis', 'mesero');
      cocina = await usuario('chef', 'cocina');
    });

    tearDown(() async {
      await central.cerrar();
      await carpeta.delete(recursive: true);
    });

    test('mover parte de las piezas de un renglón a otra cuenta', () async {
      final ana = await cuenta('Ana', [(1, 1), (2, 3)]);
      final beto = await cuenta('Beto', [(2, 1)]);
      final refrescos = items(ana['id'] as int).last;
      eventos.clear();

      final r = await central.moverProducto(ana['id'] as int, {
        'detalle_id': refrescos['id'],
        'cantidad': 2,
        'destino': beto['id'],
      });
      expect(r['eliminado'], isNull);
      expect((r['pedidos'] as List), hasLength(2));
      expect(items(ana['id'] as int).map((i) => i['cantidad']), [1, 1]);
      // Mismo producto y precio: se suma al renglón que ya tenía Beto.
      expect(items(beto['id'] as int).map((i) => (i['nombre'], i['cantidad'])), [('Refresco', 3)]);
      expect(total(ana['id'] as int) + total(beto['id'] as int), 100 + 22.0 * 4);
      expect(eventos.map((e) => e.$1), ['pedido_actualizado', 'pedido_actualizado']);
    });

    test('mover el último producto borra la cuenta vacía', () async {
      final ana = await cuenta('Ana', [(1, 1)]);
      final beto = await cuenta('Beto', [(2, 1)]);
      final r = await central.moverProducto(ana['id'] as int, {
        'detalle_id': items(ana['id'] as int).single['id'],
        'destino': beto['id'],
      });
      expect(r['eliminado'], ana['id']);
      expect(central.listarPedidos().map((p) => p['id']), [beto['id']]);
      expect(eventos.map((e) => e.$1), contains('pedido_eliminado'));
      expect(total(beto['id'] as int), 122.0);
    });

    test('mover algo que cocina no ha hecho a una cuenta ya lista avisa a cocina como extra', () async {
      final ana = await cuenta('Ana', [(1, 1), (2, 1)]);
      final beto = await cuenta('Beto', [(2, 1)]);
      await central.cambiarEstado(beto['id'] as int, 'listo', usuario: cocina);
      eventos.clear();
      await central.moverProducto(ana['id'] as int, {
        'detalle_id': items(ana['id'] as int).first['id'],
        'destino': beto['id'],
      });
      expect(eventos.first.$1, 'extra_pedido');
      expect((eventos.first.$2['items'] as List).single['nombre'], 'Pizza');
      // Queda marcado como extra (`extra_desde`) para que cocina lo vea en su tarjeta de extras.
      final deBeto = Pedido.fromJson(central.obtenerPedido(beto['id'] as int));
      expect(deBeto.extrasPendientes.single.nombre, 'Pizza');
      expect(deBeto.conExtrasPendientes, isTrue);

      // Si vuelve a una cuenta que sigue en cocina, se prepara con ella: ya no es extra.
      final caro = await cuenta('Caro', [(2, 1)]);
      await central.moverProducto(beto['id'] as int, {
        'detalle_id': deBeto.extrasPendientes.single.detalleId,
        'destino': caro['id'],
      });
      expect(items(caro['id'] as int).last['extra_desde'], isNull);

      // Dividir un extra pendiente conserva la marca solo en la parte que ve cocina.
      await central.cambiarEstado(ana['id'] as int, 'listo', usuario: cocina);
      await central.agregarProductos(ana['id'] as int, {
        'productos': [
          {'producto_id': 1, 'cantidad': 1},
        ],
      }, usuario: mesero);
      final extra = items(ana['id'] as int).last;
      expect(extra['extra_desde'], isNotNull);
      await central.dividirProducto(ana['id'] as int, {'detalle_id': extra['id'], 'destinos': [caro['id']]});
      expect(items(ana['id'] as int).last['extra_desde'], isNotNull);
      expect(items(caro['id'] as int).last['extra_desde'], isNull);
    });

    test('dividir un platillo: partes iguales, suma exacta y cocina lo ve una vez', () async {
      final ana = await cuenta('Ana', [(1, 2)]);
      final beto = await cuenta('Beto', [(2, 1)]);
      final caro = await cuenta('Caro', [(2, 1)]);
      final pizzas = items(ana['id'] as int).single;
      eventos.clear();

      final r = await central.dividirProducto(ana['id'] as int, {
        'detalle_id': pizzas['id'],
        'destinos': [beto['id'], caro['id']],
      });
      expect((r['pedidos'] as List), hasLength(3));
      expect(eventos.where((e) => e.$1 == 'pedido_actualizado'), hasLength(3));

      // Ana conserva la otra pizza completa y la parte 1 (con el centavo sobrante).
      final deAna = items(ana['id'] as int);
      expect(deAna.map((i) => (i['cantidad'], i['precio'])), [(1, 100.0), (1, 33.34)]);
      expect(deAna.last['compartido'], {'grupo': deAna.last['id'], 'parte': 1, 'partes': 3});
      expect(items(beto['id'] as int).last['precio'], 33.33);
      expect(items(caro['id'] as int).last['compartido']['parte'], 3);

      final totales = [ana, beto, caro].map((p) => total(p['id'] as int));
      expect((suma(totales) * 100).round(), (200 + 22 * 2) * 100);

      // Cocina (lado cliente): una sola pizza compartida visible en toda la mesa.
      final pedidos = [for (final p in central.listarPedidos()) Pedido.fromJson(p)];
      final visibles = pedidos.expand((p) => p.items).where((i) => i.paraCocina && i.compartido != null);
      expect(visibles, hasLength(1));

      // En "más pedidos" siguen siendo 2 pizzas, no 4.
      final top = central.resumen()['productosTop'] as List;
      expect(top.firstWhere((e) => e['nombre'] == deAna.first['nombre'])['total_pedido'], 2);

      // Una parte no se vuelve a dividir, ni cambia de cantidad.
      await expectLater(
        central.dividirProducto(beto['id'] as int, {
          'detalle_id': items(beto['id'] as int).last['id'],
          'destinos': [caro['id']],
        }),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'ALREADY_SHARED')),
      );
      await expectLater(
        central.editarPedido(beto['id'] as int, {
          'items': [
            {'detalle_id': items(beto['id'] as int).last['id'], 'cantidad': 2},
          ],
        }),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'SHARED_ITEM')),
      );

      // Agregar otra pizza no se suma a la parte compartida.
      await central.agregarProductos(ana['id'] as int, {
        'productos': [
          {'producto_id': 1, 'cantidad': 1},
        ],
      }, usuario: mesero);
      expect(items(ana['id'] as int).map((i) => (i['cantidad'], i['precio'])), [(2, 100.0), (1, 33.34)]);
    });

    test('las partes sobreviven a un reinicio de la tablet', () async {
      final ana = await cuenta('Ana', [(1, 1)]);
      final beto = await cuenta('Beto', [(2, 1)]);
      await central.dividirProducto(ana['id'] as int, {
        'detalle_id': items(ana['id'] as int).single['id'],
        'destinos': [beto['id']],
      });
      final antes = jsonEncode(central.listarPedidos());
      await central.cerrar();
      central = await abrir();
      expect(jsonEncode(central.listarPedidos()), antes);
      // Los ids nuevos no chocan con los de las partes.
      final otro = await cuenta('Caro', [(2, 1)]);
      final ids = central.listarPedidos().expand((p) => p['productos'] as List).map((i) => i['id']).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(otro['id'], greaterThan(beto['id'] as int));
    });

    test('no mueve ni divide con cuentas cobradas, canceladas o de otra mesa', () async {
      final ana = await cuenta('Ana', [(1, 1)]);
      final beto = await cuenta('Beto', [(2, 1)]);
      final otraMesa = await cuenta('Dani', [(2, 1)], mesa: 8);
      final pizza = items(ana['id'] as int).single['id'];

      await expectLater(
        central.moverProducto(ana['id'] as int, {'detalle_id': pizza, 'destino': otraMesa['id']}),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'DIFFERENT_TABLE')),
      );
      await expectLater(
        central.moverProducto(ana['id'] as int, {'detalle_id': pizza, 'destino': ana['id']}),
        throwsA(isA<ErrorCentral>()),
      );
      await expectLater(
        central.moverProducto(ana['id'] as int, {'detalle_id': pizza, 'cantidad': 2, 'destino': beto['id']}),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'VALIDATION_ERROR')),
      );

      await central.cambiarEstado(beto['id'] as int, 'pagado', usuario: mesero);
      await expectLater(
        central.moverProducto(ana['id'] as int, {'detalle_id': pizza, 'destino': beto['id']}),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'ACCOUNT_PAID')),
      );
      await expectLater(
        central.dividirProducto(ana['id'] as int, {'detalle_id': pizza, 'destinos': [beto['id']]}),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'ACCOUNT_PAID')),
      );
      await expectLater(
        central.moverProducto(beto['id'] as int, {
          'detalle_id': items(beto['id'] as int).single['id'],
          'destino': ana['id'],
        }),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'ACCOUNT_PAID')),
      );
      // La cuenta cobrada y la venta no cambiaron.
      expect(total(beto['id'] as int), 22.0);
      expect(total(ana['id'] as int), 100.0);

      final caro = await cuenta('Caro', [(2, 1)]);
      await central.cambiarEstado(caro['id'] as int, 'cancelado', usuario: mesero);
      await expectLater(
        central.dividirProducto(ana['id'] as int, {'detalle_id': pizza, 'destinos': [caro['id']]}),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'INVALID_STATUS')),
      );
    });

    test('si se cancela la cuenta con la parte 1, cocina sigue viendo el platillo', () async {
      final ana = await cuenta('Ana', [(1, 1)]);
      final beto = await cuenta('Beto', [(2, 1)]);
      final caro = await cuenta('Caro', [(2, 1)]);
      await central.dividirProducto(ana['id'] as int, {
        'detalle_id': items(ana['id'] as int).single['id'],
        'destinos': [beto['id'], caro['id']],
      });
      Iterable<PedidoItem> paraCocina() => [
            for (final p in central.listarPedidos())
              if (p['estado'] != 'cancelado') ...Pedido.fromJson(p).items,
          ].where((i) => i.compartido != null && i.paraCocina);

      await central.cambiarEstado(ana['id'] as int, 'cancelado', usuario: mesero);
      expect(paraCocina(), hasLength(1), reason: 'la parte de Beto pasa a ser la que ve cocina');
      expect(items(beto['id'] as int).last['compartido']['parte'], 1);
      expect(items(caro['id'] as int).last['compartido']['parte'], 3);

      // Igual al borrar la cuenta o quitar la parte al editarla.
      await central.eliminarPedido(beto['id'] as int);
      expect(paraCocina(), hasLength(1));
      expect(items(caro['id'] as int).last['compartido']['parte'], 1);
    });

    test('si la parte relevada está en una cuenta lista, cocina la recibe como extra', () async {
      final ana = await cuenta('Ana', [(1, 1), (2, 1)]);
      final beto = await cuenta('Beto', [(2, 1)]);
      await central.dividirProducto(ana['id'] as int, {
        'detalle_id': items(ana['id'] as int).first['id'],
        'destinos': [beto['id']],
      });
      await central.cambiarEstado(beto['id'] as int, 'listo', usuario: cocina);

      // Ana (aún pendiente) quita su parte: la pizza no se ha hecho.
      await central.editarPedido(ana['id'] as int, {
        'items': [
          {'detalle_id': items(ana['id'] as int).firstWhere((i) => i['compartido'] != null)['id'], 'cantidad': 0},
        ],
      });
      final relevo = items(beto['id'] as int).last;
      expect(relevo['compartido']['parte'], 1);
      expect(relevo['extra_desde'], isNotNull);
    });

    test('lo ya servido que pasa a una cuenta en cocina no se vuelve a preparar', () async {
      final ana = await cuenta('Ana', [(1, 1)]);
      final beto = await cuenta('Beto', [(2, 1)]);
      await central.cambiarEstado(ana['id'] as int, 'listo', usuario: cocina);

      await central.moverProducto(ana['id'] as int, {
        'detalle_id': items(ana['id'] as int).single['id'],
        'destino': beto['id'],
      });
      final pizza = items(beto['id'] as int).firstWhere((i) => i['producto_id'] == 1);
      expect(pizza['servido'], isTrue);
      expect(PedidoItem.fromJson(pizza).paraCocina, isFalse, reason: 'cocina no la vuelve a ver');
      expect(total(beto['id'] as int), 122.0, reason: 'se sigue cobrando');
    });

    test('si se cancela una cuenta lista con la parte 1, el relevo queda como servido', () async {
      final ana = await cuenta('Ana', [(1, 1)]);
      final beto = await cuenta('Beto', [(2, 1)]);
      await central.dividirProducto(ana['id'] as int, {
        'detalle_id': items(ana['id'] as int).single['id'],
        'destinos': [beto['id']],
      });
      await central.cambiarEstado(ana['id'] as int, 'listo', usuario: cocina);
      await central.cambiarEstado(ana['id'] as int, 'cancelado', usuario: mesero);
      final relevo = items(beto['id'] as int).last;
      expect(relevo['compartido']['parte'], 1);
      expect(relevo['servido'], isTrue);
      expect(relevo['extra_desde'], isNull);
    });

    test('mover, dividir y cobrar con el mismo id de operación no se repiten', () async {
      final ana = await cuenta('Ana', [(2, 3)]);
      final beto = await cuenta('Beto', [(1, 1)]);
      final refrescos = items(ana['id'] as int).single['id'];
      final datos = {'detalle_id': refrescos, 'cantidad': 1, 'destino': beto['id']};

      await central.moverProducto(ana['id'] as int, datos, operacion: 'op-mover');
      final repetido = await central.moverProducto(ana['id'] as int, datos, operacion: 'op-mover');
      expect(items(ana['id'] as int).single['cantidad'], 2, reason: 'solo se movió una pieza');
      expect((repetido['pedidos'] as List), hasLength(2));

      final pago = {'pedidos': [beto['id']], 'efectivo': total(beto['id'] as int), 'tarjeta': 0};
      await central.cobrar(pago, operacion: 'op-cobro');
      final otraVez = await central.cobrar(pago, operacion: 'op-cobro');
      expect(otraVez.single['id'], beto['id']);
      expect((central.resumen()['dia'] as Map)['total_ventas'], 122.0, reason: 'una sola venta');
    });

    test('la lista de pedidos se puede pedir desde una fecha', () async {
      await cuenta('Ana', [(1, 1)]);
      expect(central.listarPedidos(desde: DateTime.now().subtract(const Duration(hours: 1))), hasLength(1));
      expect(central.listarPedidos(desde: DateTime.now().add(const Duration(hours: 1))), isEmpty);
    });

    test('no divide un precio que no alcanza un centavo por parte', () async {
      final ana = await cuenta('Ana', [(3, 1)]);
      final beto = await cuenta('Beto', [(2, 1)]);
      final caro = await cuenta('Caro', [(2, 1)]);
      await expectLater(
        central.dividirProducto(ana['id'] as int, {
          'detalle_id': items(ana['id'] as int).single['id'],
          'destinos': [beto['id'], caro['id']],
        }),
        throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'VALIDATION_ERROR')),
      );
    });

    test('endpoints HTTP /mover y /dividir difunden el cambio por WebSocket', () async {
      final servidor = ServidorCentral(central, puerto: 0, anunciar: false);
      await servidor.iniciar();
      final http = HttpClient();
      addTearDown(() async {
        http.close(force: true);
        await servidor.detener();
      });
      final token = (await central.login('luis', 'clave123'))['token'] as String;

      Future<(int, Map<String, dynamic>)> patch(String ruta, Object cuerpo, {String? conToken}) async {
        final req = await http.openUrl('PATCH', Uri.parse('http://127.0.0.1:${servidor.puertoEnUso}$ruta'));
        req.headers.set('X-Enlace', central.codigoEnlace);
        req.headers.set('Authorization', 'Bearer ${conToken ?? token}');
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(cuerpo));
        final res = await req.close();
        return (res.statusCode, jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>);
      }

      final ana = await cuenta('Ana', [(1, 1), (2, 1)]);
      final beto = await cuenta('Beto', [(2, 1)]);

      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${servidor.puertoEnUso}/ws?token=$token&enlace=${central.codigoEnlace}',
      );
      final recibidos = ws.map((m) => jsonDecode(m as String) as Map<String, dynamic>).take(2).toList();

      final (status, cuerpo) = await patch('/api/pedidos/${ana['id']}/dividir', {
        'detalle_id': items(ana['id'] as int).first['id'],
        'destinos': [beto['id']],
      });
      expect(status, 200);
      final pedidos = [for (final p in cuerpo['pedidos'] as List) Pedido.fromJson(p as Map<String, dynamic>)];
      expect(pedidos.map((p) => p.total), [72.0, 72.0]);

      final eventosWs = await recibidos.timeout(const Duration(seconds: 5));
      expect(eventosWs.map((e) => e['evento']), ['pedido_actualizado', 'pedido_actualizado']);
      expect(eventosWs.map((e) => (e['datos'] as Map)['_accion']), everyElement('producto_dividido'));
      await ws.close();

      // El refresco de Ana se suma al de Beto.
      final (statusMover, mover) = await patch('/api/pedidos/${ana['id']}/mover', {
        'detalle_id': items(ana['id'] as int).last['id'],
        'destino': beto['id'],
        'cantidad': 1,
      });
      expect(statusMover, 200);
      expect(mover['eliminado'], isNull);
      expect(total(beto['id'] as int), 22 + 50 + 22.0);

      // Cocina no reparte cuentas.
      final tokenCocina = (await central.login('chef', 'clave123'))['token'] as String;
      final (statusCocina, _) = await patch('/api/pedidos/${ana['id']}/mover', {
        'detalle_id': items(ana['id'] as int).first['id'],
        'destino': beto['id'],
      }, conToken: tokenCocina);
      expect(statusCocina, 403);
    });
  });
}
