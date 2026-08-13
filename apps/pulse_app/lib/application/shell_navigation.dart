import 'package:flutter/foundation.dart';

import '../presentation/health/health_view_models.dart';
import '../presentation/settings/settings_category.dart';
import '../presentation/shell/app_shell.dart';
import 'alert_state_engine.dart';

/// Cross-cutting shell navigation used by tray menu and notification clicks.
class ShellNavigation extends ChangeNotifier {
  int? _pendingShellPage;
  HealthPanelKind? _pendingHealthPanel;
  bool _clearHealthPanel = false;
  SettingsCategoryId? _pendingSettingsCategory;

  int? get pendingShellPage => _pendingShellPage;
  HealthPanelKind? get pendingHealthPanel => _pendingHealthPanel;
  bool get clearHealthPanel => _clearHealthPanel;
  SettingsCategoryId? get pendingSettingsCategory => _pendingSettingsCategory;

  void open(PulseNavTarget target) {
    switch (target) {
      case PulseNavTarget.open:
      case PulseNavTarget.dashboard:
      case PulseNavTarget.systemHealth:
        _pendingShellPage = PulseShellPages.health;
        _pendingHealthPanel = null;
        _clearHealthPanel = true;
        _pendingSettingsCategory = null;
      case PulseNavTarget.processes:
        _pendingShellPage = PulseShellPages.health;
        _pendingHealthPanel = HealthPanelKind.cpu;
        _clearHealthPanel = false;
        _pendingSettingsCategory = null;
      case PulseNavTarget.hardware:
        _pendingShellPage = PulseShellPages.health;
        _pendingHealthPanel = HealthPanelKind.hardware;
        _clearHealthPanel = false;
        _pendingSettingsCategory = null;
      case PulseNavTarget.storage:
        _pendingShellPage = PulseShellPages.health;
        _pendingHealthPanel = HealthPanelKind.disk;
        _clearHealthPanel = false;
        _pendingSettingsCategory = null;
      case PulseNavTarget.network:
        _pendingShellPage = PulseShellPages.health;
        _pendingHealthPanel = HealthPanelKind.network;
        _clearHealthPanel = false;
        _pendingSettingsCategory = null;
      case PulseNavTarget.eventLogs:
        _pendingShellPage = PulseShellPages.timeline;
        _pendingHealthPanel = null;
        _clearHealthPanel = false;
        _pendingSettingsCategory = null;
      case PulseNavTarget.settings:
        _pendingShellPage = PulseShellPages.settings;
        _pendingHealthPanel = null;
        _clearHealthPanel = false;
        _pendingSettingsCategory = null;
      case PulseNavTarget.aiIntegrationSettings:
        openAiIntegrationSettings();
        return;
    }
    notifyListeners();
  }

  /// Opens Settings → AI Integration (MCP client registration).
  void openAiIntegrationSettings() {
    _pendingShellPage = PulseShellPages.settings;
    _pendingHealthPanel = null;
    _clearHealthPanel = false;
    _pendingSettingsCategory = SettingsCategoryId.aiIntegration;
    notifyListeners();
  }

  void openForAlert(AlertKind kind) {
    switch (kind) {
      case AlertKind.cpu:
        open(PulseNavTarget.processes);
      case AlertKind.memory:
        _pendingShellPage = PulseShellPages.health;
        _pendingHealthPanel = HealthPanelKind.memory;
        _clearHealthPanel = false;
        _pendingSettingsCategory = null;
        notifyListeners();
      case AlertKind.systemHealth:
        open(PulseNavTarget.dashboard);
      case AlertKind.eventLog:
        open(PulseNavTarget.eventLogs);
    }
  }

  void consume() {
    _pendingShellPage = null;
    _pendingHealthPanel = null;
    _clearHealthPanel = false;
  }

  /// Clears settings deep-link after [SettingsPage] applies it.
  void consumeSettingsCategory() {
    _pendingSettingsCategory = null;
  }
}

/// Target page (and optional Health panel) for tray / notification deep links.
enum PulseNavTarget {
  open,
  dashboard,
  systemHealth,
  processes,
  hardware,
  storage,
  network,
  eventLogs,
  settings,
  aiIntegrationSettings,
}
