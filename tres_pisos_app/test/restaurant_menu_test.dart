import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tres_pisos_app/local/menu_file.dart';
import 'package:tres_pisos_app/local/pos_engine.dart';

void main() {
  sqfliteFfiInit();
  test(
      'Owner menu: all 54 source IDs, exact prices, 53 active and Birria disabled',
      () async {
    final bytes = await File('assets/menu/restaurante.json').readAsBytes();
    final source = jsonDecode(utf8.decode(bytes))['productos'] as List;
    final menu = MenuFile.parse(bytes);
    expect(source.map((p) => p['id_origen']), List.generate(54, (i) => i + 25));
    // Prices transcribed independently from the three screenshots, by source ID.
    const expected = [
      60,
      75,
      70,
      45,
      50,
      65,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      40,
      50,
      30,
      30,
      40,
      40,
      40,
      50,
      18,
      18,
      20,
      20,
      90,
      75,
      80,
      75,
      50,
      45,
      25,
      45,
      30,
      25,
      25,
      30,
      20,
      30,
      20,
      25,
      45,
      50,
      65,
      65,
      50,
      30,
      100,
      50,
      80,
      65,
      75,
      35,
      45
    ];
    expect(menu.map((p) => PosEngine.money(p['precio'])),
        expected.map((p) => p * 100));
    expect(menu.where((p) => p['activo'] == true), hasLength(53));
    expect(menu.singleWhere((p) => p['activo'] == false)['nombre'], 'Birria');
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options:
            OpenDatabaseOptions(version: 2, onCreate: PosEngine.createSchema));
    try {
      final engine = PosEngine(db);
      expect(await engine.seedMenuIfEmpty(menu), true);
      final saved = await engine.records(db, 'products');
      expect(saved, hasLength(54));
      saved.first['precio'] = 99;
      await engine.save(db, 'products', saved.first);
      expect(await engine.seedMenuIfEmpty(menu), false);
      expect((await engine.record(db, 'products', 1))['precio'], 99);
      expect(await engine.records(db, 'orders'), isEmpty);
      expect(await engine.records(db, 'users'), isEmpty);
    } finally {
      await db.close();
    }
  });

  test(
      'Version 1 receipts migrate without keeping old passwords or losing retries',
      () async {
    final temp = await Directory.systemTemp.createTemp('pos-auth-upgrade-');
    final path = '${temp.path}/pos.db';
    var db = await databaseFactoryFfi.openDatabase(path,
        options:
            OpenDatabaseOptions(version: 1, onCreate: PosEngine.createSchema));
    const raw =
        '["POST","/api/auth/register",{"password":"private-old-password"}]';
    await db.insert('receipts', {
      'key': 'old-receipt',
      'user_id': 1,
      'fingerprint': raw,
      'response': '{"success":true}'
    });
    await db.close();
    db = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 2, onUpgrade: PosEngine.upgradeSchema));
    try {
      final receipt = (await db.query('receipts')).single;
      expect(receipt['fingerprint'], await PosEngine.receiptFingerprint(raw));
      expect(jsonEncode(receipt), isNot(contains('private-old-password')));
      expect(receipt['response'], '{"success":true}');
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
