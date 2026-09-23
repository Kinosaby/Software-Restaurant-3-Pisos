import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// `pedido_eliminado`: el administrador borró el pedido.
class PedidoEliminado extends EventoTiempoReal {
  const PedidoEliminado(this.id);
  final int id;
}

/// La conexión se (re)estableció: puede que se hayan perdido eventos mientras tanto.
class Conectado extends EventoTiempoReal {
  const Conectado();
}

/// Canal de avisos en tiempo real con la central.
abstract class TiempoReal {
  final _eventos = StreamController<EventoTiempoReal>.broadcast();
  final _estado = StreamController<bool>.broadcast();
  bool _conectado = false;

  Stream<EventoTiempoReal> get eventos => _eventos.stream;
  Stream<bool> get conectado => _estado.stream;
  bool get estaConectado => _conectado;

  void _marcarConexion(bool conectado) {
    if (_eventos.isClosed) return;
    _conectado = conectado;
    _estado.add(conectado);
    if (conectado) _eventos.add(const Conectado());
  }

  /// Traduce un evento con nombre y datos JSON; ignora los desconocidos.
  void _recibir(String evento, Object? datos) {
    if (_eventos.isClosed || datos is! Map) return;
    final mapa = Map<String, dynamic>.from(datos);
    switch (evento) {
      case 'nuevo_pedido':
        _eventos.add(PedidoCambiado(Pedido.fromJson(mapa), nuevo: true));
      case 'pedido_actualizado':
        _eventos.add(PedidoCambiado(Pedido.fromJson(mapa), nuevo: false));
      case 'extra_pedido':
        _eventos.add(ExtraRecibido(ExtraPedido.fromJson(mapa)));
      case 'pedido_eliminado':
        _eventos.add(PedidoEliminado(leerEntero(mapa['id'])));
    }
  }

  void cerrar() {
    _eventos.close();
    _estado.close();
  }
}

/// WebSocket con la central de cocina; se reconecta solo con espera creciente (1 s → 10 s).
class TiempoRealCentral extends TiempoReal {
  TiempoRealCentral(String servidor, {required String token, required String enlace})
      : _url = Uri.parse(servidor).replace(
          scheme: servidor.startsWith('https') ? 'wss' : 'ws',
          path: '/ws',
          queryParameters: {'token': token, 'enlace': enlace},
        ) {
    unawaited(_conectar());
  }

  final Uri _url;
  WebSocket? _ws;
  bool _cerrado = false;
  int _intentos = 0;

  Future<void> _conectar() async {
    while (!_cerrado) {
      try {
        final ws = await WebSocket.connect(_url.toString()).timeout(const Duration(seconds: 6));
        if (_cerrado) {
          await ws.close();
          return;
        }
        _ws = ws..pingInterval = const Duration(seconds: 10);
        _intentos = 0;
        _marcarConexion(true);
        await for (final mensaje in ws) {
          if (mensaje is! String) continue;
          try {
            final datos = jsonDecode(mensaje) as Map<String, dynamic>;
            _recibir(datos['evento'] as String, datos['datos']);
          } on Object {
            // Mensaje malformado: se ignora.
          }
        }
      } on Object {
        // Central apagada o Wi-Fi caído: se reintenta abajo.
      }
      _ws = null;
      if (_cerrado) return;
      if (_conectado) _marcarConexion(false);
      _intentos++;
      await Future<void>.delayed(Duration(seconds: _intentos.clamp(1, 10)));
    }
  }

  @override
  void cerrar() {
    _cerrado = true;
    _ws?.close();
    super.cerrar();
  }
}

final tiempoRealProvider = Provider.autoDispose<TiempoReal>((ref) {
  final sesion = ref.watch(authControllerProvider);
  if (sesion == null) {
    throw StateError('Tiempo real sin sesión');
  }
  final enlace = ref.watch(conexionProvider.select((c) => c?.enlace)) ?? sesion.conexion.enlace ?? '';
  final TiempoReal tiempoReal = TiempoRealCentral(sesion.servidor, token: sesion.token, enlace: enlace);
  ref.onDispose(tiempoReal.cerrar);
  return tiempoReal;
});

final conexionTiempoRealProvider = StreamProvider.autoDispose<bool>((ref) async* {
  final tiempoReal = ref.watch(tiempoRealProvider);
  yield tiempoReal.estaConectado;
  yield* tiempoReal.conectado;
});
