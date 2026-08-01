import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulse/app/theme/pulse_theme.dart';
import 'package:pulse/application/settings_controller.dart';
import 'package:pulse/logging/app_logger.dart';
import 'package:pulse/presentation/health/health_view_models.dart';
import 'package:pulse/presentation/utils/pulse_formatters.dart';

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
    await a.setByteUnitBinary(false);
    await a.setTemperatureCelsius(false);
    await a.setClock24h(false);
    await a.setPerformanceMode('performance');
    await a.setShowAdvancedDiagnostics(true);
    await a.setExportDirectory(r'C:\PulseExports');
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
    expect(b.byteUnitBinary, isFalse);
    expect(b.temperatureCelsius, isFalse);
    expect(b.clock24h, isFalse);
    expect(b.performanceMode, 'performance');
    expect(b.showAdvancedDiagnostics, isTrue);
    expect(b.exportDirectory, r'C:\PulseExports');
    expect(b.materialThemeMode, ThemeMode.light);
    expect(b.resolvedAccent, PulseThemeData.accentPurple);
  });

  test('battery performance mode forces animations off', () async {
    SharedPreferences.setMockInitialValues({});
    final a = SettingsController(logger: AppLogger());
    await a.load();
    await a.setAnimationsEnabled(true);
    await a.setPerformanceMode('battery');
    expect(a.performanceMode, 'battery');
    expect(a.animationsEnabled, isFalse);

    final b = SettingsController(logger: AppLogger());
    await b.load();
    expect(b.performanceMode, 'battery');
    expect(b.animationsEnabled, isFalse);
  });

  test('toMap and applyFromMap roundtrip new prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final a = SettingsController(logger: AppLogger());
    await a.load();
    await a.setByteUnitBinary(false);
    await a.setTemperatureCelsius(false);
    await a.setClock24h(false);
    await a.setPerformanceMode('performance');
    await a.setShowAdvancedDiagnostics(true);
    await a.setExportDirectory('/tmp/pulse');
    await a.setThemeMode('system');

    final map = a.toMap();
    expect(map['byte_unit_binary'], isFalse);
    expect(map['temperature_celsius'], isFalse);
    expect(map['clock_24h'], isFalse);
    expect(map['performance_mode'], 'performance');
    expect(map['show_advanced_diagnostics'], isTrue);
    expect(map['export_directory'], '/tmp/pulse');

    SharedPreferences.setMockInitialValues({});
    final b = SettingsController(logger: AppLogger());
    await b.load();
    await b.applyFromMap(map);

    expect(b.byteUnitBinary, isFalse);
    expect(b.temperatureCelsius, isFalse);
    expect(b.clock24h, isFalse);
    expect(b.performanceMode, 'performance');
    expect(b.showAdvancedDiagnostics, isTrue);
    expect(b.exportDirectory, '/tmp/pulse');
    expect(b.themeMode, 'system');

    final c = SettingsController(logger: AppLogger());
    await c.load();
    expect(c.byteUnitBinary, isFalse);
    expect(c.performanceMode, 'performance');
    expect(c.showAdvancedDiagnostics, isTrue);
  });

  test('importSettingsFromJsonString applies exported JSON', () async {
    SharedPreferences.setMockInitialValues({});
    final a = SettingsController(logger: AppLogger());
    await a.load();
    await a.setMaxStoredEvents(333);
    await a.setByteUnitBinary(false);
    final json = '{"max_stored_events":333,"byte_unit_binary":false,'
        '"performance_mode":"battery","animations_enabled":true}';

    SharedPreferences.setMockInitialValues({});
    final b = SettingsController(logger: AppLogger());
    await b.load();
    await b.importSettingsFromJsonString(json);
    expect(b.maxStoredEvents, 333);
    expect(b.byteUnitBinary, isFalse);
    expect(b.performanceMode, 'battery');
    expect(b.animationsEnabled, isTrue);
  });

  test('resetAll clears Phase C prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final a = SettingsController(logger: AppLogger());
    await a.load();
    await a.setByteUnitBinary(false);
    await a.setShowAdvancedDiagnostics(true);
    await a.setPerformanceMode('battery');
    await a.setExportDirectory(r'D:\out');
    await a.setDashboardDensity('compact');
    await a.toggleDashboardWidgetVisibility('heroes');
    await a.setDashboardWidgetOrder(
      ['bottom', 'status', 'heroes', 'system', 'performance'],
    );
    await a.resetAll();
    expect(a.byteUnitBinary, isTrue);
    expect(a.temperatureCelsius, isTrue);
    expect(a.clock24h, isTrue);
    expect(a.performanceMode, 'balanced');
    expect(a.showAdvancedDiagnostics, isFalse);
    expect(a.exportDirectory, isEmpty);
    expect(a.animationsEnabled, isTrue);
    expect(a.dashboardDensity, 'comfortable');
    expect(a.dashboardHiddenWidgets, isEmpty);
    expect(
      a.dashboardWidgetOrder,
      SettingsController.defaultDashboardWidgetOrder,
    );
  });

  test('dashboard layout prefs persist and reorder', () async {
    SharedPreferences.setMockInitialValues({});
    final a = SettingsController(logger: AppLogger());
    await a.load();
    await a.setDashboardDensity('compact');
    await a.toggleDashboardWidgetVisibility('system');
    await a.reorderDashboardWidget(0, 4);
    expect(a.dashboardDensity, 'compact');
    expect(a.isDashboardWidgetVisible('system'), isFalse);
    expect(a.dashboardWidgetOrder.first, isNot('status'));

    final b = SettingsController(logger: AppLogger());
    await b.load();
    expect(b.dashboardDensity, 'compact');
    expect(b.isDashboardWidgetVisible('system'), isFalse);
    expect(b.dashboardWidgetOrder, a.dashboardWidgetOrder);

    final map = a.toMap();
    expect(map['dashboard_density'], 'compact');
    expect(map['dashboard_hidden_widgets'], contains('system'));

    SharedPreferences.setMockInitialValues({});
    final c = SettingsController(logger: AppLogger());
    await c.load();
    await c.applyFromMap(map);
    expect(c.dashboardDensity, 'compact');
    expect(c.isDashboardWidgetVisible('system'), isFalse);
    expect(c.dashboardWidgetOrder, a.dashboardWidgetOrder);
  });

  test('cycleThemeMode rotates dark light system', () async {
    SharedPreferences.setMockInitialValues({});
    final a = SettingsController(logger: AppLogger());
    await a.load();
    expect(a.themeMode, 'dark');
    await a.cycleThemeMode();
    expect(a.themeMode, 'light');
    await a.cycleThemeMode();
    expect(a.themeMode, 'system');
    await a.cycleThemeMode();
    expect(a.themeMode, 'dark');
  });

  test('PulseFormatters drive byte and temperature labels', () {
    PulseFormatters.binaryUnits = true;
    expect(formatBytesBinary(2048, fractionDigits: 0), '2 KiB');
    PulseFormatters.binaryUnits = false;
    expect(formatBytesBinary(2000, fractionDigits: 0), '2 KB');

    PulseFormatters.temperatureCelsius = true;
    expect(formatTempC(true, 40), '40 °C');
    PulseFormatters.temperatureCelsius = false;
    expect(formatTempC(true, 40), '104 °F');

    PulseFormatters.binaryUnits = true;
    PulseFormatters.temperatureCelsius = true;
  });
}
