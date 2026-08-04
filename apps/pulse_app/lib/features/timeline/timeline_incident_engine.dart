import 'package:pulse_protocol/pulse_wire.dart';

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
      id: 'service-crash-recover',
      title: 'Service crash and recovery',
      windowMs: 180 * 1000,
      steps: [
        TimelineCorrelationStep(
          providerContains: 'Service Control Manager',
          winEventId: 7031,
        ),
        TimelineCorrelationStep(
          providerContains: 'Service Control Manager',
          winEventId: 7036,
        ),
      ],
      possibleCause:
          'A Windows service terminated unexpectedly and later reported a state change (often a recovery restart).',
      confidence: TimelineRcaConfidence.medium,
      nextStep:
          'Confirm the service name in both events. Investigate repeated 7031 crashes for the same service.',
      falsePositiveNotes:
          'Any 7036 after a 7031 within the window may pair unrelated services; prefer reviewing message text.',
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
  ///
  /// Two-pass: (1) greedily form incidents from rule step-0 anchors, (2) emit in
  /// list order so newer follow-ups are not prematurely flattened as lone rows.
  /// Complexity: O(n · R · C) with C = candidates for a follow-up Event ID.
  List<TimelineListItem> buildItems(List<TimelineEvent> newestFirst) {
    final consumed = <String>{};
    final incidentByMemberId = <String, TimelineIncident>{};
    final byEventId = <int, List<TimelineEvent>>{};
    for (final e in newestFirst) {
      byEventId.putIfAbsent(e.winEventId, () => <TimelineEvent>[]).add(e);
    }

    for (final head in newestFirst) {
      if (consumed.contains(head.eventId)) continue;
      for (final rule in rules) {
        final incident = _tryMatchFromHead(rule, head, byEventId, consumed);
        if (incident == null) continue;
        for (final e in incident.events) {
          consumed.add(e.eventId);
          incidentByMemberId[e.eventId] = incident;
        }
        break;
      }
    }

    final items = <TimelineListItem>[];
    final emittedIncidents = <String>{};
    for (final e in newestFirst) {
      final incident = incidentByMemberId[e.eventId];
      if (incident != null) {
        if (emittedIncidents.add(incident.id)) {
          items.add(TimelineIncidentItem(incident));
        }
        continue;
      }
      items.add(TimelineLoneEventItem(e));
    }
    return items;
  }

  /// RCA for [event] if it belongs to a matched incident in [items].
  TimelineRcaHint? hintFromItems(
    TimelineEvent event,
    List<TimelineListItem> items,
  ) {
    for (final item in items) {
      if (item is TimelineIncidentItem &&
          item.incident.events.any((e) => e.eventId == event.eventId)) {
        return item.incident.rca;
      }
    }
    return null;
  }

  TimelineRcaHint? hintForEvent(
    TimelineEvent event,
    List<TimelineEvent> newestFirst,
  ) {
    return hintFromItems(event, buildItems(newestFirst));
  }

  TimelineIncident? _tryMatchFromHead(
    TimelineCorrelationRule rule,
    TimelineEvent head,
    Map<int, List<TimelineEvent>> byEventId,
    Set<String> alreadyConsumed,
  ) {
    if (rule.steps.isEmpty) return null;
    if (!_matchesStep(head, rule.steps.first)) return null;

    if (rule.singleton) {
      return TimelineIncident(
        id: 'incident|${rule.id}|${head.eventId}',
        title: rule.title,
        ruleId: rule.id,
        events: [head],
        rca: TimelineRcaHint(
          possibleCause: rule.possibleCause,
          confidence: rule.confidence,
          nextStep: rule.nextStep,
          relatedEventIds: [head.eventId],
          ruleId: rule.id,
        ),
      );
    }

    if (rule.steps.length < 2) return null;

    final members = <TimelineEvent>[head];
    var cursorTime = head.timestampUnixMs;

    for (var i = 1; i < rule.steps.length; i++) {
      final step = rule.steps[i];
      final candidates = byEventId[step.winEventId];
      if (candidates == null || candidates.isEmpty) return null;

      TimelineEvent? best;
      var bestDelta = 1 << 62;
      for (final e in candidates) {
        if (alreadyConsumed.contains(e.eventId)) continue;
        if (members.any((m) => m.eventId == e.eventId)) continue;
        if (!_matchesStep(e, step)) continue;
        if (head.timestampUnixMs <= 0 || e.timestampUnixMs <= 0) continue;
        final absDelta = (e.timestampUnixMs - cursorTime).abs();
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
      id: 'incident|${rule.id}|${head.eventId}',
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
