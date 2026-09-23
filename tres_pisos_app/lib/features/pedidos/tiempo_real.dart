import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../auth/auth_controller.dart';
import 'modelos.dart';

sealed class EventoTiempoReal {
  const EventoTiempoReal();
}

/// `nuevo_pedido` o `pedido_actualizado`: el servidor manda el pedido completo.
class PedidoCambiado extends EventoTiempoReal {
  const PedidoCambiado(this.pedido, {required this.nuevo});
  final Pedido pedido;
  final bool nuevo;
}

/// `extra_pedido`: solo los productos añadidos a un pedido ya terminado.
class ExtraRecibido extends EventoTiempoReal {
  const ExtraRecibido(this.extra);
  final ExtraPedido extra;
}

/// La conexión se (re)estableció: puede que se hayan perdido eventos mientras tanto.
class Conectado extends EventoTiempoReal {
  const Conectado();
}

/// Conexión Socket.IO con el backend mientras hay sesión.
class TiempoReal {
  TiempoReal(String servidor) {
    _socket = io.io(
      servidor,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableForceNew()
          .enableReconnection()
          .setReconnectionDelayMax(10000)
          .build(),
    );
    _socket.on('connect', (_) {
      _estado.add(true);
      _eventos.add(const Conectado());
    });
    _socket.on('disconnect', (_) => _estado.add(false));
    _socket.on('connect_error', (_) => _estado.add(false));
    _socket.on('nuevo_pedido', (datos) => _pedido(datos, nuevo: true));
    _socket.on('pedido_actualizado', (datos) => _pedido(datos, nuevo: false));
    _socket.on('extra_pedido', (datos) {
      if (datos is Map) {
        _eventos.add(ExtraRecibido(ExtraPedido.fromJson(Map<String, dynamic>.from(datos))));
      }
    });
  }

  late final io.Socket _socket;
  final _eventos = StreamController<EventoTiempoReal>.broadcast();
  final _estado = StreamController<bool>.broadcast();

  Stream<EventoTiempoReal> get eventos => _eventos.stream;
  Stream<bool> get conectado => _estado.stream;
  bool get estaConectado => _socket.connected;

  void _pedido(Object? datos, {required bool nuevo}) {
    if (datos is Map) {
      _eventos.add(PedidoCambiado(Pedido.fromJson(Map<String, dynamic>.from(datos)), nuevo: nuevo));
    }
  }

  void cerrar() {
    _socket.dispose();
    _eventos.close();
    _estado.close();
  }
}

final tiempoRealProvider = Provider.autoDispose<TiempoReal>((ref) {
  final servidor = ref.watch(authControllerProvider.select((s) => s?.servidor));
  if (servidor == null) {
    throw StateError('Tiempo real sin sesión');
  }
  final tiempoReal = TiempoReal(servidor);
  ref.onDispose(tiempoReal.cerrar);
  return tiempoReal;
});

final conexionProvider = StreamProvider.autoDispose<bool>((ref) async* {
  final tiempoReal = ref.watch(tiempoRealProvider);
  yield tiempoReal.estaConectado;
  yield* tiempoReal.conectado;
});
