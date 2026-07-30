import 'dart:convert';

import 'package:pulse_protocol/pulse_wire.dart';

import 'timeline_display.dart';

/// JSON export helpers for Timeline (local-only, no network).
abstract final class TimelineExport {
  static Map<String, dynamic> eventToJson(TimelineEvent e) {
    return {
      'event_id': e.eventId,
      'timestamp_unix_ms': e.timestampUnixMs,
      'timestamp_iso': e.timestampIso,
      'severity': _severityName(e.severity),
      'channel': e.displayChannel,
      'provider_name': e.providerName,
      'win_event_id': e.winEventId,
      'record_id': e.recordId,
      'computer_name': e.computerName,
      'title': e.displayTitle,
      'summary': e.displaySummary,
      'technical_summary': e.technicalSummary,
      'message': e.message,
      'recommendation': e.recommendation,
      'action_required': e.actionRequired,
      'importance': e.importance,
      'category': e.category,
    };
  }

  static String encodeEvents(List<TimelineEvent> events, {String? note}) {
    final payload = <String, dynamic>{
      'pulse_export': 'timeline_events',
      'version': 1,
      'exported_at_unix_ms': DateTime.now().millisecondsSinceEpoch,
      'count': events.length,
      if (note != null && note.isNotEmpty) 'note': note,
      'events': [for (final e in events) eventToJson(e)],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static String _severityName(int severity) {
    return switch (severity) {
      Severity.critical => 'critical',
      Severity.error => 'error',
      Severity.warning => 'warning',
      Severity.info => 'info',
      Severity.verbose => 'verbose',
      _ => 'unknown',
    };
  }
}
