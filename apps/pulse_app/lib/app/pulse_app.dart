import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/settings_controller.dart';
import '../presentation/onboarding/welcome_page.dart';
import '../presentation/shell/app_shell.dart';
import '../presentation/utils/pulse_formatters.dart';
import 'theme/pulse_theme.dart';

class PulseApp extends StatelessWidget {
  const PulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final accent = settings.resolvedAccent;
    PulseFormatters.binaryUnits = settings.byteUnitBinary;
    PulseFormatters.temperatureCelsius = settings.temperatureCelsius;
    PulseFormatters.clock24h = settings.clock24h;
    return MaterialApp(
      title: 'Pulse',
      debugShowCheckedModeBanner: false,
      theme: PulseTheme.light(accent: accent),
      darkTheme: PulseTheme.dark(accent: accent),
      themeMode: settings.materialThemeMode,
      color: Colors.transparent,
      builder: (context, child) {
        final pulse = Theme.of(context).extension<PulseThemeData>();
        if (pulse != null) {
          PulseThemeScope.current = pulse;
        }

        final media = MediaQuery.of(context);
        final compactFactor = settings.compactMode ? 0.94 : 1.0;
        final scale = (settings.textScale * compactFactor).clamp(0.85, 1.35);
        return MediaQuery(
          data: media.copyWith(
            disableAnimations: !settings.animationsEnabled,
            textScaler: TextScaler.linear(scale.toDouble()),
          ),
          child: child ?? const SizedBox.shrink(),
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
