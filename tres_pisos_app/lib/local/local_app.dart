import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'pos_engine.dart';
import 'pos_server.dart';

class LocalPosApp extends StatelessWidget {
  const LocalPosApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '3 Pisos',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffc99b48),
        brightness: Brightness.dark,
      ),
    ),
    home: const LocalPosScreen(),
  );
}

({Uri address, String key, String id}) parsePairing(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null ||
      uri.scheme != 'trespisos' ||
      uri.port != 8787 ||
      uri.userInfo.isNotEmpty) {
    throw PosError(400, 'Pega el código completo de la tablet de cocina');
  }
  final parts = uri.host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((n) => n == null || n < 0 || n > 255)) {
    throw PosError(400, 'El enlace debe usar una dirección de la red local');
  }
  final private =
      parts[0] == 10 ||
      (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31) ||
      (parts[0] == 192 && parts[1] == 168);
  final key = uri.queryParameters['key'] ?? '',
      id = uri.queryParameters['id'] ?? '';
  if (!private || id.length < 16 || id.length > 128) {
    throw PosError(400, 'Código de enlace inválido');
  }
  try {
    if (base64Url.decode(key).length != 32) {
      throw const FormatException();
    }
  } catch (_) {
    throw PosError(400, 'La clave de enlace está incompleta');
  }
  return (
    address: Uri(scheme: 'http', host: uri.host, port: uri.port),
    key: key,
    id: id,
  );
}

Future<String> backupKey(String password, String salt) async {
  final k =
      await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 210000,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: utf8.encode(salt),
      );
  return base64UrlEncode(await k.extractBytes());
}

class LocalPosScreen extends StatefulWidget {
  const LocalPosScreen({super.key});
  @override
  State<LocalPosScreen> createState() => _LocalPosScreenState();
}

