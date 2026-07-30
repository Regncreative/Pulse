import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });
}
