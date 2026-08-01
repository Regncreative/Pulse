import 'package:pulse_protocol/pulse_wire.dart';

import 'timeline_display.dart';

enum TimelineRcaConfidence { high, medium, low }

/// Deterministic correlation rule (documented Event IDs only).
class TimelineCorrelationRule {
  const TimelineCorrelationRule({
    required this.id,
    required this.title,
    required this.steps,
    required this.windowMs,
    required this.possibleCause,
    required this.confidence,
    required this.nextStep,
    required this.falsePositiveNotes,
    this.singleton = false,
  });

  final String id;
  final String title;
  final List<TimelineCorrelationStep> steps;
  final int windowMs;
  final String possibleCause;
  final TimelineRcaConfidence confidence;
  final String nextStep;
  final String falsePositiveNotes;
  final bool singleton;
}

class TimelineCorrelationStep {
  const TimelineCorrelationStep({
    required this.providerContains,
    required this.winEventId,
  });

  final String providerContains;
  final int winEventId;
}

/// Root-cause hint backed by a matched [TimelineCorrelationRule].
class TimelineRcaHint {
  const TimelineRcaHint({
    required this.possibleCause,
    required this.confidence,
    required this.nextStep,
    required this.relatedEventIds,
    required this.ruleId,
  });

  final String possibleCause;
  final TimelineRcaConfidence confidence;
  final String nextStep;
  final List<String> relatedEventIds;
  final String ruleId;

  String get confidenceLabel => switch (confidence) {
        TimelineRcaConfidence.high => 'High',
        TimelineRcaConfidence.medium => 'Medium',
        TimelineRcaConfidence.low => 'Low',
      };
}

/// Collapsed incident row for the Timeline list.
class TimelineIncident {
  const TimelineIncident({
    required this.id,
    required this.title,
    required this.ruleId,
    required this.events,
    required this.rca,
  });

  final String id;
  final String title;
  final String ruleId;
  final List<TimelineEvent> events;
  final TimelineRcaHint rca;

  TimelineEvent get anchor => events.first;
  int get memberCount => events.length;
}

/// Flat list item: either a lone event or a collapsed incident.
sealed class TimelineListItem {
  const TimelineListItem();
}

class TimelineLoneEventItem extends TimelineListItem {
  const TimelineLoneEventItem(this.event);
  final TimelineEvent event;
}

class TimelineIncidentItem extends TimelineListItem {
  const TimelineIncidentItem(this.incident);
  final TimelineIncident incident;
}

/// Client-side deterministic incident builder. Never invents events.
class TimelineIncidentEngine {
  TimelineIncidentEngine({List<TimelineCorrelationRule>? rules})
      : rules = rules ?? documentedRules;

  final List<TimelineCorrelationRule> rules;

  /// Documented rules — keep in sync with docs/architecture/37-timeline-correlation-rules.md
  static const List<TimelineCorrelationRule> documentedRules = [
    TimelineCorrelationRule(
      id: 'app-crash-wer',
      title: 'Application crash reported',
      windowMs: 120 * 1000,
      steps: [
        TimelineCorrelationStep(
          providerContains: 'Application Error',
          winEventId: 1000,
        ),
        TimelineCorrelationStep(
          providerContains: 'Windows Error Reporting',
          winEventId: 1001,
        ),
      ],
      possibleCause:
          'An application faulted; Windows Error Reporting recorded a follow-up report.',
      confidence: TimelineRcaConfidence.high,
      nextStep:
          'Read the Faulting application / module fields in the Application Error message; open the matching WER report if present.',
      falsePositiveNotes:
          'Unrelated 1000/1001 pairs can coincide on busy machines; nearest-pair within the window is used.',
    ),
    TimelineCorrelationRule(
      id: 'unexpected-shutdown',
      title: 'Unexpected shutdown recorded',
      windowMs: 7 * 24 * 60 * 60 * 1000,
      steps: [
        TimelineCorrelationStep(
          providerContains: 'Kernel-Power',
          winEventId: 41,
        ),
        TimelineCorrelationStep(
          providerContains: 'EventLog',
          winEventId: 6008,
        ),
      ],
      possibleCause:
          'The system restarted without a clean shutdown; Kernel-Power 41 marks an unexpected reset, and EventLog 6008 records the prior unclean shutdown.',
      confidence: TimelineRcaConfidence.medium,
      nextStep:
          'Review Kernel-Power 41 details and recent Bugcheck / WER entries around the same time.',
      falsePositiveNotes:
          'Long window can pair unrelated cycles; nearest 6008 after 41 is preferred.',
    ),
    TimelineCorrelationRule(
      id: 'display-tdr-4101',
      title: 'Display driver reset (TDR)',
      windowMs: 0,
      singleton: true,
      steps: [
        TimelineCorrelationStep(
          providerContains: 'Display',
          winEventId: 4101,
        ),
      ],
      possibleCause:
          'Timeout Detection and Recovery reset the display driver after it stopped responding.',
      confidence: TimelineRcaConfidence.high,
      nextStep:
          'Note the driver name in the 4101 message; update or clean-install the GPU driver; check thermals / overclock.',
      falsePositiveNotes:
          'Singleton incident — does not invent DWM/recovery siblings without documented Event IDs in the loaded set.',
    ),
  ];

