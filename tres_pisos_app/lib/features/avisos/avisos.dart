import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/almacen_local.dart';
import '../../core/formato.dart';
import '../../core/plataforma.dart';
import '../auth/auth_controller.dart';
import '../auth/sesion.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedidos_controller.dart';
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

/// Pantallas de cocina que se están viendo ahora mismo en esta tablet. La de un
/// administrador sigue montada aunque esté en otra pestaña: solo cuenta la visible.
class PantallaCocina {
  final _aLaVista = <Object>{};

  bool get aLaVista => _aLaVista.isNotEmpty;

  void fijar(Object pantalla, {required bool visible}) =>
      visible ? _aLaVista.add(pantalla) : _aLaVista.remove(pantalla);
}

/// Se consulta al llegar cada evento; no notifica cambios.
final pantallaCocinaProvider = Provider<PantallaCocina>((ref) => PantallaCocina());

/// Decide qué eventos merecen avisar a quién:
///  - Cocina (el rol, o cualquiera que esté viendo la pantalla de cocina): pedidos
///    nuevos y extras (dos pitidos + vibración).
///  - Mesero y admin: sus pedidos listos para servir y los que cocina canceló.
/// Cada pedido avisa una sola vez por estado, aunque el evento se repita.
class ReglasAviso {
  ReglasAviso(this.usuario);

  final Usuario usuario;
  final _avisados = <String>{};

  bool _esMio(Pedido p) => p.usuarioId == null || p.usuarioId == usuario.id;

  bool _primeraVez(String clave) => _avisados.add(clave);

  /// Devuelve el aviso y el tipo de sonido, o `null` si no hay que avisar.
  /// [enCocina]: la pantalla de cocina está a la vista. Una tablet de cocina con
  /// sesión de administrador también debe sonar cuando entra trabajo.
  ({Aviso aviso, String sonido})? evaluar(EventoTiempoReal evento, {bool enCocina = false}) {
    final rolCocina = usuario.rol == Rol.cocina;
    final cocina = rolCocina || enCocina;
    switch (evento) {
      case PedidoCambiado(:final pedido, nuevo: true) when cocina:
        if (!_primeraVez('nuevo-${pedido.id}')) return null;
        return (
          aviso: Aviso('Nuevo pedido · ${pedido.titulo} (${pedido.piezas} productos)', pedidoId: pedido.id, urgente: true),
          sonido: 'pedido',
        );
      case ExtraRecibido(:final extra) when cocina:
        final piezas = extra.items.fold(0, (s, i) => s + i.cantidad);
        return (aviso: Aviso('Extra · ${etiquetaMesa(extra.mesa, llevar: extra.tipo == TipoPedido.llevar)}: $piezas productos', urgente: true), sonido: 'pedido');
      case PedidoCambiado(:final pedido, nuevo: false, :final accion) when !rolCocina && _esMio(pedido):
        // Cocina lo regresó ("Deshacer"): cuando lo vuelva a terminar se avisa otra vez.
        if (pedido.estado.modificable) _olvidarListo(pedido.id);
        // Con un extra en cocina aún no se puede servir; cuando lo terminan cambian
        // las piezas y se vuelve a avisar.
        // Mover, dividir, editar o cobrar una cuenta ya lista cambia sus piezas,
        // pero no es que cocina haya terminado algo: no se vuelve a avisar.
        const sinAviso = {'producto_movido', 'producto_dividido', 'pedido_editado', 'parte_relevada', 'cobrado'};
        if (pedido.paraServir && !sinAviso.contains(accion) && _primeraVez('listo-${pedido.id}-${pedido.piezas}')) {
          return (aviso: Aviso('${pedido.titulo} está lista para servir', pedidoId: pedido.id), sonido: 'listo');
        }
        // Cobrado por adelantado: al terminarlo cocina se cierra solo, pero hay que entregarlo.
        if (accion == 'listo_pagado' && _primeraVez('listo-${pedido.id}-${pedido.piezas}')) {
          return (
            aviso: Aviso('${pedido.titulo} está lista para entregar (ya pagada)', pedidoId: pedido.id),
            sonido: 'listo',
          );
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

  void _olvidarListo(int pedidoId) => _avisados.removeWhere((c) => c.startsWith('listo-$pedidoId-'));

  /// Tras descargar la lista completa (al reconectar o al abrir la app): avisa de
  /// los pedidos propios que cocina terminó mientras esta tablet no recibía
  /// eventos. [antes] es lo que se tenía; lo que ya estaba listo o ya se avisó no
  /// se repite. Varios pedidos salen en un solo aviso.
  ({Aviso aviso, String sonido})? evaluarRecarga(List<Pedido> antes, List<Pedido> ahora) {
    if (usuario.rol == Rol.cocina) return null;
    final previos = {for (final p in antes) p.id: p};
    final listos = <Pedido>[];
    for (final p in ahora) {
      if (!_esMio(p)) continue;
      if (p.estado.modificable) _olvidarListo(p.id);
      final yaEstaba = previos[p.id]?.paraServir ?? false;
      if (p.paraServir && !yaEstaba && _primeraVez('listo-${p.id}-${p.piezas}')) listos.add(p);
    }
    if (listos.isEmpty) return null;
    return (
      aviso: listos.length == 1
          ? Aviso('${listos.single.titulo} está lista para servir', pedidoId: listos.single.id)
          : Aviso('Listas para servir: ${listos.map((p) => p.titulo).join(', ')}'),
      sonido: 'listo',
    );
  }
}

/// Flujo de avisos de la sesión actual. Lo escucha la pantalla principal para
/// mostrarlos; al escucharlo también mantiene viva la conexión en tiempo real.
final avisosProvider = StreamProvider.autoDispose<Aviso>((ref) {
  final usuario = ref.watch(authControllerProvider.select((s) => s?.usuario));
  if (usuario == null) return const Stream.empty();
  final reglas = ReglasAviso(usuario);
  final salida = StreamController<Aviso>();
  final pantallaCocina = ref.watch(pantallaCocinaProvider);
  void avisar(({Aviso aviso, String sonido})? resultado) {
    if (resultado == null || salida.isClosed) return;
    if (ref.read(sonidoActivoProvider)) {
      unawaited(Plataforma.sonar(resultado.sonido));
      unawaited(Plataforma.vibrar(resultado.aviso.urgente ? const [0, 350, 150, 350] : const [0, 250]));
    }
    salida.add(resultado.aviso);
  }

  final suscripcion = ref.watch(tiempoRealProvider).eventos.listen(
        (evento) => avisar(reglas.evaluar(evento, enCocina: pantallaCocina.aLaVista)),
      );
  // Lo que cocina terminó mientras esta tablet estaba sin Wi-Fi no llegó como
  // evento: se detecta al volver a descargar la lista.
  ref.listen(listaRecargadaProvider, (_, recarga) {
    if (recarga != null) avisar(reglas.evaluarRecarga(recarga.antes, recarga.ahora));
  });
  ref.onDispose(() {
    suscripcion.cancel();
    salida.close();
  });
  return salida.stream;
});
