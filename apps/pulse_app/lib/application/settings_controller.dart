import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/theme/pulse_theme.dart';
import '../logging/app_logger.dart';

/// Persisted user preferences (local-only).
class SettingsController extends ChangeNotifier {
  SettingsController({required this.logger});

  final AppLogger logger;

  static const _kMaxEvents = 'timeline.max_events';
  static const _kSnapshotSize = 'timeline.snapshot_size';
  static const _kAutoScroll = 'timeline.auto_scroll';
  static const _kLiveMonitoring = 'timeline.live_monitoring';
  static const _kCompact = 'interface.compact';
  static const _kAnimations = 'interface.animations';
  static const _kDebugLogging = 'diagnostics.debug_logging';
  static const _kWelcomeDone = 'onboarding.welcome_completed';
  static const _kThemeMode = 'appearance.theme_mode';
  static const _kAccentPreset = 'appearance.accent_preset';
  static const _kCustomAccent = 'appearance.custom_accent_argb';
  static const _kAnimationSpeed = 'appearance.animation_speed';

  static const String buildDate = '2026-07-30';
  static const int defaultCustomAccentArgb = 0xFF60CDFF;

  SharedPreferences? _prefs;
  bool _ready = false;
  bool get ready => _ready;

  int maxStoredEvents = 500;
  int startupSnapshotSize = 100;
  bool autoScroll = true;
  bool liveMonitoringEnabled = true;
  bool compactMode = false;
  bool animationsEnabled = true;
  bool debugLogging = false;
  bool welcomeCompleted = false;

  /// `system` | `light` | `dark`
  String themeMode = 'dark';

  /// `blue` | `green` | `purple` | `orange` | `custom`
  String accentPreset = 'blue';

  int customAccentArgb = defaultCustomAccentArgb;

  /// Motion scale factor in range 0.5–1.5 (1.0 = default).
  double animationSpeed = 1.0;

  ThemeMode get materialThemeMode {
    switch (themeMode) {
      case 'system':
        return ThemeMode.system;
      case 'light':
        return ThemeMode.light;
      case 'dark':
      default:
        return ThemeMode.dark;
    }
  }

  Color get resolvedAccent {
    switch (accentPreset) {
      case 'green':
        return PulseThemeData.accentGreen;
      case 'purple':
        return PulseThemeData.accentPurple;
      case 'orange':
        return PulseThemeData.accentOrange;
      case 'custom':
        return Color(customAccentArgb);
      case 'blue':
      default:
        return PulseThemeData.accentBlue;
    }
  }

  PulseAccentPreset get accentPresetEnum {
    switch (accentPreset) {
      case 'green':
        return PulseAccentPreset.green;
      case 'purple':
        return PulseAccentPreset.purple;
      case 'orange':
        return PulseAccentPreset.orange;
      case 'custom':
        return PulseAccentPreset.custom;
      case 'blue':
      default:
        return PulseAccentPreset.blue;
    }
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    maxStoredEvents = p.getInt(_kMaxEvents) ?? 500;
    startupSnapshotSize = p.getInt(_kSnapshotSize) ?? 100;
    autoScroll = p.getBool(_kAutoScroll) ?? true;
    liveMonitoringEnabled = p.getBool(_kLiveMonitoring) ?? true;
    compactMode = p.getBool(_kCompact) ?? false;
    animationsEnabled = p.getBool(_kAnimations) ?? true;
    debugLogging = p.getBool(_kDebugLogging) ?? false;
    welcomeCompleted = p.getBool(_kWelcomeDone) ?? false;
    themeMode = _normalizeThemeMode(p.getString(_kThemeMode));
    accentPreset = _normalizeAccentPreset(p.getString(_kAccentPreset));
    customAccentArgb = p.getInt(_kCustomAccent) ?? defaultCustomAccentArgb;
    animationSpeed =
        (p.getDouble(_kAnimationSpeed) ?? 1.0).clamp(0.5, 1.5).toDouble();
    logger.debugEnabled = debugLogging;
    _ready = true;
    notifyListeners();
  }

