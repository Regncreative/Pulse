import 'dart:convert';

import 'package:pulse_protocol/pulse_wire.dart';

import '../../application/timeline_library_controller.dart';
import 'timeline_display.dart';
import 'timeline_query.dart';

/// JSON + CSV export helpers for Timeline (local-only, no network).
abstract final class TimelineExport {
  static const List<String> csvColumns = [
    'event_id',
    'timestamp_unix_ms',
    'timestamp_iso',
    'severity',
    'channel',
    'provider_name',
    'win_event_id',
    'record_id',
    'computer_name',
    'title',
    'summary',
    'technical_summary',
    'message',
    'recommendation',
    'action_required',
    'importance',
    'category',
    'task',
    'opcode',
    'keywords',
    'process_id',
    'process_name',
    'thread_id',
    'user_sid',
    'activity_id',
    'related_activity_id',
    'level_name',
    'bookmarked',
    'pinned',
    'incident_id',
    'incident_title',
    'correlation_rule_id',
  ];

  static Map<String, dynamic> eventToJson(
    TimelineEvent e, {
    bool bookmarked = false,
    bool pinned = false,
    String? incidentId,
    String? incidentTitle,
    String? correlationRuleId,
  }) {
    return {
      'event_id': e.eventId,
      'timestamp_unix_ms': e.timestampUnixMs,
      'timestamp_iso': e.timestampIso,
      'severity': severityName(e.severity),
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
      if (e.hasTask) 'task': e.task,
      if (e.hasOpcode) 'opcode': e.opcode,
      if (e.hasKeywords) 'keywords': e.keywords.toUnsigned(64).toString(),
      if (e.hasProcessId) 'process_id': e.processId,
      if (e.processName.isNotEmpty) 'process_name': e.processName,
      if (e.hasThreadId) 'thread_id': e.threadId,
      if (e.userSid.isNotEmpty) 'user_sid': e.userSid,
      if (e.activityId.isNotEmpty) 'activity_id': e.activityId,
      if (e.relatedActivityId.isNotEmpty)
        'related_activity_id': e.relatedActivityId,
      if (e.levelName.isNotEmpty) 'level_name': e.levelName,
      if (e.rawXml.isNotEmpty) 'raw_xml': e.rawXml,
      'bookmarked': bookmarked,
      'pinned': pinned,
      if (incidentId != null && incidentId.isNotEmpty) 'incident_id': incidentId,
      if (incidentTitle != null && incidentTitle.isNotEmpty)
        'incident_title': incidentTitle,
      if (correlationRuleId != null && correlationRuleId.isNotEmpty)
        'correlation_rule_id': correlationRuleId,
    };
  }

  static String encodeEvents(
    List<TimelineEvent> events, {
    String? note,
    TimelineQuery? appliedFilters,
    Set<String>? bookmarkedEventIds,
    Set<String>? pinnedEventIds,
    Map<String, TimelineIncidentMeta>? incidentByEventId,
  }) {
    final bookmarks = bookmarkedEventIds ?? const <String>{};
    final pins = pinnedEventIds ?? const <String>{};
    final incidents = incidentByEventId ?? const <String, TimelineIncidentMeta>{};
    final payload = <String, dynamic>{
      'pulse_export': 'timeline_events',
      'version': 2,
      'exported_at_unix_ms': DateTime.now().millisecondsSinceEpoch,
      'count': events.length,
      if (note != null && note.isNotEmpty) 'note': note,
      if (appliedFilters != null)
        'applied_filters': timelineQueryToJson(appliedFilters),
      'events': [
        for (final e in events)
          eventToJson(
            e,
            bookmarked: bookmarks.contains(e.eventId),
            pinned: pins.contains(e.eventId),
            incidentId: incidents[e.eventId]?.incidentId,
            incidentTitle: incidents[e.eventId]?.title,
            correlationRuleId: incidents[e.eventId]?.ruleId,
          ),
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// CSV with header row. Applied filters are written as `#` comment lines.
  static String encodeCsv(
    List<TimelineEvent> events, {
    TimelineQuery? appliedFilters,
    Set<String>? bookmarkedEventIds,
    Set<String>? pinnedEventIds,
    Map<String, TimelineIncidentMeta>? incidentByEventId,
  }) {
    final bookmarks = bookmarkedEventIds ?? const <String>{};
    final pins = pinnedEventIds ?? const <String>{};
    final incidents = incidentByEventId ?? const <String, TimelineIncidentMeta>{};
    final buf = StringBuffer();
    buf.writeln('# pulse_export=timeline_events');
    buf.writeln('# version=2');
    buf.writeln('# exported_at_unix_ms=${DateTime.now().millisecondsSinceEpoch}');
    buf.writeln('# count=${events.length}');
    if (appliedFilters != null) {
      final filters = timelineQueryToJson(appliedFilters);
      for (final entry in filters.entries) {
        buf.writeln('# filter_${entry.key}=${entry.value}');
      }
    }
    buf.writeln(csvColumns.join(','));
    for (final e in events) {
      final meta = incidents[e.eventId];
      buf.writeln(
        [
          csvCell(e.eventId),
          csvCell(e.timestampUnixMs.toString()),
          csvCell(e.timestampIso),
          csvCell(severityName(e.severity)),
          csvCell(e.displayChannel),
          csvCell(e.providerName),
          csvCell(e.winEventId.toString()),
          csvCell(e.recordId.toString()),
          csvCell(e.computerName),
          csvCell(e.displayTitle),
          csvCell(e.displaySummary),
          csvCell(e.technicalSummary),
          csvCell(e.message),
          csvCell(e.recommendation),
          csvCell(e.actionRequired.toString()),
          csvCell(e.importance.toString()),
          csvCell(e.category),
          csvCell(e.hasTask ? e.task.toString() : ''),
          csvCell(e.hasOpcode ? e.opcode.toString() : ''),
          csvCell(
            e.hasKeywords ? e.keywords.toUnsigned(64).toString() : '',
          ),
          csvCell(e.hasProcessId ? e.processId.toString() : ''),
          csvCell(e.processName),
          csvCell(e.hasThreadId ? e.threadId.toString() : ''),
          csvCell(e.userSid),
          csvCell(e.activityId),
          csvCell(e.relatedActivityId),
          csvCell(e.levelName),
          csvCell(bookmarks.contains(e.eventId).toString()),
          csvCell(pins.contains(e.eventId).toString()),
          csvCell(meta?.incidentId ?? ''),
          csvCell(meta?.title ?? ''),
          csvCell(meta?.ruleId ?? ''),
        ].join(','),
      );
    }
    return buf.toString();
  }

  static String csvCell(String value) {
    final needsQuote = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuote) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  static String severityName(int severity) {
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

/// Compact incident membership for export (no fabricated fields).
class TimelineIncidentMeta {
  const TimelineIncidentMeta({
    required this.incidentId,
    required this.title,
    required this.ruleId,
  });

  final String incidentId;
  final String title;
  final String ruleId;
}
