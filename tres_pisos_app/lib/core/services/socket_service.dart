// lib/core/services/socket_service.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../constants/api_constants.dart';

class SocketService {
  static IO.Socket? _socket;
  static bool _connected = false;

  static IO.Socket get socket {
    _socket ??= IO.io(
      ApiConstants.baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .build(),
    );
    return _socket!;
  }

  static void connect() {
    if (_connected) return;
    socket.connect();
    socket.onConnect((_) => _connected = true);
    socket.onDisconnect((_) => _connected = false);
  }

  static void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _connected = false;
  }

  static bool get isConnected => _connected;

  static void on(String event, Function(dynamic) handler) {
    socket.on(event, handler);
  }

  static void off(String event) {
    socket.off(event);
  }
}
