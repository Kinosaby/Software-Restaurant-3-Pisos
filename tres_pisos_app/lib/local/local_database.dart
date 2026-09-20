import 'package:sqflite/sqflite.dart';

import 'pos_engine.dart';

/// Shared by the app and the Android integration tests. Keep PRAGMAs that
/// return rows on rawQuery: Android rejects them through execute/execSQL.
Future<Database> openPosDatabase(String path) async {
  final db = await openDatabase(
    path,
    version: 3,
    onCreate: PosEngine.createSchema,
    onUpgrade: PosEngine.upgradeSchema,
    onConfigure: (db) async {
      await db.rawQuery('PRAGMA journal_mode=WAL');
      await db.execute('PRAGMA synchronous=NORMAL');
      await db.execute('PRAGMA busy_timeout=5000');
      await db.rawQuery('PRAGMA secure_delete=ON');
    },
  );
  try {
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    return db;
  } catch (_) {
    await db.close();
    rethrow;
  }
}
