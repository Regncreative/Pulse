import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/settings_controller.dart';
import '../presentation/onboarding/welcome_page.dart';
import '../presentation/shell/app_shell.dart';
import '../presentation/utils/pulse_formatters.dart';
import 'theme/pulse_theme.dart';
import 'theme/pulse_window_chrome.dart';

class PulseApp extends StatelessWidget {
  const PulseApp({super.key});

  static const _themeCrossfade = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final accent = settings.resolvedAccent;
    PulseFormatters.binaryUnits = settings.byteUnitBinary;
    PulseFormatters.temperatureCelsius = settings.temperatureCelsius;
    PulseFormatters.clock24h = settings.clock24h;

    final light = PulseTheme.light(accent: accent);
    final dark = PulseTheme.dark(accent: accent);

    return MaterialApp(
      title: 'Pulse',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: settings.materialThemeMode,
      themeAnimationDuration: settings.animationsEnabled
          ? _themeCrossfade
          : Duration.zero,
      themeAnimationCurve: Curves.easeInOutCubic,
      color: Colors.transparent,
      builder: (context, child) {
        final theme = Theme.of(context);
        final pulse = theme.extension<PulseThemeData>() ??
            (theme.brightness == Brightness.dark
                ? PulseThemeData.dark(accent: accent)
                : PulseThemeData.light(accent: accent));

        // Sync ambient tokens on every Material theme animation frame so
        // PulseTokens.* callers never paint the previous palette.
        PulseThemeScope.sync(pulse);
        PulseWindowChrome.syncLater(theme.brightness);

        final media = MediaQuery.of(context);
        final compactFactor = settings.compactMode ? 0.94 : 1.0;
        final scale = (settings.textScale * compactFactor).clamp(0.85, 1.35);

        return MediaQuery(
          data: media.copyWith(
            disableAnimations: !settings.animationsEnabled,
            textScaler: TextScaler.linear(scale.toDouble()),
          ),
          child: _PulseThemeBridge(
            theme: pulse,
            themeMode: settings.themeMode,
            accentArgb: accent.toARGB32(),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: settings.welcomeCompleted
          ? const AppShell()
          : WelcomePage(
              onFinished: () {
                settings.completeWelcome();
              },
            ),
    );
  }
}

/// Inherited bridge — notifies dependents when the active palette identity
/// changes (mode, accent, or animated canvas). Combined with [Theme.of] in
/// [AppShell], this keeps PulseTokens consumers in sync during the 150ms
/// theme crossfade.
class _PulseThemeBridge extends InheritedWidget {
  const _PulseThemeBridge({
    required this.theme,
    required this.themeMode,
    required this.accentArgb,
    required super.child,
  });

  final PulseThemeData theme;
  final String themeMode;
  final int accentArgb;

  @override
  bool updateShouldNotify(_PulseThemeBridge oldWidget) {
    return themeMode != oldWidget.themeMode ||
        accentArgb != oldWidget.accentArgb ||
        theme.brightness != oldWidget.theme.brightness ||
        theme.canvas != oldWidget.theme.canvas ||
        theme.accent != oldWidget.theme.accent;
  }
}
