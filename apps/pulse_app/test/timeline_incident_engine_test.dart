import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/timeline/timeline_incident_engine.dart';
import 'package:pulse_protocol/pulse_wire.dart';

TimelineEvent _ev({
  required String id,
  required String provider,
  required int winEventId,
  required int ts,
}) {
  return TimelineEvent(
    eventId: id,
    providerName: provider,
    winEventId: winEventId,
    timestampUnixMs: ts,
    channel: 'Application',
    title: provider,
    summary: 'summary',
  );
}

void main() {
  group('TimelineIncidentEngine', () {
    test('pairs Application Error 1000 with WER 1001', () {
      final events = [
        _ev(
          id: 'a',
          provider: 'Windows Error Reporting',
          winEventId: 1001,
          ts: 2_000,
        ),
        _ev(
          id: 'b',
          provider: 'Application Error',
          winEventId: 1000,
          ts: 1_000,
        ),
      ];
      final items = TimelineIncidentEngine().buildItems(events);
      expect(items, hasLength(1));
      final incident = (items.first as TimelineIncidentItem).incident;
      expect(incident.ruleId, 'app-crash-wer');
      expect(incident.memberCount, 2);
      expect(incident.rca.confidence, TimelineRcaConfidence.high);
    });

    test('does not invent pairs outside window', () {
      final events = [
        _ev(
          id: 'a',
          provider: 'Windows Error Reporting',
          winEventId: 1001,
          ts: 1_000_000,
        ),
        _ev(
          id: 'b',
          provider: 'Application Error',
          winEventId: 1000,
          ts: 1_000,
        ),
      ];
      final items = TimelineIncidentEngine().buildItems(events);
      expect(items.whereType<TimelineLoneEventItem>(), hasLength(2));
    });

    test('display 4101 becomes singleton incident', () {
      final events = [
        _ev(
          id: 'd',
          provider: 'Display',
          winEventId: 4101,
          ts: 5_000,
        ),
      ];
      final items = TimelineIncidentEngine().buildItems(events);
      expect(items, hasLength(1));
      final incident = (items.first as TimelineIncidentItem).incident;
      expect(incident.ruleId, 'display-tdr-4101');
      expect(incident.memberCount, 1);
    });

    test('unrelated events stay flat', () {
      final events = [
        _ev(
          id: 's',
          provider: 'Service Control Manager',
          winEventId: 7036,
          ts: 9_000,
        ),
      ];
      final items = TimelineIncidentEngine().buildItems(events);
      expect(items.single, isA<TimelineLoneEventItem>());
    });
  });
}
