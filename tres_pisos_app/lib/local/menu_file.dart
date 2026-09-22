import 'dart:convert';

/// A menu file never restores users, orders, sales or foreign database IDs.
/// Business validation is repeated by PosEngine before the transaction commits.
class MenuFile {
  static const maxBytes = 2 * 1024 * 1024;
  static const maxProducts = 2000;

  static List<Map<String, dynamic>> parse(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('El menú debe pesar menos de 2 MB');
    }
    final text = utf8.decode(bytes).replaceFirst('\uFEFF', '').trim();
    dynamic rows;
    if (text.startsWith('{') || text.startsWith('[')) {
      final data = jsonDecode(text);
      if (data is Map) {
        if (data['moneda'] != null && data['moneda'] != 'MXN') {
          throw const FormatException('El menú debe tener precios en MXN');
        }
        rows = data['productos'];
      } else {
        rows = data;
      }
    } else {
      final header = text.split('\n').first;
      final separator = header.contains(';') ? ';' : ',';
      final table = _csv(text, separator);
      if (table.isEmpty) {
        throw const FormatException('El archivo está vacío');
      }
      final columns = table.first.map((s) => s.trim().toLowerCase()).toList();
      if (!columns.contains('nombre') ||
          !columns.contains('precio') ||
          columns.toSet().length != columns.length) {
        throw const FormatException(
          'CSV: incluye las columnas nombre y precio, sin repetir encabezados',
        );
      }
      rows = <Map<String, dynamic>>[];
      for (var i = 1; i < table.length; i++) {
        final row = table[i];
        if (row.length == 1 && row.first.trim().isEmpty) {
          continue;
        }
        if (row.length != columns.length) {
          throw FormatException(
            'Fila ${i + 1}: el número de columnas no coincide',
          );
        }
        final product = <String, dynamic>{
          for (var j = 0; j < columns.length; j++) columns[j]: row[j].trim(),
        };
        if (separator == ';') {
          product['precio'] = product['precio'].toString().replaceAll(',', '.');
        }
        final active = (product['activo'] ?? '').toString().toLowerCase();
        if (![
          '',
          'true',
          'false',
          '1',
          '0',
          'sí',
          'si',
          'no',
        ].contains(active)) {
          throw FormatException('Fila ${i + 1}: activo debe ser true o false');
        }
        product['activo'] = !['false', '0', 'no'].contains(active);
        rows.add(product);
      }
    }
    if (rows is! List || rows.isEmpty || rows.length > maxProducts) {
      throw const FormatException(
        'El archivo debe contener entre 1 y 2000 productos',
      );
    }
    return rows.map<Map<String, dynamic>>((row) {
      if (row is! Map) {
        throw const FormatException('Producto inválido');
      }
      return {
        'nombre': row['nombre'],
        'precio': row['precio'],
        'categoria': row['categoria'] ?? 'General',
        'activo': row['activo'] ?? true,
      };
    }).toList();
  }

  static List<List<String>> _csv(String text, String separator) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false, closedQuote = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
            closedQuote = true;
          }
        } else {
          field.write(char);
        }
      } else if (char == separator || char == '\n' || char == '\r') {
        row.add(field.toString());
        field = StringBuffer();
        closedQuote = false;
        if (char != separator) {
          rows.add(row);
          row = [];
          if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
            i++;
          }
        }
      } else if (char == '"' && field.isEmpty && !closedQuote) {
        quoted = true;
      } else {
        if (closedQuote || char == '"') {
          throw const FormatException('CSV: comillas mal cerradas');
        }
        field.write(char);
      }
    }
    if (quoted) {
      throw const FormatException('CSV: faltan comillas de cierre');
    }
    row.add(field.toString());
    rows.add(row);
    return rows;
  }
}
