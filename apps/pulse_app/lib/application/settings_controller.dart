import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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
  static const _kTextScale = 'appearance.text_scale';
  static const _kHealthSectionsExpanded = 'health.sections.expanded';
  static const _kByteUnitBinary = 'health.byte_unit_binary';
  static const _kTemperatureCelsius = 'health.temperature_celsius';
  static const _kClock24h = 'health.clock_24h';
  static const _kDashboardWidgetOrder = 'health.dashboard.widget_order';
  static const _kDashboardHiddenWidgets = 'health.dashboard.hidden_widgets';
  static const _kDashboardDensity = 'health.dashboard.density';
  static const _kPerformanceMode = 'performance.mode';
  static const _kShowAdvancedDiagnostics = 'diagnostics.show_advanced';
  static const _kExportDirectory = 'exports.directory';
  static const _kBackgroundMode = 'background.mode';
  static const _kStartWithWindows = 'background.start_with_windows';
  static const _kSystemNotifications = 'background.system_notifications';
  static const _kNotificationsPaused = 'background.notifications_paused';
  static const _kNotificationCooldownMinutes =
      'background.notification_cooldown_minutes';
  static const _kAssistantLocalAiProvider = 'assistant.local_ai.provider_id';
  static const _kAssistantLocalAiModel = 'assistant.local_ai.model_id';

  static const String buildDate = '2026-08-02';
  /// Default cooldown between repeat notifications for the same alert kind.
  static const int defaultNotificationCooldownMinutes = 15;
  static const int defaultCustomAccentArgb = 0xFF60CDFF;
  static const String defaultSettingsExportFileName = 'settings-export.json';
  static const String releasesUrl =
      'https://github.com/Regncreative/Pulse/releases';

  /// Default System Health dashboard section order.
  static const List<String> defaultDashboardWidgetOrder = [
    'status',
    'heroes',
    'system',
    'performance',
    'bottom',
  ];

  static const Set<String> _knownDashboardWidgets = {
    'status',
    'heroes',
    'system',
    'performance',
    'bottom',
  };

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

  /// Map key: `"cpu.overview"` etc. `true` = expanded.
  Map<String, bool> healthSectionExpanded = {};

  /// Ordered System Health dashboard widget ids.
  List<String> dashboardWidgetOrder =
      List<String>.from(defaultDashboardWidgetOrder);

  /// Hidden dashboard widget ids (still present in [dashboardWidgetOrder]).
  Set<String> dashboardHiddenWidgets = {};

  /// `compact` | `comfortable`
  String dashboardDensity = 'comfortable';

  /// `system` | `light` | `dark`
  String themeMode = 'dark';

  /// `blue` | `green` | `purple` | `orange` | `custom`
  String accentPreset = 'blue';

  int customAccentArgb = defaultCustomAccentArgb;

  /// Motion scale factor in range 0.5–1.5 (1.0 = default).
  double animationSpeed = 1.0;

  /// Text scale factor in range 0.9–1.3 (1.0 = default).
  double textScale = 1.0;

  /// Binary (KiB/MiB) vs decimal (KB/MB) byte labels.
  bool byteUnitBinary = true;

  /// Celsius vs Fahrenheit for health temperatures.
  bool temperatureCelsius = true;

  /// 24-hour vs 12-hour clock formatting preference.
  bool clock24h = true;

  /// `balanced` | `performance` | `battery`
  String performanceMode = 'balanced';

  bool showAdvancedDiagnostics = false;

  /// Empty = Documents/Pulse default. Absolute path when set.
  String exportDirectory = '';

  /// Keep Pulse.exe alive in the system tray when the main window is closed.
  bool backgroundMode = false;

  /// Register Pulse.exe for user-session startup (not PulseService).
  bool startWithWindows = false;

  /// Allow local Windows notifications for sustained critical conditions.
  /// Default off (privacy / roadmap R10).
  bool systemNotifications = false;

  /// Temporary mute from the tray menu (persisted).
  bool notificationsPaused = false;

  /// Minutes between repeat notifications for the same alert kind.
  int notificationCooldownMinutes = defaultNotificationCooldownMinutes;

  /// Persisted Assistant local runtime id (`ollama`, `lm_studio`, …).
  String? assistantLocalAiProviderId;

  /// Persisted Assistant model id for the selected runtime.
  String? assistantLocalAiModelId;

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
    maxStoredEvents = (p.getInt(_kMaxEvents) ?? 500).clamp(50, 100000);
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
    textScale =
        (p.getDouble(_kTextScale) ?? 1.0).clamp(0.9, 1.3).toDouble();
    healthSectionExpanded =
        _decodeHealthSections(p.getString(_kHealthSectionsExpanded));
    dashboardWidgetOrder =
        _decodeDashboardOrder(p.getString(_kDashboardWidgetOrder));
    dashboardHiddenWidgets =
        _decodeDashboardHidden(p.getString(_kDashboardHiddenWidgets));
    dashboardDensity = _normalizeDashboardDensity(p.getString(_kDashboardDensity));
    byteUnitBinary = p.getBool(_kByteUnitBinary) ?? true;
    temperatureCelsius = p.getBool(_kTemperatureCelsius) ?? true;
    clock24h = p.getBool(_kClock24h) ?? true;
    performanceMode = _normalizePerformanceMode(p.getString(_kPerformanceMode));
    showAdvancedDiagnostics = p.getBool(_kShowAdvancedDiagnostics) ?? false;
    exportDirectory = p.getString(_kExportDirectory) ?? '';
    backgroundMode = p.getBool(_kBackgroundMode) ?? false;
    startWithWindows = p.getBool(_kStartWithWindows) ?? false;
    systemNotifications = p.getBool(_kSystemNotifications) ?? false;
    notificationsPaused = p.getBool(_kNotificationsPaused) ?? false;
    notificationCooldownMinutes =
        (p.getInt(_kNotificationCooldownMinutes) ??
                defaultNotificationCooldownMinutes)
            .clamp(1, 180);
    assistantLocalAiProviderId =
        _normalizeOptionalId(p.getString(_kAssistantLocalAiProvider));
    assistantLocalAiModelId =
        _normalizeOptionalId(p.getString(_kAssistantLocalAiModel));
    logger.debugEnabled = debugLogging;
    _ready = true;
    notifyListeners();
  }

  Future<void> setMaxStoredEvents(int value) async {
    // Flagship Timeline can retain up to 100k events in memory (RAM cost grows
    // with message size). Default remains 500 for typical machines.
    maxStoredEvents = value.clamp(50, 100000);
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

  Future<void> setBackgroundMode(bool value) async {
    backgroundMode = value;
    await _prefs?.setBool(_kBackgroundMode, value);
    notifyListeners();
  }

  Future<void> setStartWithWindows(bool value) async {
    startWithWindows = value;
    await _prefs?.setBool(_kStartWithWindows, value);
    notifyListeners();
  }

  Future<void> setSystemNotifications(bool value) async {
    systemNotifications = value;
    await _prefs?.setBool(_kSystemNotifications, value);
    notifyListeners();
  }

  Future<void> setNotificationsPaused(bool value) async {
    notificationsPaused = value;
    await _prefs?.setBool(_kNotificationsPaused, value);
    notifyListeners();
  }

  Future<void> setNotificationCooldownMinutes(int value) async {
    notificationCooldownMinutes = value.clamp(1, 180);
    await _prefs?.setInt(
      _kNotificationCooldownMinutes,
      notificationCooldownMinutes,
    );
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

  Future<void> setTextScale(double value) async {
    textScale = value.clamp(0.9, 1.3).toDouble();
    await _prefs?.setDouble(_kTextScale, textScale);
    notifyListeners();
  }

  Future<void> setByteUnitBinary(bool value) async {
    byteUnitBinary = value;
    await _prefs?.setBool(_kByteUnitBinary, value);
    notifyListeners();
  }

  Future<void> setTemperatureCelsius(bool value) async {
    temperatureCelsius = value;
    await _prefs?.setBool(_kTemperatureCelsius, value);
    notifyListeners();
  }

  Future<void> setClock24h(bool value) async {
    clock24h = value;
    await _prefs?.setBool(_kClock24h, value);
    notifyListeners();
  }

  Future<void> setPerformanceMode(String value) async {
    performanceMode = _normalizePerformanceMode(value);
    await _prefs?.setString(_kPerformanceMode, performanceMode);
    if (performanceMode == 'battery' && animationsEnabled) {
      animationsEnabled = false;
      await _prefs?.setBool(_kAnimations, false);
    }
    notifyListeners();
  }

  Future<void> setShowAdvancedDiagnostics(bool value) async {
    showAdvancedDiagnostics = value;
    await _prefs?.setBool(_kShowAdvancedDiagnostics, value);
    notifyListeners();
  }

  Future<void> setExportDirectory(String value) async {
    exportDirectory = value.trim();
    await _prefs?.setString(_kExportDirectory, exportDirectory);
    notifyListeners();
  }

  Future<void> completeWelcome() async {
    welcomeCompleted = true;
    await _prefs?.setBool(_kWelcomeDone, true);
    notifyListeners();
  }

  Future<void> resetOnboarding() async {
    welcomeCompleted = false;
    await _prefs?.setBool(_kWelcomeDone, false);
    notifyListeners();
  }

  /// Whether a System Health detail section is expanded.
  ///
  /// Key format: `"$kind.$sectionId"` (e.g. `"cpu.overview"`).
  bool isHealthSectionExpanded(
    String kind,
    String sectionId, {
    bool defaultExpanded = true,
  }) {
    return healthSectionExpanded['$kind.$sectionId'] ?? defaultExpanded;
  }

  Future<void> setHealthSectionExpanded(
    String kind,
    String sectionId,
    bool expanded,
  ) async {
    healthSectionExpanded['$kind.$sectionId'] = expanded;
    await _prefs?.setString(
      _kHealthSectionsExpanded,
      jsonEncode(healthSectionExpanded),
    );
    notifyListeners();
  }

  bool isDashboardWidgetVisible(String widgetId) =>
      !dashboardHiddenWidgets.contains(widgetId);

  Future<void> setDashboardWidgetOrder(List<String> order) async {
    dashboardWidgetOrder = _normalizeDashboardOrder(order);
    await _prefs?.setString(
      _kDashboardWidgetOrder,
      jsonEncode(dashboardWidgetOrder),
    );
    notifyListeners();
  }

  Future<void> reorderDashboardWidget(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= dashboardWidgetOrder.length) return;
    final next = List<String>.from(dashboardWidgetOrder);
    final item = next.removeAt(oldIndex);
    final target = newIndex.clamp(0, next.length);
    next.insert(target, item);
    await setDashboardWidgetOrder(next);
  }

  Future<void> setDashboardWidgetVisible(String widgetId, bool visible) async {
    if (!_knownDashboardWidgets.contains(widgetId)) return;
    if (visible) {
      dashboardHiddenWidgets.remove(widgetId);
    } else {
      dashboardHiddenWidgets.add(widgetId);
    }
    await _prefs?.setString(
      _kDashboardHiddenWidgets,
      jsonEncode(dashboardHiddenWidgets.toList()..sort()),
    );
    notifyListeners();
  }

  Future<void> toggleDashboardWidgetVisibility(String widgetId) async {
    await setDashboardWidgetVisible(
      widgetId,
      !isDashboardWidgetVisible(widgetId),
    );
  }

  Future<void> setDashboardDensity(String value) async {
    dashboardDensity = _normalizeDashboardDensity(value);
    await _prefs?.setString(_kDashboardDensity, dashboardDensity);
    notifyListeners();
  }

  /// Cycles theme: dark → light → system → dark.
  Future<void> cycleThemeMode() async {
    final next = switch (themeMode) {
      'dark' => 'light',
      'light' => 'system',
      _ => 'dark',
    };
    await setThemeMode(next);
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
    textScale = 1.0;
    healthSectionExpanded = {};
    dashboardWidgetOrder = List<String>.from(defaultDashboardWidgetOrder);
    dashboardHiddenWidgets = {};
    dashboardDensity = 'comfortable';
    byteUnitBinary = true;
    temperatureCelsius = true;
    clock24h = true;
    performanceMode = 'balanced';
    showAdvancedDiagnostics = false;
    exportDirectory = '';
    backgroundMode = false;
    startWithWindows = false;
    systemNotifications = false;
    notificationsPaused = false;
    notificationCooldownMinutes = defaultNotificationCooldownMinutes;
    assistantLocalAiProviderId = null;
    assistantLocalAiModelId = null;
    logger.debugEnabled = false;
    await _prefs?.clear();
    notifyListeners();
  }

  Future<void> setAssistantLocalAiSelection({
    String? providerId,
    String? modelId,
  }) async {
    assistantLocalAiProviderId = _normalizeOptionalId(providerId);
    assistantLocalAiModelId = _normalizeOptionalId(modelId);
    final p = _prefs;
    if (p != null) {
      if (assistantLocalAiProviderId == null) {
        await p.remove(_kAssistantLocalAiProvider);
      } else {
        await p.setString(
          _kAssistantLocalAiProvider,
          assistantLocalAiProviderId!,
        );
      }
      if (assistantLocalAiModelId == null) {
        await p.remove(_kAssistantLocalAiModel);
      } else {
        await p.setString(_kAssistantLocalAiModel, assistantLocalAiModelId!);
      }
    }
    notifyListeners();
  }

  String? _normalizeOptionalId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
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
        'text_scale': textScale,
        'health_sections_expanded':
            Map<String, bool>.from(healthSectionExpanded),
        'dashboard_widget_order': List<String>.from(dashboardWidgetOrder),
        'dashboard_hidden_widgets':
            dashboardHiddenWidgets.toList()..sort(),
        'dashboard_density': dashboardDensity,
        'byte_unit_binary': byteUnitBinary,
        'temperature_celsius': temperatureCelsius,
        'clock_24h': clock24h,
        'performance_mode': performanceMode,
        'show_advanced_diagnostics': showAdvancedDiagnostics,
        'export_directory': exportDirectory,
        'background_mode': backgroundMode,
        'start_with_windows': startWithWindows,
        'system_notifications': systemNotifications,
        'notifications_paused': notificationsPaused,
        'notification_cooldown_minutes': notificationCooldownMinutes,
        'assistant_local_ai_provider_id': assistantLocalAiProviderId,
        'assistant_local_ai_model_id': assistantLocalAiModelId,
      };

  /// Applies a settings map (from export JSON) and persists each field.
  Future<void> applyFromMap(Map<String, dynamic> map) async {
    if (map.containsKey('max_stored_events')) {
      final v = map['max_stored_events'];
      if (v is int) maxStoredEvents = v.clamp(50, 100000);
    }
    if (map.containsKey('startup_snapshot_size')) {
      final v = map['startup_snapshot_size'];
      if (v is int) startupSnapshotSize = v.clamp(20, 500);
    }
    if (map['auto_scroll'] is bool) autoScroll = map['auto_scroll'] as bool;
    if (map['live_monitoring_enabled'] is bool) {
      liveMonitoringEnabled = map['live_monitoring_enabled'] as bool;
    }
    if (map['compact_mode'] is bool) compactMode = map['compact_mode'] as bool;
    if (map['animations_enabled'] is bool) {
      animationsEnabled = map['animations_enabled'] as bool;
    }
    if (map['debug_logging'] is bool) {
      debugLogging = map['debug_logging'] as bool;
      logger.debugEnabled = debugLogging;
    }
    if (map['welcome_completed'] is bool) {
      welcomeCompleted = map['welcome_completed'] as bool;
    }
    if (map['theme_mode'] is String) {
      themeMode = _normalizeThemeMode(map['theme_mode'] as String);
    }
    if (map['accent_preset'] is String) {
      accentPreset = _normalizeAccentPreset(map['accent_preset'] as String);
    }
    if (map['custom_accent_argb'] is int) {
      customAccentArgb = map['custom_accent_argb'] as int;
    }
    if (map['animation_speed'] is num) {
      animationSpeed =
          (map['animation_speed'] as num).toDouble().clamp(0.5, 1.5).toDouble();
    }
    if (map['text_scale'] is num) {
      textScale =
          (map['text_scale'] as num).toDouble().clamp(0.9, 1.3).toDouble();
    }
    if (map['health_sections_expanded'] is Map) {
      healthSectionExpanded = _decodeHealthSections(
        jsonEncode(map['health_sections_expanded']),
      );
    }
    if (map['dashboard_widget_order'] is List) {
      dashboardWidgetOrder = _normalizeDashboardOrder(
        (map['dashboard_widget_order'] as List)
            .whereType<String>()
            .toList(growable: false),
      );
    }
    if (map['dashboard_hidden_widgets'] is List) {
      dashboardHiddenWidgets = _normalizeDashboardHidden(
        (map['dashboard_hidden_widgets'] as List)
            .whereType<String>()
            .toSet(),
      );
    }
    if (map['dashboard_density'] is String) {
      dashboardDensity =
          _normalizeDashboardDensity(map['dashboard_density'] as String);
    }
    if (map['byte_unit_binary'] is bool) {
      byteUnitBinary = map['byte_unit_binary'] as bool;
    }
    if (map['temperature_celsius'] is bool) {
      temperatureCelsius = map['temperature_celsius'] as bool;
    }
    if (map['clock_24h'] is bool) clock24h = map['clock_24h'] as bool;
    if (map['performance_mode'] is String) {
      performanceMode =
          _normalizePerformanceMode(map['performance_mode'] as String);
    }
    if (map['show_advanced_diagnostics'] is bool) {
      showAdvancedDiagnostics = map['show_advanced_diagnostics'] as bool;
    }
    if (map['export_directory'] is String) {
      exportDirectory = (map['export_directory'] as String).trim();
    }
    if (map['background_mode'] is bool) {
      backgroundMode = map['background_mode'] as bool;
    }
    if (map['start_with_windows'] is bool) {
      startWithWindows = map['start_with_windows'] as bool;
    }
    if (map['system_notifications'] is bool) {
      systemNotifications = map['system_notifications'] as bool;
    }
    if (map['notifications_paused'] is bool) {
      notificationsPaused = map['notifications_paused'] as bool;
    }
    if (map['notification_cooldown_minutes'] is int) {
      notificationCooldownMinutes =
          (map['notification_cooldown_minutes'] as int).clamp(1, 180);
    }
    if (map.containsKey('assistant_local_ai_provider_id')) {
      assistantLocalAiProviderId = _normalizeOptionalId(
        map['assistant_local_ai_provider_id']?.toString(),
      );
    }
    if (map.containsKey('assistant_local_ai_model_id')) {
      assistantLocalAiModelId = _normalizeOptionalId(
        map['assistant_local_ai_model_id']?.toString(),
      );
    }

    final p = _prefs;
    if (p != null) {
      await p.setInt(_kMaxEvents, maxStoredEvents);
      await p.setInt(_kSnapshotSize, startupSnapshotSize);
      await p.setBool(_kAutoScroll, autoScroll);
      await p.setBool(_kLiveMonitoring, liveMonitoringEnabled);
      await p.setBool(_kCompact, compactMode);
      await p.setBool(_kAnimations, animationsEnabled);
      await p.setBool(_kDebugLogging, debugLogging);
      await p.setBool(_kWelcomeDone, welcomeCompleted);
      await p.setString(_kThemeMode, themeMode);
      await p.setString(_kAccentPreset, accentPreset);
      await p.setInt(_kCustomAccent, customAccentArgb);
      await p.setDouble(_kAnimationSpeed, animationSpeed);
      await p.setDouble(_kTextScale, textScale);
      await p.setString(
        _kHealthSectionsExpanded,
        jsonEncode(healthSectionExpanded),
      );
      await p.setString(
        _kDashboardWidgetOrder,
        jsonEncode(dashboardWidgetOrder),
      );
      await p.setString(
        _kDashboardHiddenWidgets,
        jsonEncode(dashboardHiddenWidgets.toList()..sort()),
      );
      await p.setString(_kDashboardDensity, dashboardDensity);
      await p.setBool(_kByteUnitBinary, byteUnitBinary);
      await p.setBool(_kTemperatureCelsius, temperatureCelsius);
      await p.setBool(_kClock24h, clock24h);
      await p.setString(_kPerformanceMode, performanceMode);
      await p.setBool(_kShowAdvancedDiagnostics, showAdvancedDiagnostics);
      await p.setString(_kExportDirectory, exportDirectory);
      await p.setBool(_kBackgroundMode, backgroundMode);
      await p.setBool(_kStartWithWindows, startWithWindows);
      await p.setBool(_kSystemNotifications, systemNotifications);
      await p.setBool(_kNotificationsPaused, notificationsPaused);
      await p.setInt(_kNotificationCooldownMinutes, notificationCooldownMinutes);
      if (assistantLocalAiProviderId == null) {
        await p.remove(_kAssistantLocalAiProvider);
      } else {
        await p.setString(
          _kAssistantLocalAiProvider,
          assistantLocalAiProviderId!,
        );
      }
      if (assistantLocalAiModelId == null) {
        await p.remove(_kAssistantLocalAiModel);
      } else {
        await p.setString(_kAssistantLocalAiModel, assistantLocalAiModelId!);
      }
    }
    notifyListeners();
  }

  /// Resolves the directory used for settings (and future) exports.
  Future<Directory> resolveExportDirectory() async {
    final custom = exportDirectory.trim();
    if (custom.isNotEmpty) {
      final dir = Directory(custom);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}Pulse',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> defaultSettingsExportPath() async {
    final dir = await resolveExportDirectory();
    return '${dir.path}${Platform.pathSeparator}$defaultSettingsExportFileName';
  }

  /// Writes current settings JSON to the export path and returns that path.
  Future<String> exportSettingsJson() async {
    final path = await defaultSettingsExportPath();
    final file = File(path);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(toMap()));
    logger.info('settings', 'Settings exported to $path');
    return path;
  }

  /// Reads settings JSON from [path] and applies it.
  Future<void> importSettingsJson(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Settings export not found', path);
    }
    final raw = await file.readAsString();
    await importSettingsFromJsonString(raw);
  }

  /// Restores settings from the last export at the default path.
  Future<void> importSettingsFromLastExport() async {
    final path = await defaultSettingsExportPath();
    await importSettingsJson(path);
  }

  Future<void> importSettingsFromJsonString(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Settings JSON must be an object');
    }
    await applyFromMap(Map<String, dynamic>.from(decoded));
  }

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

  static String _normalizePerformanceMode(String? value) {
    switch (value) {
      case 'balanced':
      case 'performance':
      case 'battery':
        return value!;
      default:
        return 'balanced';
    }
  }

  static Map<String, bool> _decodeHealthSections(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, bool>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is bool) {
          out[key] = value;
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static String _normalizeDashboardDensity(String? value) {
    switch (value) {
      case 'compact':
      case 'comfortable':
        return value!;
      default:
        return 'comfortable';
    }
  }

  static List<String> _normalizeDashboardOrder(List<String> order) {
    final seen = <String>{};
    final out = <String>[];
    for (final id in order) {
      if (_knownDashboardWidgets.contains(id) && seen.add(id)) {
        out.add(id);
      }
    }
    for (final id in defaultDashboardWidgetOrder) {
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  static Set<String> _normalizeDashboardHidden(Set<String> hidden) {
    return hidden.where(_knownDashboardWidgets.contains).toSet();
  }

  static List<String> _decodeDashboardOrder(String? raw) {
    if (raw == null || raw.isEmpty) {
      return List<String>.from(defaultDashboardWidgetOrder);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return List<String>.from(defaultDashboardWidgetOrder);
      }
      return _normalizeDashboardOrder(
        decoded.whereType<String>().toList(growable: false),
      );
    } catch (_) {
      return List<String>.from(defaultDashboardWidgetOrder);
    }
  }

  static Set<String> _decodeDashboardHidden(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      return _normalizeDashboardHidden(
        decoded.whereType<String>().toSet(),
      );
    } catch (_) {
      return {};
    }
  }
}
