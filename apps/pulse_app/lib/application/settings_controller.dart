import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const String buildDate = '2026-07-30';

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
      };
}
