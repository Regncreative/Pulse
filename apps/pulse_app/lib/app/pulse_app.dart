import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/settings_controller.dart';
import '../presentation/shell/app_shell.dart';
import 'theme/pulse_theme.dart';

class PulseApp extends StatelessWidget {
  const PulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return MaterialApp(
      title: 'Pulse',
      debugShowCheckedModeBanner: false,
      theme: PulseTheme.dark(),
      color: Colors.transparent,
      builder: (context, child) {
        final media = MediaQuery.of(context);
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
      home: const AppShell(),
    );
  }
}
