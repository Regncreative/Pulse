import 'package:flutter/foundation.dart';

import '../presentation/health/health_view_models.dart';

/// Cross-shell navigation into System Health detail panels (e.g. command palette).
class HealthNavigation extends ChangeNotifier {
  HealthPanelKind? _pendingPanel;
  bool _requestOverview = false;

  /// Panel requested by a global command; consumed by [SystemHealthPage].
  HealthPanelKind? get pendingPanel => _pendingPanel;

  /// When true, Health should show the overview (no detail panel).
  bool get requestOverview => _requestOverview;

  void openPanel(HealthPanelKind kind) {
    _pendingPanel = kind;
    _requestOverview = false;
    notifyListeners();
  }

  /// Request overview (no detail panel) — used by tray "System Health" / Dashboard.
  void clearPanel() {
    _pendingPanel = null;
    _requestOverview = true;
    notifyListeners();
  }

  /// Clears [pendingPanel] after the Health page has applied it.
  void consume() {
    if (_pendingPanel == null) return;
    _pendingPanel = null;
  }

  void consumeOverview() {
    _requestOverview = false;
  }
}
