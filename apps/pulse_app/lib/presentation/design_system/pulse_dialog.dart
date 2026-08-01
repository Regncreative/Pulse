import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';

/// Themed [AlertDialog] helper for Pulse confirmations and notices.
Future<T?> showPulseDialog<T>({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String? cancelLabel,
  bool barrierDismissible = true,
  VoidCallback? onConfirm,
}) {
  final theme = context.pulseTheme;
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: theme.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme.radiusXl),
          side: BorderSide(color: theme.stroke.withValues(alpha: 0.7)),
        ),
        title: Text(
          title,
          style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                color: theme.textPrimary,
              ),
        ),
        content: Text(
          message,
          style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                color: theme.textSecondary,
                height: 1.5,
              ),
        ),
        actions: [
          if (cancelLabel != null)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false as T?),
              child: Text(
                cancelLabel,
                style: TextStyle(color: theme.textSecondary),
              ),
            ),
          TextButton(
            onPressed: () {
              onConfirm?.call();
              Navigator.of(dialogContext).pop(true as T?);
            },
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: theme.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Confirm dialog returning `true` when the user confirms.
Future<bool> showPulseConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
}) async {
  final result = await showPulseDialog<bool>(
    context: context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
  );
  return result == true;
}
