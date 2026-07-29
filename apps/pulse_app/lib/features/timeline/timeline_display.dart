import 'package:flutter/material.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../app/theme/pulse_theme.dart';
import '../../presentation/components/pulse_badge.dart';

/// Display helpers for IPC [TimelineEvent] — no duplicated event model.
extension TimelineEventDisplay on TimelineEvent {
  String get displayTitle {
    if (title.isNotEmpty) return title;
    if (providerName.isNotEmpty) return providerName;
    return 'Windows Event';
  }

  String get displaySummary {
    if (summary.isNotEmpty) return summary;
    if (message.isNotEmpty) return message;
    return 'No message available.';
  }

  String get displayChannel => channel.isNotEmpty ? channel : 'System';

  String get relativeTimeLabel => formatRelativeTime(timestampUnixMs, timestampIso);

  String get absoluteTimeLabel {
    if (timestampUnixMs > 0) {
      final dt =
          DateTime.fromMillisecondsSinceEpoch(timestampUnixMs, isUtc: true)
              .toLocal();
      return _formatLocalDateTime(dt);
    }
    if (timestampIso.isNotEmpty) return timestampIso;
    return 'Unknown';
  }

  TimelineSeverityVisual get severityVisual =>
      TimelineSeverityVisual.fromWire(severity);

  String get importanceLabel => switch (importance) {
        Importance.critical => 'Critical',
        Importance.high => 'High',
        Importance.medium => 'Medium',
        _ => 'Low',
      };

  /// Card/detail guidance line — never invents "No recommendation available."
  String get actionGuidance {
    if (actionRequired) {
      return recommendation.trim().isNotEmpty
          ? recommendation.trim()
          : 'Action may be required.';
    }
    return 'No action required.';
  }

  bool get showRecommendationSection =>
      actionRequired && recommendation.trim().isNotEmpty;
}

String formatRelativeTime(int unixMs, String iso) {
  if (unixMs > 0) {
    final dt =
        DateTime.fromMillisecondsSinceEpoch(unixMs, isUtc: true).toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _formatLocalDateTime(dt);
  }
  if (iso.isNotEmpty) return iso;
  return 'Unknown time';
}

String _formatLocalDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}

class TimelineSeverityVisual {
  const TimelineSeverityVisual({
    required this.color,
    required this.soft,
    required this.label,
    required this.tone,
  });

  final Color color;
  final Color soft;
  final String label;
  final PulseBadgeTone tone;

  static TimelineSeverityVisual fromWire(int severity) {
    return switch (severity) {
      Severity.warning => const TimelineSeverityVisual(
          color: PulseTokens.severityWarning,
          soft: PulseTokens.warningSoft,
          label: 'Warning',
          tone: PulseBadgeTone.warning,
        ),
      Severity.error => const TimelineSeverityVisual(
          color: PulseTokens.severityError,
          soft: PulseTokens.errorSoft,
          label: 'Error',
          tone: PulseBadgeTone.error,
        ),
      Severity.critical => const TimelineSeverityVisual(
          color: PulseTokens.severityCritical,
          soft: PulseTokens.errorSoft,
          label: 'Critical',
          tone: PulseBadgeTone.error,
        ),
      Severity.verbose => const TimelineSeverityVisual(
          color: PulseTokens.textTertiary,
          soft: PulseTokens.surface,
          label: 'Verbose',
          tone: PulseBadgeTone.neutral,
        ),
      Severity.info => const TimelineSeverityVisual(
          color: PulseTokens.severityInfo,
          soft: PulseTokens.infoSoft,
          label: 'Info',
          tone: PulseBadgeTone.info,
        ),
      _ => const TimelineSeverityVisual(
          color: PulseTokens.textSecondary,
          soft: PulseTokens.surface,
          label: 'Unknown',
          tone: PulseBadgeTone.neutral,
        ),
    };
  }
}
