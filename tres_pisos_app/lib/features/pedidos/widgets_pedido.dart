import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import 'modelos.dart';

class ChipEstado extends StatelessWidget {
  const ChipEstado(this.estado, {super.key});

  final EstadoPedido estado;

  @override
  Widget build(BuildContext context) {
    final color = Colores.deEstado(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        estado.etiqueta,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Renglón "2× Tacos de pastor" con la nota debajo.
class RenglonItem extends StatelessWidget {
  const RenglonItem(this.item, {super.key, this.mostrarPrecio = false, this.grande = false});

  final PedidoItem item;
  final bool mostrarPrecio;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final estilo = grande ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: grande ? 40 : 32,
            child: Text(
              '${item.cantidad}×',
              style: estilo?.copyWith(color: Colores.acento, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nombre, style: estilo),
                if (item.llevar)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.takeout_dining, size: 16, color: Colores.acento),
                      SizedBox(width: 4),
                      Text('Para llevar', style: TextStyle(color: Colores.acento, fontWeight: FontWeight.w600)),
                    ],
                  ),
                if (item.notaVisible != null)
                  Text(
                    item.notaVisible!,
                    style: const TextStyle(color: Colores.dorado, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
          if (mostrarPrecio) Text(dinero(item.subtotal)),
        ],
      ),
    );
  }
}

/// Tarjeta resumida de un pedido para las listas de mesero y caja.
class TarjetaPedido extends StatelessWidget {
  const TarjetaPedido({super.key, required this.pedido, this.onTap, this.accion});

  final Pedido pedido;
  final VoidCallback? onTap;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    pedido.tipo == TipoPedido.llevar ? Icons.takeout_dining : Icons.table_restaurant,
                    color: Colores.acento,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(pedido.titulo, style: texto.titleMedium)),
                  ChipEstado(pedido.estado),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                pedido.items.map((i) => '${i.cantidad}× ${i.nombre}').join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: texto.bodyMedium?.copyWith(color: Colores.apagado),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '#${pedido.id} · ${hora(pedido.creadoEn)}${pedido.mesero == null ? '' : ' · ${pedido.mesero}'}',
                    style: texto.bodySmall?.copyWith(color: Colores.apagado),
                  ),
                  const Spacer(),
                  Text(
                    dinero(pedido.total),
                    style: texto.titleMedium?.copyWith(color: Colores.dorado, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (accion != null) ...[const SizedBox(height: 12), accion!],
            ],
          ),
        ),
      ),
    );
  }
}
