import 'package:flutter/foundation.dart';

import '../presentation/health/health_view_models.dart';

/// Cross-shell navigation into System Health detail panels (e.g. command palette).
class HealthNavigation extends ChangeNotifier {
  HealthPanelKind? _pendingPanel;

  /// Panel requested by a global command; consumed by [SystemHealthPage].
  HealthPanelKind? get pendingPanel => _pendingPanel;

  void openPanel(HealthPanelKind kind) {
    _pendingPanel = kind;
    notifyListeners();
  }

  /// Clears [pendingPanel] after the Health page has applied it.
  void consume() {
    if (_pendingPanel == null) return;
    _pendingPanel = null;
  }
}
