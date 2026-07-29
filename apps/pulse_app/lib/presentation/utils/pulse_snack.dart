import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';

/// Consistent floating feedback across Timeline, Health, Diagnostics, Settings.
abstract final class PulseSnack {
  static void success(BuildContext context, String message) {
    _show(context, message, background: PulseTokens.successSoft, foreground: PulseTokens.success);
  }

  static void error(BuildContext context, String message) {
    _show(context, message, background: PulseTokens.errorSoft, foreground: PulseTokens.error);
  }

  static void info(BuildContext context, String message) {
    _show(context, message, background: PulseTokens.infoSoft, foreground: PulseTokens.info);
  }

  static void _show(
    BuildContext context,
    String message, {
    required Color background,
    required Color foreground,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: PulseTokens.textPrimary,
            fontSize: 13.5,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: background,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
          side: BorderSide(color: foreground.withValues(alpha: 0.28)),
        ),
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      ),
    );
  }
}
