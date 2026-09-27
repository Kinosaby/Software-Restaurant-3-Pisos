import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/central/central.dart';
import 'package:tres_pisos_app/central/diario.dart';

void main() {
  late Directory carpeta;
  late File archivo;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('diario_test');
    archivo = File('${carpeta.path}${Platform.pathSeparator}central.jsonl');
  });

  tearDown(() async {
    await carpeta.delete(recursive: true);
  });

  List<Map<String, dynamic>> lote(String nombre) => [
        {'t': 'config', 'v': {'nombre': nombre}},
      ];

  List<String> nombres(List<List<Map<String, dynamic>>> lotes) =>
      [for (final l in lotes) (l.single['v'] as Map<String, dynamic>)['nombre'] as String];

  group('corte de luz a mitad de una escritura', () {
    test('descarta la línea cortada (con una ñ partida) y la siguiente escritura sobrevive al reinicio', () async {
      final diario = Diario(carpeta);
      await diario.cargar();
      await diario.escribir(lote('Uno'));
      await diario.escribir(lote('Año'));
      await diario.cerrar();

      // La escritura cortada termina justo en medio de los dos bytes de la ñ.
      final cortada = utf8.encode(jsonEncode(lote('Peña')));
      final hastaLaEnie = cortada.indexOf(0xC3);
      await archivo.writeAsBytes(cortada.sublist(0, hastaLaEnie + 1), mode: FileMode.append, flush: true);

      final reabierto = Diario(carpeta);
      expect(nombres(await reabierto.cargar()), ['Uno', 'Año']);
      expect(reabierto.lineas, 2);
      // El resto cortado se recorta del archivo.
      final bytes = await archivo.readAsBytes();
      expect(bytes.last, 10);
      await reabierto.escribir(lote('Después'));
      await reabierto.cerrar();

      final otraVez = Diario(carpeta);
      expect(nombres(await otraVez.cargar()), ['Uno', 'Año', 'Después']);
      await otraVez.cerrar();
    });

    test('una línea ilegible en medio del archivo no tumba la carga', () async {
      await archivo.writeAsBytes([
        ...utf8.encode('${jsonEncode(lote('Uno'))}\n'),
        // Basura de un corte antiguo pegada a otra línea, con UTF-8 inválido.
        ...utf8.encode('[{"t":"config","v":{"nombre":"Pe'), 0xC3,
        ...utf8.encode('${jsonEncode(lote('Pegada'))}\n'),
        ...utf8.encode('${jsonEncode(lote('Dos'))}\n'),
      ]);
      final diario = Diario(carpeta);
      expect(nombres(await diario.cargar()), ['Uno', 'Dos']);
      await diario.cerrar();
    });

    test('la central abre con la última línea cortada y conserva lo anterior', () async {
      final central = await Central.abrir(carpeta, iteraciones: 1000);
      await central.inicializar(admin: 'admin', password: 'secreto1');
      await central.crearUsuario({'username': 'mesero', 'password': 'clave123', 'role': 'mesero'});
      await central.cerrar();

      await archivo.writeAsBytes([...utf8.encode('[{"t":"usuario","v":{"username":"Nuñ'), 0xC3],
          mode: FileMode.append, flush: true);

      final reabierta = await Central.abrir(carpeta, iteraciones: 1000);
      await reabierta.crearUsuario({'username': 'cocinero', 'password': 'clave123', 'role': 'cocina'});
      await reabierta.cerrar();

      final otraVez = await Central.abrir(carpeta, iteraciones: 1000);
      expect(otraVez.listarUsuarios().map((u) => u['username']), containsAll(['admin', 'mesero', 'cocinero']));
      await otraVez.cerrar();
    });
  });

  group('compactación', () {
    test('si falla, el diario sigue abierto y se puede seguir escribiendo', () async {
      final diario = Diario(carpeta);
      await diario.cargar();
      await diario.escribir(lote('Uno'));

      // Un directorio con el nombre del temporal hace fallar la compactación.
      final estorbo = await Directory('${archivo.path}.tmp').create();
      await expectLater(diario.compactar(lote('Todo')), throwsA(isA<FileSystemException>()));
      await diario.escribir(lote('Dos'));
      await diario.cerrar();
      await estorbo.delete();

      final reabierto = Diario(carpeta);
      expect(nombres(await reabierto.cargar()), ['Uno', 'Dos']);
      await reabierto.compactar(lote('Todo'));
      await reabierto.escribir(lote('Tres'));
      await reabierto.cerrar();

      final compactado = Diario(carpeta);
      expect(nombres(await compactado.cargar()), ['Todo', 'Tres']);
      await compactado.cerrar();
    });

    test('un fallo al compactar no hace fallar la operación y la central sigue escribiendo', () async {
      final central = await Central.abrir(carpeta, iteraciones: 1000, lineasParaCompactar: 3);
      await central.inicializar(admin: 'admin', password: 'secreto1');
      final estorbo = await Directory('${archivo.path}.tmp').create();

      for (var i = 0; i < 5; i++) {
        await central.crearUsuario({'username': 'mesero$i', 'password': 'clave123', 'role': 'mesero'});
      }
      await estorbo.delete();
      // Ahora sí puede compactar.
      await central.crearUsuario({'username': 'cocinero', 'password': 'clave123', 'role': 'cocina'});
      await central.cerrar();
      expect((await archivo.readAsLines()).length, 1);

      final reabierta = await Central.abrir(carpeta, iteraciones: 1000);
      expect(
        reabierta.listarUsuarios().map((u) => u['username']),
        containsAll(['admin', for (var i = 0; i < 5; i++) 'mesero$i', 'cocinero']),
      );
      await reabierta.cerrar();
    });
  });
}
