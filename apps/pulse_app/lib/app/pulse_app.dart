import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/settings_controller.dart';
import '../presentation/onboarding/welcome_page.dart';
import '../presentation/shell/app_shell.dart';
import 'theme/pulse_theme.dart';

class PulseApp extends StatelessWidget {
  const PulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final accent = settings.resolvedAccent;
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
        // animationSpeed is persisted for later duration scaling; MediaQuery
        // has no animation-speed factor, so we only apply enable/compact today.
        return MediaQuery(
          data: media.copyWith(
            disableAnimations: !settings.animationsEnabled,
            textScaler: settings.compactMode
                ? TextScaler.linear(0.94)
                : media.textScaler,
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
