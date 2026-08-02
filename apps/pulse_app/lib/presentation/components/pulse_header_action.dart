import 'package:flutter/material.dart';

/// Declarative app-bar action used by [PulseAppBar] for overflow-safe layout.
class PulseHeaderAction {
  const PulseHeaderAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.collapseFirst = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// In the mid-width band (≈1200–1400), drop this action’s label first
  /// (e.g. Copy becomes icon-only while Export/Refresh keep text).
  final bool collapseFirst;
}
