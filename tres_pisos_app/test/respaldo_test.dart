import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/central/central.dart';
import 'package:tres_pisos_app/central/respaldo.dart';
import 'package:tres_pisos_app/features/conexion/respaldos_page.dart';

void main() {
  final carpetas = <Directory>[];
  final centrales = <Central>[];

  Future<Central> nuevaCentral() async {
    final carpeta = await Directory.systemTemp.createTemp('respaldo');
    carpetas.add(carpeta);
    final central = await Central.abrir(carpeta, iteraciones: 1000);
    centrales.add(central);
    return central;
  }

  tearDown(() async {
    for (final c in centrales) {
      await c.cerrar();
    }
    for (final d in carpetas) {
      await d.delete(recursive: true);
    }
    centrales.clear();
    carpetas.clear();
  });

  Future<Central> centralConDatos() async {
    final central = await nuevaCentral();
    await central.inicializar(admin: 'admin', password: 'secreto1', nombreRestaurante: 'Tres Pisos', menu: [
      {'nombre': 'Tacos', 'precio': 42, 'categoria': 'Tacos'},
    ]);
    await central.crearUsuario({'username': 'luis', 'password': 'clave123', 'role': 'mesero'});
    final mesero = central.autenticar((await central.login('luis', 'clave123'))['token'] as String)!;
    final id = (await central.crearPedido({
      'mesa': 4,
      'productos': [
        {'producto_id': 1, 'cantidad': 2},
      ],
    }, usuario: mesero, operacion: 'op-1'))['id'] as int;
    await central.cambiarEstado(id, 'pagado', usuario: mesero);
    return central;
  }

  test('un respaldo restaurado en otra tablet conserva todo y cierra las sesiones', () async {
    final original = await centralConDatos();
    final tokenViejo = (await original.login('luis', 'clave123'))['token'] as String;
    final archivo = cifrarRespaldo(await original.exportar(), 'mi-clave-segura', restaurante: original.nombre, iteraciones: 1000);

    final info = leerInfoRespaldo(archivo);
    expect(info.restaurante, 'Tres Pisos');

    final nueva = await nuevaCentral();
    await nueva.restaurar(descifrarRespaldo(archivo, 'mi-clave-segura'));

    expect(nueva.listarPedidos(), original.listarPedidos());
    expect(nueva.listarProductos(), original.listarProductos());
    expect(nueva.resumen(), original.resumen());
    expect(nueva.codigoEnlace, original.codigoEnlace, reason: 'los meseros no tienen que volver a teclear el código');
    expect(nueva.autenticar(tokenViejo), isNull, reason: 'secreto nuevo: hay que volver a iniciar sesión');
    expect(nueva.autenticar((await nueva.login('luis', 'clave123'))['token'] as String), isNotNull);

    // Las operaciones también viajan: un reintento pendiente no duplica tras restaurar.
    final mesero = nueva.autenticar((await nueva.login('luis', 'clave123'))['token'] as String)!;
    await nueva.crearPedido({
      'mesa': 4,
      'productos': [
        {'producto_id': 1, 'cantidad': 2},
      ],
    }, usuario: mesero, operacion: 'op-1');
    expect(nueva.listarPedidos(), hasLength(1));

    // Y sobrevive al reinicio de la tablet nueva.
    await nueva.cerrar();
    centrales.remove(nueva);
    final reabierta = await Central.abrir(carpetas.last, iteraciones: 1000);
    centrales.add(reabierta);
    expect(reabierta.listarPedidos(), hasLength(1));
  });

  test('contraseña incorrecta, archivo manipulado o ajeno', () async {
    final original = await centralConDatos();
    final archivo = cifrarRespaldo(await original.exportar(), 'mi-clave-segura', restaurante: 'Tres Pisos', iteraciones: 1000);

    expect(
      () => descifrarRespaldo(archivo, 'otra-clave'),
      throwsA(isA<RespaldoInvalido>().having((e) => e.mensaje, 'mensaje', contains('Contraseña incorrecta'))),
    );

    // Cambiar el nombre del restaurante en la cabecera invalida el archivo.
    final sobre = jsonDecode(utf8.decode(archivo)) as Map<String, dynamic>;
    final manipulado = Uint8List.fromList(utf8.encode(jsonEncode({...sobre, 'restaurante': 'Otro'})));
    expect(() => descifrarRespaldo(manipulado, 'mi-clave-segura'), throwsA(isA<RespaldoInvalido>()));

    expect(() => leerInfoRespaldo(Uint8List.fromList(utf8.encode('hola'))), throwsA(isA<RespaldoInvalido>()));
  });

  test('nunca sobrescribe una central que ya tiene datos', () async {
    final original = await centralConDatos();
    final registros = await original.exportar();
    final otra = await centralConDatos();
    await expectLater(
      otra.restaurar(registros),
      throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'CENTRAL_CON_DATOS')),
    );
  });

  test('rechaza respaldos sin administrador o con datos corruptos', () async {
    final vacia = await nuevaCentral();
    await expectLater(
      vacia.restaurar([
        {'t': 'config', 'v': {'enlace': 'AAAA-BBBB', 'secreto': 'x'}},
      ]),
      throwsA(isA<ErrorCentral>().having((e) => e.codigo, 'codigo', 'RESPALDO_INVALIDO')),
    );
    await expectLater(
      vacia.restaurar([
        {'t': 'pedido', 'v': {'id': 'no-es-numero'}},
      ]),
      throwsA(isA<ErrorCentral>()),
    );
    expect(vacia.inicializada, isFalse);
  });

  test('aviso de respaldo atrasado', () {
    final ahora = DateTime(2026, 9, 23, 20);
    expect(descripcionUltimoRespaldo(null), contains('Nunca'));
    expect(respaldoAtrasado(null, ahora: ahora), isTrue);
    expect(descripcionUltimoRespaldo(DateTime(2026, 9, 22, 19), ahora: ahora), 'Último respaldo: ayer');
    expect(respaldoAtrasado(DateTime(2026, 9, 20), ahora: ahora), isFalse);
    expect(respaldoAtrasado(DateTime(2026, 9, 10), ahora: ahora), isTrue);
  });
}
