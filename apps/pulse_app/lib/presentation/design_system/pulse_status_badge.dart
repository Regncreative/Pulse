import 'package:flutter/material.dart';

import '../components/pulse_badge.dart';

/// Status / tone badge — thin re-export of [PulseBadge] for the design system.
typedef PulseStatusBadge = PulseBadge;

/// Re-export tone enum alongside the badge typedef.
typedef PulseStatusBadgeTone = PulseBadgeTone;

/// Convenience constructor alias matching design-system naming.
PulseBadge pulseStatusBadge({
  Key? key,
  required String label,
  PulseBadgeTone tone = PulseBadgeTone.neutral,
  IconData? icon,
  Widget? iconWidget,
  bool compact = false,
}) {
  return PulseBadge(
    key: key,
    label: label,
    tone: tone,
    icon: icon,
    iconWidget: iconWidget,
    compact: compact,
  );
}
