import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/timeline/timeline_export.dart';
import 'package:pulse/features/timeline/timeline_query.dart';
import 'package:pulse_protocol/pulse_wire.dart';

void main() {
  final event = TimelineEvent(
    eventId: 'e1',
    title: 'Test',
    summary: 'Hello',
    severity: Severity.warning,
    channel: 'System',
    winEventId: 1000,
    providerName: 'Application Error',
    hasProcessId: true,
    processId: 42,
    processName: 'app.exe',
  );

  test('TimelineExport encodes selected event as JSON v2', () {
    final json = TimelineExport.encodeEvents(
      [event],
      note: 'selected_event',
      appliedFilters: const TimelineQuery(
        searchQuery: 'app',
        eventIdEquals: '1000',
      ),
      bookmarkedEventIds: {'e1'},
      pinnedEventIds: {'e1'},
      incidentByEventId: {
        'e1': const TimelineIncidentMeta(
          incidentId: 'incident|app-crash-wer|e1',
          title: 'Application crash reported',
          ruleId: 'app-crash-wer',
        ),
      },
    );
    expect(json, contains('"pulse_export": "timeline_events"'));
    expect(json, contains('"version": 2'));
    expect(json, contains('"count": 1'));
    expect(json, contains('selected_event'));
    expect(json, contains('"bookmarked": true'));
    expect(json, contains('"pinned": true'));
    expect(json, contains('app-crash-wer'));
    expect(json, contains('"applied_filters"'));
  });

  test('TimelineExport encodes CSV with filters and marks', () {
    final csv = TimelineExport.encodeCsv(
      [event],
      appliedFilters: const TimelineQuery(providerContains: 'Application'),
      bookmarkedEventIds: {'e1'},
      pinnedEventIds: const {},
      incidentByEventId: {
        'e1': const TimelineIncidentMeta(
          incidentId: 'inc-1',
          title: 'Application crash reported',
          ruleId: 'app-crash-wer',
        ),
      },
    );
    expect(csv, contains('# pulse_export=timeline_events'));
    expect(csv, contains('# filter_provider_contains=Application'));
    expect(csv, contains(TimelineExport.csvColumns.join(',')));
    expect(csv, contains('e1'));
    expect(csv, contains('true')); // bookmarked
    expect(csv, contains('app-crash-wer'));
    expect(csv, contains('app.exe'));
  });

  test('csvCell quotes commas and quotes', () {
    expect(TimelineExport.csvCell('a,b'), '"a,b"');
    expect(TimelineExport.csvCell('say "hi"'), '"say ""hi"""');
    expect(TimelineExport.csvCell('plain'), 'plain');
  });
}
