import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

/// Keeps the Win32 mica/acrylic window effect in sync with Flutter brightness.
///
/// Light theme must use `dark: false` — leaving dark mica under light paints
/// is the main cause of the washed-out light UI.
abstract final class PulseWindowChrome {
  static Brightness? _applied;

  static Future<void> sync(Brightness brightness) async {
    if (_applied == brightness) return;
    _applied = brightness;
    final dark = brightness == Brightness.dark;
    try {
      await Window.setEffect(effect: WindowEffect.mica, dark: dark);
    } catch (_) {
      try {
        await Window.setEffect(effect: WindowEffect.acrylic, dark: dark);
      } catch (_) {
        // Solid Flutter fills remain as fallback.
      }
    }
  }

  /// Fire-and-forget sync from the UI isolate (post-frame safe).
  static void syncLater(Brightness brightness) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sync(brightness);
    });
  }
}
