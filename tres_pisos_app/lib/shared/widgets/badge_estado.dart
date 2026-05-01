// lib/shared/widgets/badge_estado.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class BadgeEstado extends StatelessWidget {
  final String estado;
  const BadgeEstado(this.estado, {super.key});

  Color get color {
    switch (estado) {
      case 'pendiente':  return AppColors.warning;
      case 'preparando': return AppColors.info;
      case 'listo':      return AppColors.success;
      case 'pagado':     return const Color(0xFF8B5CF6);
      case 'cancelado':  return AppColors.danger;
      default:           return AppColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        estado,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
