import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/timeline/timeline_incident_engine.dart';
import 'package:pulse/features/timeline/timeline_query.dart';
import 'package:pulse_protocol/pulse_wire.dart';

/// Synthetic load for Timeline Intelligence performance gates (R2).
List<TimelineEvent> _synthetic(int count) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return [
    for (var i = 0; i < count; i++)
      TimelineEvent(
        eventId: 'synth|$i|${1000 + (i % 50)}',
        timestampUnixMs: now - i * 1000,
        timestampIso: '2026-08-01T00:00:00Z',
        severity: i % 7 == 0 ? Severity.error : Severity.info,
        channel: i % 2 == 0 ? 'System' : 'Application',
        providerName: i % 11 == 0
            ? 'Application Error'
            : (i % 13 == 0
                ? 'Windows Error Reporting'
                : 'Service Control Manager'),
        winEventId: i % 11 == 0
            ? 1000
            : (i % 13 == 0 ? 1001 : 7036),
        recordId: i,
        computerName: 'DESKTOP',
        title: 'Synthetic $i',
        summary: 'Synthetic event $i for Timeline load testing',
        message: 'Message body $i notepad.exe pid=${1000 + i}',
        category: i % 5 == 0 ? 'Crash' : 'Service',
        hasProcessId: i % 3 == 0,
        processId: 1000 + (i % 500),
        processName: i % 3 == 0 ? 'app.exe' : '',
      ),
  ];
}

void main() {
  test('TimelineQuery filters 100k events under budget', () {
    final events = _synthetic(100000);
    const q = TimelineQuery(
      severity: TimelineSeverityFilter.errors,
      searchQuery: 'notepad',
    );
    final sw = Stopwatch()..start();
    final matched = [for (final e in events) if (q.matches(e)) e];
    sw.stop();
    expect(matched, isNotEmpty);
    // Local-first gate: full scan of 100k should stay interactive on CI hosts.
    expect(sw.elapsedMilliseconds, lessThan(2500));
  });

  test('Incident engine builds items for 100k under budget', () {
    final events = _synthetic(100000);
    final engine = TimelineIncidentEngine();
    final sw = Stopwatch()..start();
    final items = engine.buildItems(events);
    sw.stop();
    // Synthetic mix yields many app-crash pairs + display singletons + flat rows.
    expect(items.length, greaterThan(1000));
    expect(items.length, lessThanOrEqualTo(100000));
    // Hosted CI runners are slower than local workstations; keep a generous
    // but finite gate so regressions still fail.
    expect(sw.elapsedMilliseconds, lessThan(15000),
        reason: 'took ${sw.elapsedMilliseconds}ms');
  });

  test('Virtualized list identity keys are stable for 100k', () {
    final events = _synthetic(100000);
    final keys = {for (final e in events) e.eventId};
    expect(keys.length, 100000);
  });
}
