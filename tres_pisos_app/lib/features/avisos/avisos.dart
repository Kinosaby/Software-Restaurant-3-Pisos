import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/almacen_local.dart';
import '../../core/plataforma.dart';
import '../auth/auth_controller.dart';
import '../auth/sesion.dart';
import '../pedidos/modelos.dart';
import '../pedidos/tiempo_real.dart';

/// Aviso para mostrar en pantalla (el sonido y la vibración ya se dispararon).
class Aviso {
  const Aviso(this.mensaje, {this.pedidoId, this.urgente = false});

  final String mensaje;
  final int? pedidoId;
  final bool urgente;
}

/// Sonido y vibración de los avisos; se recuerda por tablet.
final sonidoActivoProvider = NotifierProvider<SonidoActivo, bool>(SonidoActivo.new);

class SonidoActivo extends Notifier<bool> {
  @override
  bool build() => ref.watch(almacenLocalProvider).preferencia('sonido');

  void alternar() {
    state = !state;
    unawaited(ref.read(almacenLocalProvider).guardarPreferencia('sonido', state));
  }
}

/// Decide qué eventos merecen avisar a quién:
///  - Cocina: pedidos nuevos y extras (dos pitidos + vibración).
///  - Mesero y admin: sus pedidos listos para servir y los que cocina canceló.
/// Cada pedido avisa una sola vez por estado, aunque el evento se repita.
class ReglasAviso {
  ReglasAviso(this.usuario);

  final Usuario usuario;
  final _avisados = <String>{};

  bool _esMio(Pedido p) => p.usuarioId == null || p.usuarioId == usuario.id;

  bool _primeraVez(String clave) => _avisados.add(clave);

  /// Devuelve el aviso y el tipo de sonido, o `null` si no hay que avisar.
  ({Aviso aviso, String sonido})? evaluar(EventoTiempoReal evento) {
    final cocina = usuario.rol == Rol.cocina;
    switch (evento) {
      case PedidoCambiado(:final pedido, nuevo: true) when cocina:
        if (!_primeraVez('nuevo-${pedido.id}')) return null;
        return (
          aviso: Aviso('Nuevo pedido · ${pedido.titulo} (${pedido.piezas} productos)', pedidoId: pedido.id, urgente: true),
          sonido: 'pedido',
        );
      case ExtraRecibido(:final extra) when cocina:
        final piezas = extra.items.fold(0, (s, i) => s + i.cantidad);
        return (aviso: Aviso('Extra para mesa ${extra.mesa}: $piezas productos', urgente: true), sonido: 'pedido');
      case PedidoCambiado(:final pedido, nuevo: false) when !cocina && _esMio(pedido):
        if (pedido.estado == EstadoPedido.listo && _primeraVez('listo-${pedido.id}')) {
          return (aviso: Aviso('${pedido.titulo} está lista para servir', pedidoId: pedido.id), sonido: 'listo');
        }
        if (pedido.estado == EstadoPedido.cancelado && _primeraVez('cancelado-${pedido.id}')) {
          return (
            aviso: Aviso('Se canceló el pedido #${pedido.id} (${pedido.titulo})', pedidoId: pedido.id, urgente: true),
            sonido: 'aviso',
          );
        }
        return null;
      default:
        return null;
    }
  }
}

/// Flujo de avisos de la sesión actual. Lo escucha la pantalla principal para
/// mostrarlos; al escucharlo también mantiene viva la conexión en tiempo real.
final avisosProvider = StreamProvider.autoDispose<Aviso>((ref) {
  final usuario = ref.watch(authControllerProvider.select((s) => s?.usuario));
  if (usuario == null) return const Stream.empty();
  final reglas = ReglasAviso(usuario);
  final salida = StreamController<Aviso>();
  final suscripcion = ref.watch(tiempoRealProvider).eventos.listen((evento) {
    final resultado = reglas.evaluar(evento);
    if (resultado == null) return;
    if (ref.read(sonidoActivoProvider)) {
      unawaited(Plataforma.sonar(resultado.sonido));
      unawaited(Plataforma.vibrar(resultado.aviso.urgente ? const [0, 350, 150, 350] : const [0, 250]));
    }
    salida.add(resultado.aviso);
  });
  ref.onDispose(() {
    suscripcion.cancel();
    salida.close();
  });
  return salida.stream;
});