  /// Build list items from newest-first events. Consumed events appear only inside incidents.
  List<TimelineListItem> buildItems(List<TimelineEvent> newestFirst) {
    final remaining = List<TimelineEvent>.from(newestFirst);
    final items = <TimelineListItem>[];
    final consumed = <String>{};

    while (remaining.isNotEmpty) {
      final head = remaining.first;
      if (consumed.contains(head.eventId)) {
        remaining.removeAt(0);
        continue;
      }

      TimelineIncident? incident;
      for (final rule in rules) {
        incident = _tryMatch(rule, remaining, consumed);
        if (incident != null) break;
      }

      if (incident != null) {
        items.add(TimelineIncidentItem(incident));
        for (final e in incident.events) {
          consumed.add(e.eventId);
        }
        remaining.removeWhere((e) => consumed.contains(e.eventId));
      } else {
        items.add(TimelineLoneEventItem(head));
        consumed.add(head.eventId);
        remaining.removeAt(0);
      }
    }
    return items;
  }

  TimelineRcaHint? hintForEvent(
    TimelineEvent event,
    List<TimelineEvent> newestFirst,
  ) {
    final items = buildItems(newestFirst);
    for (final item in items) {
      if (item is TimelineIncidentItem &&
          item.incident.events.any((e) => e.eventId == event.eventId)) {
        return item.incident.rca;
      }
    }
    return null;
  }

  TimelineIncident? _tryMatch(
    TimelineCorrelationRule rule,
    List<TimelineEvent> remaining,
    Set<String> alreadyConsumed,
  ) {
    if (rule.singleton) {
      final e = remaining.first;
      if (alreadyConsumed.contains(e.eventId)) return null;
      if (!_matchesStep(e, rule.steps.first)) return null;
      return TimelineIncident(
        id: 'incident|${rule.id}|${e.eventId}',
        title: rule.title,
        ruleId: rule.id,
        events: [e],
        rca: TimelineRcaHint(
          possibleCause: rule.possibleCause,
          confidence: rule.confidence,
          nextStep: rule.nextStep,
          relatedEventIds: [e.eventId],
          ruleId: rule.id,
        ),
      );
    }

    if (rule.steps.length < 2) return null;

    final firstStep = rule.steps.first;
    final anchor = remaining.cast<TimelineEvent?>().firstWhere(
          (e) =>
              e != null &&
              !alreadyConsumed.contains(e.eventId) &&
              _matchesStep(e, firstStep),
          orElse: () => null,
        );
    if (anchor == null) return null;

    final members = <TimelineEvent>[anchor];
    var cursorTime = anchor.timestampUnixMs;

    for (var i = 1; i < rule.steps.length; i++) {
      final step = rule.steps[i];
      TimelineEvent? best;
      var bestDelta = 1 << 62;
      for (final e in remaining) {
        if (alreadyConsumed.contains(e.eventId)) continue;
        if (members.any((m) => m.eventId == e.eventId)) continue;
        if (!_matchesStep(e, step)) continue;
        if (anchor.timestampUnixMs <= 0 || e.timestampUnixMs <= 0) continue;
        // Prefer follow-up at or after the previous step (boot/WER typically later).
        final delta = e.timestampUnixMs - cursorTime;
        final absDelta = delta.abs();
        if (absDelta > rule.windowMs) continue;
        if (absDelta < bestDelta) {
          bestDelta = absDelta;
          best = e;
        }
      }
      if (best == null) return null;
      members.add(best);
      cursorTime = best.timestampUnixMs;
    }

    return TimelineIncident(
      id: 'incident|${rule.id}|${anchor.eventId}',
      title: rule.title,
      ruleId: rule.id,
      events: members,
      rca: TimelineRcaHint(
        possibleCause: rule.possibleCause,
        confidence: rule.confidence,
        nextStep: rule.nextStep,
        relatedEventIds: [for (final e in members) e.eventId],
        ruleId: rule.id,
      ),
    );
  }

  bool _matchesStep(TimelineEvent e, TimelineCorrelationStep step) {
    if (e.winEventId != step.winEventId) return false;
    final provider = e.providerName.toLowerCase();
    return provider.contains(step.providerContains.toLowerCase());
  }
}
