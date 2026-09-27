import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../central/servidor_central.dart' show cierreSesionInvalida;
import '../auth/auth_controller.dart';
import 'modelos.dart';

sealed class EventoTiempoReal {
  const EventoTiempoReal();
}

/// `nuevo_pedido` o `pedido_actualizado`: el servidor manda el pedido completo.
class PedidoCambiado extends EventoTiempoReal {
  const PedidoCambiado(this.pedido, {required this.nuevo, this.accion});
  final Pedido pedido;
  final bool nuevo;

  /// `_accion` del evento, p. ej. `listo_pagado`: cocina terminó un pedido cobrado por adelantado.
  final String? accion;
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
        _eventos.add(PedidoCambiado(Pedido.fromJson(mapa), nuevo: false, accion: mapa['_accion']?.toString()));
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
///
/// Cada conexión usa el token vigente en ese momento ([token]), así que tras una
/// renovación basta con reconectar. Si la central cierra el socket porque la
/// sesión dejó de valer ([cierreSesionInvalida]), se reconecta enseguida; si al
/// conectar responde 401, la sesión ya no sirve: avisa con [alSesionInvalida] y
/// deja de reintentar.
class TiempoRealCentral extends TiempoReal {
  TiempoRealCentral(
    String servidor, {
    required this._token,
    required this._enlace,
    this.alSesionInvalida,
  }) : _servidor = Uri.parse(servidor) {
    unawaited(_conectar());
  }

  final Uri _servidor;
  final String? Function() _token;
  final String _enlace;
  final void Function()? alSesionInvalida;
  final _cliente = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  WebSocket? _ws;
  bool _cerrado = false;
  int _intentos = 0;

  Uri get _url => _servidor.replace(
        scheme: _servidor.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws',
        queryParameters: {'token': _token() ?? '', 'enlace': _enlace},
      );

  Future<void> _conectar() async {
    while (!_cerrado) {
      try {
        final intento = WebSocket.connect(_url.toString(), customClient: _cliente);
        final ws = await intento.timeout(const Duration(seconds: 6), onTimeout: () {
          // Si el intento lento acaba conectando después, se cierra para no dejar un socket huérfano.
          unawaited(intento.then((tarde) => tarde.close(), onError: (_) {}));
          throw TimeoutException('La central no respondió');
        });
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
        // Cerrado por la central (p. ej. [cierreSesionInvalida]): se reconecta en 1 s con el token actual.
      } on WebSocketException catch (e) {
        if (e.httpStatusCode == 401) {
          _ws = null;
          if (_conectado) _marcarConexion(false);
          if (!_cerrado) alSesionInvalida?.call();
          return;
        }
        // Otro rechazo (central reiniciando, red no permitida...): se reintenta abajo.
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
    _cliente.close(force: true);
    super.cerrar();
  }
}

final tiempoRealProvider = Provider.autoDispose<TiempoReal>((ref) {
  // Sin el token: renovarlo no reabre el socket (la reconexión ya usa el nuevo).
  final sesion = ref.watch(sesionActivaProvider);
  if (sesion == null) {
    throw StateError('Tiempo real sin sesión');
  }
  final enlace = ref.watch(conexionProvider.select((c) => c?.enlace)) ?? sesion.enlace ?? '';
  final auth = ref.read(authControllerProvider.notifier);
  final TiempoReal tiempoReal = TiempoRealCentral(
    sesion.servidor,
    token: () => auth.tokenActual,
    enlace: enlace,
    alSesionInvalida: () => unawaited(auth.cerrarSesion()),
  );
  // Al (re)conectar se renueva el token si ya pasó la mitad de su vigencia.
  final suscripcion = tiempoReal.eventos.listen((evento) {
    if (evento is Conectado) unawaited(auth.renovarSiHaceFalta());
  });
  ref.onDispose(() {
    unawaited(suscripcion.cancel());
    tiempoReal.cerrar();
  });
  return tiempoReal;
});

final conexionTiempoRealProvider = StreamProvider.autoDispose<bool>((ref) async* {
  final tiempoReal = ref.watch(tiempoRealProvider);
  yield tiempoReal.estaConectado;
  yield* tiempoReal.conectado;
});
