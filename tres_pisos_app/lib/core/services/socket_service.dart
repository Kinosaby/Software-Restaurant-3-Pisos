// lib/core/services/socket_service.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../constants/api_constants.dart';
import 'auth_service.dart';

class SocketService {
  static IO.Socket? _socket;
  static bool _connected = false;

  static Future<void> connect() async {
    if (_connected || _socket != null) return;
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) return;

    _socket = IO.io(
      ApiConstants.baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    _socket!.onConnect((_) => _connected = true);
    _socket!.onDisconnect((_) => _connected = false);
    _socket!.onConnectError((_) => _connected = false);
    _socket!.connect();
  }

  static void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _connected = false;
  }

  static bool get isConnected => _connected;

  static void on(String event, Function(dynamic) handler) {
    _socket?.off(event);
    _socket?.on(event, handler);
  }

  static void off(String event) {
    _socket?.off(event);
  }
}
