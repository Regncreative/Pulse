import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/timeline/timeline_export.dart';
import 'package:pulse_protocol/pulse_wire.dart';

void main() {
  test('TimelineExport encodes selected event as JSON', () {
    final event = TimelineEvent(
      eventId: 'e1',
      title: 'Test',
      summary: 'Hello',
      severity: Severity.warning,
      channel: 'System',
      winEventId: 1000,
    );
    final json = TimelineExport.encodeEvents([event], note: 'selected_event');
    expect(json, contains('"pulse_export": "timeline_events"'));
    expect(json, contains('"count": 1'));
    expect(json, contains('selected_event'));
    expect(json, contains('Test'));
    expect(json, contains('warning'));
  });
}
