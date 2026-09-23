import 'dart:convert';
import 'dart:io';

/// Almacenamiento de la central: un archivo de líneas JSON al que solo se añade.
///
/// Cada operación de negocio escribe **una** línea (un lote de registros) y la
/// fuerza a disco antes de responder, así que una operación queda completa o no
/// queda. Si la tablet se apaga a mitad de una escritura, la última línea queda
/// cortada y se ignora al cargar.
///
/// Cada cierto número de líneas se compacta: se escribe el estado vigente en un
/// archivo temporal y se renombra encima del diario (reemplazo atómico).
class Diario {
  Diario(Directory carpeta)
      : _archivo = File('${carpeta.path}${Platform.pathSeparator}central.jsonl'),
        _temporal = File('${carpeta.path}${Platform.pathSeparator}central.jsonl.tmp');

  final File _archivo;
  final File _temporal;
  RandomAccessFile? _escritura;
  int _lineas = 0;

  int get lineas => _lineas;

  /// Lee todos los lotes válidos, en orden.
  Future<List<List<Map<String, dynamic>>>> cargar() async {
    // Una compactación interrumpida deja el temporal: el diario original sigue intacto.
    if (await _temporal.exists()) await _temporal.delete();
    if (!await _archivo.exists()) await _archivo.create(recursive: true);

    final lotes = <List<Map<String, dynamic>>>[];
    final lineas = await _archivo.openRead().transform(utf8.decoder).transform(const LineSplitter()).toList();
    for (final linea in lineas) {
      if (linea.trim().isEmpty) continue;
      try {
        final registros = (jsonDecode(linea) as List).cast<Map<String, dynamic>>();
        lotes.add(registros);
      } on Object {
        // Línea incompleta por un corte de energía: se descarta.
      }
    }
    _lineas = lotes.length;
    _escritura = await _archivo.open(mode: FileMode.append);
    return lotes;
  }

  Future<void> escribir(List<Map<String, dynamic>> lote) async {
    final escritura = _escritura;
    if (escritura == null) throw StateError('Diario sin cargar');
    await escritura.writeString('${jsonEncode(lote)}\n');
    await escritura.flush();
    _lineas++;
  }

  /// Reemplaza el diario por una sola línea con el estado completo.
  Future<void> compactar(List<Map<String, dynamic>> estado) async {
    await _escritura?.close();
    _escritura = null;
    await _temporal.writeAsString('${jsonEncode(estado)}\n', flush: true);
    await _temporal.rename(_archivo.path);
    _lineas = 1;
    _escritura = await _archivo.open(mode: FileMode.append);
  }

  Future<void> cerrar() async {
    await _escritura?.close();
    _escritura = null;
  }
}
