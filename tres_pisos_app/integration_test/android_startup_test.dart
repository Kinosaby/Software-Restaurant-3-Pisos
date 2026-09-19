import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:tres_pisos_app/local/local_app.dart';
import 'package:tres_pisos_app/local/local_database.dart';
import 'package:tres_pisos_app/local/menu_file.dart';
import 'package:tres_pisos_app/local/pos_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android SQLite: reproduce old failure, open, persist and reopen', (tester) async {
    expect(Platform.isAndroid, true, reason: 'This regression requires the native Android driver');
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/startup-${DateTime.now().microsecondsSinceEpoch}.db';
    Database? db;
    try {
      db = await openDatabase(path);
      // Reproduce the exact API misuse reported by the owner on Android.
      await expectLater(db.execute('PRAGMA secure_delete=ON'), throwsA(isA<DatabaseException>()));
      await db.close();
      db = await openPosDatabase(path);
      expect((await db.rawQuery('PRAGMA secure_delete')).single.values.single, 1);
      expect((await db.rawQuery('PRAGMA synchronous')).single.values.single, 2);
      expect((await db.rawQuery('PRAGMA journal_mode')).single.values.single, 'wal');
      final engine = PosEngine(db);
      await engine.bootstrap('native-admin', 'native-fixture-password');
      final bytes = await rootBundle.load('assets/menu/restaurante.json');
      await engine.seedMenuIfEmpty(MenuFile.parse(bytes.buffer.asUint8List()));
      final login = await engine.call('POST', Uri.parse('/api/auth/login'),
        body: {'username': 'native-admin', 'password': 'native-fixture-password'});
      final order = await engine.call('POST', Uri.parse('/api/pedidos'),
        body: {'mesa': 3, 'productos': [{'producto_id': 1, 'cantidad': 2}]},
        token: login['token'], operationId: randomKey());
      await db.close();
      db = await openPosDatabase(path);
      final reopened = PosEngine(db);
      expect((await reopened.call('GET', Uri.parse('/api/auth/me'), token: login['token']))['user']['role'], 'admin');
      expect(await reopened.records(db, 'products'), hasLength(54));
      expect((await reopened.records(db, 'orders')).single['id'], order['pedido']['id']);
      expect((await db.rawQuery('PRAGMA secure_delete')).single.values.single, 1);
      expect((await db.rawQuery('PRAGMA synchronous')).single.values.single, 2);
    } finally {
      if (db != null && db.isOpen) { await db.close(); }
      await deleteDatabase(path);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('Android setup reaches WebView, logs in and loads the owner menu', (tester) async {
    Future<void> until(Future<bool> Function() condition) async {
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (await condition()) { return; }
      }
      fail('Android startup did not reach the expected screen within 60 seconds');
    }
    await tester.pumpWidget(const LocalPosApp());
    await until(() async => find.text('Iniciar central').evaluate().isNotEmpty);
    expect(find.textContaining('DatabaseException'), findsNothing);
    await tester.enterText(find.byType(TextField).at(0), 'setup-admin');
    await tester.enterText(find.byType(TextField).at(1), 'setup-fixture-password');
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.ensureVisible(find.text('Iniciar central'));
    await tester.tap(find.text('Iniciar central'));
    await until(() async => find.byType(WebViewWidget).evaluate().isNotEmpty);
    final controller = tester.widget<WebViewWidget>(find.byType(WebViewWidget)).platform.params.controller;
    Future<bool> js(String expression) async =>
        await controller.runJavaScriptReturningResult('Boolean($expression)') == true;
    await until(() => js('window.LOCAL_POS && document.getElementById("login-form") && typeof doLogin === "function"'));
    await controller.runJavaScript('''
      document.getElementById('login-user').value = 'setup-admin';
      document.getElementById('login-pass').value = 'setup-fixture-password';
      doLogin();
    ''');
    await until(() => js('typeof Auth !== "undefined" && Auth.user && Auth.user.role === "admin"'));
    await controller.runJavaScript("get('/api/productos').then(r => window.nativeMenuCount = r.productos.length)");
    await until(() => js('window.nativeMenuCount === 54'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
