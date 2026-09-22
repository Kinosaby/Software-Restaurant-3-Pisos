import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/local/menu_file.dart';

void main() {
  test('Reads UTF-8 CSV, quoted commas and decimal comma with semicolons', () {
    final csv = MenuFile.parse(
      utf8.encode(
        '\uFEFFnombre,precio,categoria,activo\r\n"Taco, especial",12.50,Platillos,true\r\nAgua,20,Bebidas,false\r\n',
      ),
    );
    expect(csv.first['nombre'], 'Taco, especial');
    expect(csv.first['precio'], '12.50');
    expect(csv.last['activo'], false);
    final regional = MenuFile.parse(
      utf8.encode('nombre;precio;categoria;activo\nPozole;75,50;;sí'),
    );
    expect(regional.single['precio'], '75.50');
    expect(regional.single['activo'], true);
  });

  test('Only menu fields enter from a JSON API response', () {
    final result = MenuFile.parse(
      utf8.encode(
        jsonEncode({
          'productos': [
            {
              'id': 987,
              'nombre': 'Pozole',
              'precio': '75.00',
              'categoria': 'Platillos',
              'created_at': '2020-01-01',
            },
          ],
          'usuarios': [
            {'username': 'old-user'},
          ],
          'pedidos': [
            {'id': 2},
          ],
        }),
      ),
    );
    expect(result.single.keys.toSet(), {
      'nombre',
      'precio',
      'categoria',
      'activo',
    });
    expect(result.single['activo'], true);
    expect(
      MenuFile.parse(utf8.encode('[{"nombre":"Agua","precio":20}]'))
          .single['categoria'],
      'General',
    );
  });

  test('Rejects ambiguous CSV, non-menu backup, oversized and wrong currency files', () {
    for (final value in [
      'nombre,precio\nTaco,12,50',
      'nombre,precio\n"Taco,12.50',
      'nombre,precio\n"Taco"oops,12.50',
      'nombre,precio,precio\nTaco,12,12',
      'nombre,precio,activo\nTaco,12,tal vez',
      '{"records":[],"sequences":[]}',
      '{"moneda":"USD","productos":[{"nombre":"Taco","precio":12}]}',
      '[]',
    ]) {
      expect(
        () => MenuFile.parse(utf8.encode(value)),
        throwsFormatException,
        reason: value,
      );
    }
    expect(
      () => MenuFile.parse(List.filled(MenuFile.maxBytes + 1, 32)),
      throwsFormatException,
    );
  });
}