class _LocalPosScreenState extends State<LocalPosScreen>
    with WidgetsBindingObserver {
  final storage = const FlutterSecureStorage();
  final username = TextEditingController(),
      password = TextEditingController(),
      pairing = TextEditingController();
  PosEngine? engine;
  PosServer? server;
  WebViewController? web;
  bool busy = true, centralChoice = true, hasAccounts = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    username.dispose();
    password.dispose();
    pairing.dispose();
    server?.stop();
    engine?.db.close();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && server != null) {
      WakelockPlus.enable();
      server!.sync();
      web?.runJavaScript("window.dispatchEvent(new Event('pos-refresh'))");
    }
  }

  Future<void> initialize() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final db = await openDatabase(
        '${dir.path}/local-pos-v2.db',
        version: 1,
        onCreate: PosEngine.createSchema,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA synchronous=FULL');
        },
      );
      engine = PosEngine(db);
      hasAccounts = (await engine!.records(db, 'users')).isNotEmpty;
      final mode = await engine!.setting('mode');
      if (mode != null) {
        final key = await storage.read(key: 'lan-key'),
            id = await engine!.setting('hub-id');
        if (key == null || id == null) {
          throw PosError(
            409,
            'No se encontró la clave de enlace. Conserva los datos y revisa la configuración.',
          );
        }
        await launch(
          mode == 'central',
          key,
          id,
          await engine!.setting('hub-url'),
        );
      }
    } catch (e) {
      error = '$e';
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<List<int>> asset(String path) async =>
      (await rootBundle.load('assets/pos/$path')).buffer.asUint8List();
  Future<void> launch(bool central, String key, String id, String? url) async {
    final next = PosServer(
      engine: engine!,
      central: central,
      pairSecret: key,
      hubId: id,
      hub: url == null ? null : Uri.parse(url),
      asset: asset,
    );
    try {
      await next.start();
    } catch (_) {
      await next.stop();
      rethrow;
    }
    server = next;
    final origin = 'http://127.0.0.1:${next.localServer!.port}',
        controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          return uri != null && uri.scheme == 'http' && uri.origin == origin
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ),
    );
    await controller.setOnJavaScriptAlertDialog((r) async {
      await ask(r.message, confirmOnly: true, cancel: false);
    });
    await controller.setOnJavaScriptConfirmDialog(
      (r) async => await ask(r.message, confirmOnly: true) != null,
    );
    await controller.setOnJavaScriptTextInputDialog(
      (r) async => await ask(r.message, initial: r.defaultText) ?? '',
    );
    await controller.addJavaScriptChannel(
      'PosNative',
      onMessageReceived: (m) async {
        try {
          final d = jsonDecode(m.message) as Json;
          if (d['action'] == 'settings') {
            await connectionDetails();
          }
          if (d['action'] == 'backup') {
            await exportBackup(d['token']);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('$e')));
          }
        }
      },
    );
    if (controller.platform is AndroidWebViewController) {
      await (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    await controller.loadRequest(Uri.parse(origin));
    await WakelockPlus.enable();
    if (mounted) {
      setState(() => web = controller);
    }
  }

  Future<String?> ask(
    String title, {
    bool confirmOnly = false,
    bool cancel = true,
    String? initial,
    bool secret = false,
  }) async {
    if (!mounted) {
      return null;
    }
    final input = TextEditingController(text: initial);
    final answer = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: confirmOnly
            ? null
            : TextField(
                controller: input,
                obscureText: secret,
                autofocus: true,
              ),
        actions: [
          if (cancel)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, confirmOnly ? 'ok' : input.text),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), input.dispose);
    return answer;
  }

  Future<void> configure() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (engine == null) {
        throw PosError(500, 'No se pudo abrir el almacenamiento');
      }
      if (centralChoice) {
        if (!hasAccounts) {
          await engine!.bootstrap(username.text, password.text);
          hasAccounts = true;
        }
        final key = randomKey(), id = randomKey();
        await storage.write(key: 'lan-key', value: key);
        await engine!.setSetting('hub-id', id);
        await engine!.setSetting('mode', 'central');
        await launch(true, key, id, null);
        await connectionDetails();
      } else {
        final p = parsePairing(pairing.text);
        await probe(p);
        final old = await engine!.setting('hub-id');
        if (old != null && old != p.id) {
          throw PosError(
            409,
            'Esta tablet está vinculada a otra central. Conserva sus pedidos pendientes antes de cambiarla.',
          );
        }
        await storage.write(key: 'lan-key', value: p.key);
        await engine!.setSetting('hub-id', p.id);
        await engine!.setSetting('hub-url', p.address.toString());
        await engine!.setSetting('mode', 'client');
        await launch(false, p.key, p.id, p.address.toString());
      }
    } catch (e) {
      error = e is PosError ? e.message : 'No se pudo conectar. Revisa el código y que las tablets estén en el mismo Wi-Fi.';
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> probe(({Uri address, String key, String id}) p) async {
    final check = PosServer(
      engine: engine!,
      central: false,
      pairSecret: p.key,
      hubId: p.id,
      hub: p.address,
      asset: asset,
    );
    try {
      await check.remote({
        'method': 'GET',
        'path': '/api/local/ping',
        'body': {},
      });
    } finally {
      await check.stop();
    }
  }

  Future<void> connectionDetails() async {
    final current = server!;
    if (!current.central) {
      final code = await ask(
        'Actualizar enlace con la misma cocina',
        initial:
            'trespisos://${current.hub!.host}:8787?key=${current.pairSecret}&id=${current.hubId}',
      );
      if (code == null) {
        return;
      }
      final p = parsePairing(code);
      if (p.id != current.hubId || p.key != current.pairSecret) {
        throw PosError(
          409,
          'Usa la misma central para conservar los envíos pendientes',
        );
      }
      await probe(p);
      await engine!.setSetting('hub-url', p.address.toString());
      await current.stop();
      await launch(false, p.key, p.id, p.address.toString());
      return;
    }
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final codes = <String>[];
    for (final a in interfaces.expand((i) => i.addresses)) {
      final code =
          'trespisos://${a.address}:8787?key=${current.pairSecret}&id=${current.hubId}';
      try {
        parsePairing(code);
        codes.add(code);
      } catch (_) {}
    }
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Esta tablet es la central'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mantén 3 Pisos abierta en cocina, con batería y conectada al Wi-Fi. Internet no es necesario. En las tablets de meseros selecciona Vincular y pega este código. Compártelo solo con tu personal.',
              ),
              if (codes.isEmpty)
                const Text(
                  'Conecta esta tablet al Wi-Fi y vuelve a abrir Conexión.',
                ),
              for (final code in codes)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    children: [
                      SelectableText(code),
                      TextButton(
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: code)),
                        child: const Text('Copiar código'),
                      ),
                    ],
                  ),
                ),
              const Text(
                'Si cambia la dirección Wi-Fi de cocina, copia el nuevo código a los meseros. Guarda un respaldo al terminar el servicio.',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  Future<void> exportBackup(String? token) async {
    if (server?.central != true) {
      throw PosError(
        400,
        'Guarda el respaldo desde la tablet central con sesión de administrador',
      );
    }
    final data = await engine!.call(
      'GET',
      Uri.parse('/api/local/backup'),
      token: token,
    );
    final pass = await ask(
      'Contraseña del respaldo (mínimo 8 caracteres). Guárdala para restaurar.',
      secret: true,
    );
    if (pass == null) {
      return;
    }
    if (pass.length < 8) {
      throw PosError(400, 'Usa al menos 8 caracteres');
    }
    final salt = randomKey();
    final cipher = LanCipher(await backupKey(pass, salt));
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/3-Pisos-${DateTime.now().millisecondsSinceEpoch}.3pisos',
    );
    await file.writeAsString(
      jsonEncode({
        'format': '3pisos-encrypted-v1',
        'salt': salt,
        'box': await cipher.seal(data),
      }),
      flush: true,
    );
    await Share.shareXFiles(
      [XFile(file.path)],
      text:
          'Respaldo cifrado de 3 Pisos. Guarda el archivo fuera de la tablet.',
    );
  }

  Future<void> restoreBackup() async {
    try {
      final selected = await FilePicker.platform.pickFiles(type: FileType.any);
      if (selected == null || selected.files.single.path == null) {
        return;
      }
      final pass = await ask('Contraseña del respaldo', secret: true);
      if (pass == null) {
        return;
      }
      setState(() => busy = true);
      final outer = jsonDecode(
        await File(selected.files.single.path!).readAsString(),
      ) as Json;
      if (outer['format'] != '3pisos-encrypted-v1') {
        throw PosError(400, 'Archivo no compatible');
      }
      final data = await LanCipher(await backupKey(pass, outer['salt']))
          .open(Json.from(outer['box']));
      await engine!.restore(data);
      hasAccounts = true;
      centralChoice = true;
      error = 'Respaldo recuperado. Inicia la central y entra con tus usuarios anteriores. Luego vincula de nuevo las tablets.';
    } catch (_) {
      error = 'No se pudo restaurar. Revisa archivo y contraseña. No se modificaron los datos.';
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (web != null) {
      return Scaffold(
        body: SafeArea(child: WebViewWidget(controller: web!)),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '3 PISOS',
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sistema local del restaurante\nMeseros, cocina y administración completos. Sin servidor de pago.',
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Central de cocina'),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('Vincular tablet'),
                      ),
                    ],
                    selected: {centralChoice},
                    onSelectionChanged: busy || hasAccounts
                        ? null
                        : (v) => setState(() => centralChoice = v.first),
                  ),
                  const SizedBox(height: 20),
                  if (centralChoice) ...[
                    const Text(
                      'Configura una sola central: la tablet que permanecerá en cocina. Las otras tablets se vinculan a ella por Wi-Fi.',
                    ),
                    if (!hasAccounts) ...[
                      TextField(
                        controller: username,
                        decoration: const InputDecoration(
                          labelText: 'Nuevo usuario administrador',
                        ),
                        autocorrect: false,
                      ),
                      TextField(
                        controller: password,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña (mínimo 8 caracteres)',
                        ),
                        obscureText: true,
                      ),
                    ],
                  ] else ...[
                    const Text(
                      'Abre Conexión en la tablet de cocina y copia su código. Ambas tablets deben estar en el mismo Wi-Fi.',
                    ),
                    TextField(
                      controller: pairing,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Código trespisos://…',
                      ),
                      autocorrect: false,
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.amber),
                      ),
                    ),
                  FilledButton(
                    onPressed: busy ? null : configure,
                    child: Text(
                      busy
                          ? 'Preparando…'
                          : centralChoice
                          ? 'Iniciar central'
                          : 'Vincular con cocina',
                    ),
                  ),
                  if (!hasAccounts && centralChoice)
                    TextButton(
                      onPressed: busy ? null : restoreBackup,
                      child: const Text('Restaurar un respaldo local'),
                    ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
