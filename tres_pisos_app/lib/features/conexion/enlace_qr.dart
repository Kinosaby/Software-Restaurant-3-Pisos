import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr/qr.dart';

import '../../central/seguridad.dart';
import '../../central/servidor_central.dart';
import '../../core/plataforma.dart';

/// Lo que viaja en el QR de la central: dónde está y su código de enlace.
///
/// Es un enlace `trespisos://enlace?ip=…&p=…&c=…&n=…`, así que también lo abre
/// la cámara normal de la tablet (o Google Lens) directamente en la app.
class DatosEnlace {
  const DatosEnlace({required this.ips, required this.puerto, required this.codigo, this.nombre});

  /// Todas las IP de la central (si tiene varias redes, se prueba cada una).
  final List<String> ips;
  final int puerto;
  final String codigo;
  final String? nombre;

  Uri get uri => Uri(
        scheme: 'trespisos',
        host: 'enlace',
        queryParameters: {
          'ip': ips.join(','),
          'p': '$puerto',
          'c': codigo,
          'n': ?nombre,
        },
      );

  List<String> get urls => [for (final ip in ips) 'http://$ip:$puerto'];

  /// `null` si el texto no es un enlace válido de Tres Pisos (otro QR, uno manipulado...).
  static DatosEnlace? leer(String? texto) {
    if (texto == null) return null;
    final uri = Uri.tryParse(texto.trim());
    if (uri == null || uri.scheme != 'trespisos' || uri.host != 'enlace') return null;
    final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
    final ips = [
      for (final ip in (uri.queryParameters['ip'] ?? '').split(','))
        if (ipv4.firstMatch(ip.trim()) case final m? when m.groups([1, 2, 3, 4]).every((g) => int.parse(g!) <= 255))
          ip.trim(),
    ];
    final puerto = int.tryParse(uri.queryParameters['p'] ?? '') ?? puertoCentral;
    final codigo = normalizarCodigo(uri.queryParameters['c'] ?? '');
    if (ips.isEmpty || puerto < 1 || puerto > 65535 || !RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}$').hasMatch(codigo)) {
      return null;
    }
    final nombre = uri.queryParameters['n']?.trim();
    return DatosEnlace(
      ips: ips,
      puerto: puerto,
      codigo: codigo,
      nombre: (nombre == null || nombre.isEmpty) ? null : nombre,
    );
  }
}

/// Se sobreescribe en `main()` si la app se abrió desde un QR leído con la cámara del sistema.
final enlaceInicialProvider = Provider<DatosEnlace?>((ref) => null);

/// QR de una central esperando confirmación para conectar esta tablet.
/// Llega del escáner de la app, del enlace con el que se abrió o de uno recibido con la app abierta.
final enlacePendienteProvider = NotifierProvider<EnlacePendiente, DatosEnlace?>(EnlacePendiente.new);

class EnlacePendiente extends Notifier<DatosEnlace?> {
  @override
  DatosEnlace? build() {
    final suscripcion = Plataforma.enlaces.listen((texto) {
      final datos = DatosEnlace.leer(texto);
      if (datos != null) state = datos;
    });
    ref.onDispose(suscripcion.cancel);
    return ref.read(enlaceInicialProvider);
  }

  void recibir(DatosEnlace datos) => state = datos;

  void descartar() => state = null;
}

/// Primero las IP de redes domésticas (192.168…, 10…, 172.16–31…), que son las del Wi-Fi.
List<String> ordenarIps(List<String> ips) {
  int prioridad(String ip) {
    if (ip.startsWith('192.168.')) return 0;
    if (ip.startsWith('10.')) return 1;
    final partes = ip.split('.');
    if (partes.length == 4 && partes[0] == '172') {
      final segundo = int.tryParse(partes[1]) ?? 0;
      if (segundo >= 16 && segundo <= 31) return 2;
    }
    return 3;
  }

  return [...ips]..sort((a, b) => prioridad(a).compareTo(prioridad(b)));
}

/// Dibuja el QR en negro sobre blanco con su margen, para que cualquier cámara lo lea.
class VistaQr extends StatelessWidget {
  const VistaQr({super.key, required this.datos, this.tamano = 260});

  final String datos;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final imagen = QrImage(QrCode(payload: QrPayload.fromString(datos), errorCorrectLevel: QrErrorCorrectLevel.medium));
    return Semantics(
      label: 'Código QR para enlazar tablets',
      child: Container(
        width: tamano,
        height: tamano,
        // Margen blanco de ~4 módulos, como pide el estándar, para que la cámara lo lea a la primera.
        padding: EdgeInsets.all(tamano * 0.1),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: CustomPaint(painter: _PintorQr(imagen)),
      ),
    );
  }
}

class _PintorQr extends CustomPainter {
  _PintorQr(this.imagen);

  final QrImage imagen;

  @override
  void paint(Canvas canvas, Size size) {
    final modulo = size.shortestSide / imagen.moduleCount;
    final tinta = Paint()..color = Colors.black;
    for (var fila = 0; fila < imagen.moduleCount; fila++) {
      for (var col = 0; col < imagen.moduleCount; col++) {
        if (imagen.isDark(fila, col)) {
          // Un poco más grande que el módulo para que no queden líneas finas entre cuadros.
          canvas.drawRect(Rect.fromLTWH(col * modulo, fila * modulo, modulo + 0.5, modulo + 0.5), tinta);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PintorQr anterior) => anterior.imagen != imagen;
}
