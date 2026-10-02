import 'dart:convert';
import 'dart:io';

/// Almacenamiento de la central: un archivo de líneas JSON al que solo se añade.
///
/// Cada operación de negocio escribe **una** línea (un lote de registros) y la
/// fuerza a disco antes de responder, así que una operación queda completa o no
/// queda. Si la tablet se apaga a mitad de una escritura, la última línea queda
/// cortada: al cargar se descarta y se recorta del archivo, para que la
/// siguiente escritura empiece en una línea limpia.
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
  bool _cargado = false;
  int _lineas = 0;

  /// Bytes del archivo que son líneas completas; lo que haya después es basura.
  int _tamano = 0;

  static const _saltoDeLinea = 10;

  int get lineas => _lineas;

  /// Lee todos los lotes válidos, en orden.
  Future<List<List<Map<String, dynamic>>>> cargar() async {
    // Una compactación interrumpida deja el temporal: el diario original sigue intacto.
    if (await _temporal.exists()) await _temporal.delete();
    if (!await _archivo.exists()) await _archivo.create(recursive: true);

    final bytes = await _archivo.readAsBytes();
    final lotes = <List<Map<String, dynamic>>>[];
    var inicio = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != _saltoDeLinea) continue;
      final lote = _leerLinea(bytes.sublist(inicio, i));
      if (lote != null) lotes.add(lote);
      inicio = i + 1;
    }
    // Lo que queda después del último salto de línea es una escritura cortada
    // (corte de luz): se descarta aquí y se recorta del archivo al abrirlo.
    _tamano = inicio;
    _lineas = lotes.length;
    _cargado = true;
    await _cerrarEscritura();
    _escritura = await _abrirEscritura();
    return lotes;
  }

  /// Una línea ilegible (JSON incompleto o un carácter partido) se descarta sin tumbar la carga.
  static List<Map<String, dynamic>>? _leerLinea(List<int> bytes) {
    try {
      final linea = utf8.decode(bytes);
      if (linea.trim().isEmpty) return null;
      return (jsonDecode(linea) as List).cast<Map<String, dynamic>>();
    } on Object {
      return null;
    }
  }

  /// Abre el diario para añadir, recortando cualquier resto posterior a la última línea completa.
  Future<RandomAccessFile> _abrirEscritura() async {
    final escritura = await _archivo.open(mode: FileMode.append);
    try {
      final longitud = await escritura.length();
      if (longitud > _tamano) {
        await escritura.truncate(_tamano);
        await escritura.flush();
      } else if (longitud < _tamano) {
        _tamano = longitud;
      }
      await escritura.setPosition(_tamano);
      return escritura;
    } on Object {
      await escritura.close();
      rethrow;
    }
  }

  Future<void> _cerrarEscritura() async {
    final escritura = _escritura;
    _escritura = null;
    if (escritura == null) return;
    try {
      await escritura.close();
    } on Object {
      // Si no cierra, no hay nada más que hacer con él.
    }
  }

  Future<void> escribir(List<Map<String, dynamic>> lote) async {
    if (!_cargado) throw StateError('Diario sin cargar');
    // Si una escritura o compactación anterior dejó el diario cerrado, se reabre aquí.
    final escritura = _escritura ??= await _abrirEscritura();
    final bytes = utf8.encode('${jsonEncode(lote)}\n');
    try {
      await escritura.writeFrom(bytes);
      await escritura.flush();
    } on Object {
      // El archivo vuelve a su tamaño anterior para no dejar media línea.
      try {
        await escritura.truncate(_tamano);
        await escritura.setPosition(_tamano);
      } on Object {
        // Se cierra; la próxima escritura lo reabre y recorta hasta [_tamano].
        await _cerrarEscritura();
      }
      rethrow;
    }
    _tamano += bytes.length;
    _lineas++;
  }

  /// Reemplaza el diario por una sola línea con el estado completo.
  ///
  /// Si falla, el diario anterior queda intacto y se vuelve a abrir para seguir
  /// escribiendo; el error se propaga.
  Future<void> compactar(List<Map<String, dynamic>> estado) async {
    if (!_cargado) throw StateError('Diario sin cargar');
    await _cerrarEscritura();
    try {
      final bytes = utf8.encode('${jsonEncode(estado)}\n');
      await _temporal.writeAsBytes(bytes, flush: true);
      await _temporal.rename(_archivo.path);
      _lineas = 1;
      _tamano = bytes.length;
      // Tras el rename habría que hacer fsync de la carpeta para que el cambio de
      // nombre sobreviva a un corte de luz, pero dart:io no puede abrir una
      // carpeta como archivo (File.open la rechaza) ni expone fsync de carpetas.
      // Si el rename se pierde, al arrancar queda el diario anterior completo
      // (el temporal se borra), así que no se pierden datos confirmados.
    } on Object {
      try {
        if (await _temporal.exists()) await _temporal.delete();
      } on Object {
        // Se borra en el siguiente arranque.
      }
      rethrow;
    } finally {
      try {
        _escritura = await _abrirEscritura();
      } on Object {
        // La próxima escritura intenta reabrirlo.
      }
    }
  }

  Future<void> cerrar() async {
    await _cerrarEscritura();
    _cargado = false;
  }
}
