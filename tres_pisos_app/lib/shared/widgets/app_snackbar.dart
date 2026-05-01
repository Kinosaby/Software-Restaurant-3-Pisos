// lib/shared/widgets/app_snackbar.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AppSnackbar {
  static void ok(BuildContext context, String msg) {
    _show(context, msg, AppColors.success, Icons.check_circle_outline);
  }
  static void error(BuildContext context, String msg) {
    _show(context, msg, AppColors.danger, Icons.cancel_outlined);
  }
  static void info(BuildContext context, String msg) {
    _show(context, msg, AppColors.info, Icons.info_outline);
  }

  static void _show(BuildContext context, String msg, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(color: AppColors.textPrimary))),
        ]),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
