import 'package:flutter/material.dart';

import 'health_view_models.dart';

/// System Health utilization semantics — independent of global Accent Color.
///
/// Only for percentage-based System Health charts/progress.
abstract final class HealthUtilizationColors {
  static const Color low = Color(0xFF3D9A6E); // 0–49% green
  static const Color medium = Color(0xFFD4A017); // 50–69% yellow
  static const Color high = Color(0xFFE67E22); // 70–89% orange
  static const Color critical = Color(0xFFD64545); // 90–100% red

  /// Neutral chart color for non-percentage metrics (disk MB/s, network Mbps).
  /// Not tied to global accent.
  static const Color neutral = Color(0xFF7A8799);

  /// Map a 0–100 utilization percentage to a diagnostic color.
  static Color forPercent(double percent) {
    final p = percent.isFinite ? percent : 0.0;
    if (p >= 90) return critical;
    if (p >= 70) return high;
    if (p >= 50) return medium;
    return low;
  }
}

/// Chart color for a [HealthMetric] using latest utilization when percentage-based.
Color healthMetricChartColor(HealthMetric metric) {
  if (metric.unit == '%') {
    final latest = metric.sparkline.isNotEmpty
        ? metric.sparkline.last
        : double.tryParse(metric.value) ?? 0;
    return HealthUtilizationColors.forPercent(latest);
  }
  if (metric.progress != null) {
    return HealthUtilizationColors.forPercent(metric.progress! * 100.0);
  }
  return HealthUtilizationColors.neutral;
}