  Future<void> setMaxStoredEvents(int value) async {
    maxStoredEvents = value.clamp(50, 2000);
    await _prefs?.setInt(_kMaxEvents, maxStoredEvents);
    notifyListeners();
  }

  Future<void> setStartupSnapshotSize(int value) async {
    startupSnapshotSize = value.clamp(20, 500);
    await _prefs?.setInt(_kSnapshotSize, startupSnapshotSize);
    notifyListeners();
  }

  Future<void> setAutoScroll(bool value) async {
    autoScroll = value;
    await _prefs?.setBool(_kAutoScroll, value);
    notifyListeners();
  }

  Future<void> setLiveMonitoringEnabled(bool value) async {
    liveMonitoringEnabled = value;
    await _prefs?.setBool(_kLiveMonitoring, value);
    notifyListeners();
  }

  Future<void> setCompactMode(bool value) async {
    compactMode = value;
    await _prefs?.setBool(_kCompact, value);
    notifyListeners();
  }

  Future<void> setAnimationsEnabled(bool value) async {
    animationsEnabled = value;
    await _prefs?.setBool(_kAnimations, value);
    notifyListeners();
  }

  Future<void> setDebugLogging(bool value) async {
    debugLogging = value;
    logger.debugEnabled = value;
    await _prefs?.setBool(_kDebugLogging, value);
    notifyListeners();
  }

  Future<void> setThemeMode(String value) async {
    themeMode = _normalizeThemeMode(value);
    await _prefs?.setString(_kThemeMode, themeMode);
    notifyListeners();
  }

  Future<void> setAccentPreset(String value) async {
    accentPreset = _normalizeAccentPreset(value);
    await _prefs?.setString(_kAccentPreset, accentPreset);
    notifyListeners();
  }

  Future<void> setCustomAccentArgb(int value) async {
    customAccentArgb = value;
    await _prefs?.setInt(_kCustomAccent, value);
    notifyListeners();
  }

  Future<void> setAnimationSpeed(double value) async {
    animationSpeed = value.clamp(0.5, 1.5).toDouble();
    await _prefs?.setDouble(_kAnimationSpeed, animationSpeed);
    notifyListeners();
  }

  Future<void> completeWelcome() async {
    welcomeCompleted = true;
    await _prefs?.setBool(_kWelcomeDone, true);
    notifyListeners();
  }

  Future<void> resetAll() async {
    maxStoredEvents = 500;
    startupSnapshotSize = 100;
    autoScroll = true;
    liveMonitoringEnabled = true;
    compactMode = false;
    animationsEnabled = true;
    debugLogging = false;
    welcomeCompleted = false;
    themeMode = 'dark';
    accentPreset = 'blue';
    customAccentArgb = defaultCustomAccentArgb;
    animationSpeed = 1.0;
    logger.debugEnabled = false;
    await _prefs?.clear();
    notifyListeners();
  }

  Map<String, dynamic> toMap() => {
        'max_stored_events': maxStoredEvents,
        'startup_snapshot_size': startupSnapshotSize,
        'auto_scroll': autoScroll,
        'live_monitoring_enabled': liveMonitoringEnabled,
        'compact_mode': compactMode,
        'animations_enabled': animationsEnabled,
        'debug_logging': debugLogging,
        'welcome_completed': welcomeCompleted,
        'theme_mode': themeMode,
        'accent_preset': accentPreset,
        'custom_accent_argb': customAccentArgb,
        'animation_speed': animationSpeed,
      };

  static String _normalizeThemeMode(String? value) {
    switch (value) {
      case 'system':
      case 'light':
      case 'dark':
        return value!;
      default:
        return 'dark';
    }
  }

  static String _normalizeAccentPreset(String? value) {
    switch (value) {
      case 'blue':
      case 'green':
      case 'purple':
      case 'orange':
      case 'custom':
        return value!;
      default:
        return 'blue';
    }
  }
}
