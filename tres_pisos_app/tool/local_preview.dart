// Development-only in-memory preview. Android never runs this entry point.
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tres_pisos_app/local/pos_engine.dart';
import 'package:tres_pisos_app/local/pos_server.dart';

Future<void> main() async {
  final password = Platform.environment['POS_PREVIEW_PASSWORD'];
  if (password == null || password.length < 8) {
    stderr.writeln('Set POS_PREVIEW_PASSWORD (8+ characters).');
    exitCode = 1;
    return;
  }
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 1, onCreate: PosEngine.createSchema),
  );
  final engine = PosEngine(db);
  await engine.bootstrap('admin', password);
  final token = (await engine.call(
    'POST',
    Uri.parse('/api/auth/login'),
    body: {'username': 'admin', 'password': password},
  ))['token'];
  for (final role in ['mesero', 'cocina']) {
    await engine.call(
      'POST',
      Uri.parse('/api/auth/register'),
      body: {'username': role, 'password': password, 'role': role},
      token: token,
      operationId: randomKey(),
    );
  }
  for (final p in [('Taco', 12.5, 'Tacos'), ('Agua', 20.0, 'Bebidas')]) {
    await engine.call(
      'POST',
      Uri.parse('/api/productos'),
      body: {'nombre': p.$1, 'precio': p.$2, 'categoria': p.$3},
      token: token,
      operationId: randomKey(),
    );
  }
  final server = PosServer(
    engine: engine,
    central: true,
    pairSecret: randomKey(),
    hubId: randomKey(),
    asset: (path) => File('assets/pos/$path').readAsBytes(),
  );
  await server.start();
  stdout.writeln(
    'Preview: http://127.0.0.1:8788 — users admin, mesero, cocina',
  );
  await ProcessSignal.sigterm.watch().first;
  await server.stop();
  await db.close();
}
