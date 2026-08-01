import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulse/app/theme/pulse_theme.dart';
import 'package:pulse/application/settings_controller.dart';
import 'package:pulse/logging/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings persist across controller reload', () async {
    SharedPreferences.setMockInitialValues({});
    final logger = AppLogger();
    final a = SettingsController(logger: logger);
    await a.load();

    await a.setAutoScroll(false);
    await a.setLiveMonitoringEnabled(false);
    await a.setMaxStoredEvents(250);
    await a.setStartupSnapshotSize(40);
    await a.setCompactMode(true);
    await a.setAnimationsEnabled(false);
    await a.setDebugLogging(true);
    await a.setThemeMode('light');
    await a.setAccentPreset('purple');
    await a.setCustomAccentArgb(0xFF112233);
    await a.setAnimationSpeed(1.25);
    await a.completeWelcome();

    final b = SettingsController(logger: AppLogger());
    await b.load();

    expect(b.autoScroll, isFalse);
    expect(b.liveMonitoringEnabled, isFalse);
    expect(b.maxStoredEvents, 250);
    expect(b.startupSnapshotSize, 40);
    expect(b.compactMode, isTrue);
    expect(b.animationsEnabled, isFalse);
    expect(b.debugLogging, isTrue);
    expect(b.logger.debugEnabled, isTrue);
    expect(b.welcomeCompleted, isTrue);
    expect(b.themeMode, 'light');
    expect(b.accentPreset, 'purple');
    expect(b.customAccentArgb, 0xFF112233);
    expect(b.animationSpeed, 1.25);
    expect(b.materialThemeMode, ThemeMode.light);
    expect(b.resolvedAccent, PulseThemeData.accentPurple);
  });
}
