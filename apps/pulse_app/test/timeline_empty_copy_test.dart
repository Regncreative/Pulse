import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/timeline/timeline_empty_copy.dart';
import 'package:pulse/features/timeline/timeline_query.dart';
import 'package:pulse_protocol/pulse_wire.dart';

TimelineEvent _ev({String channel = 'System'}) {
  return TimelineEvent(
    eventId: '$channel|1',
    severity: Severity.info,
    channel: channel,
    category: 'Service',
    providerName: 'Test',
    winEventId: 1,
    computerName: 'PC',
    message: 'msg',
    title: 'Title',
    summary: 'Summary',
    processName: '',
    hasProcessId: false,
    processId: 0,
    timestampUnixMs: 1_700_000_000_000,
    rawXml: '',
  );
}

void main() {
  group('timelineEmptyMessage', () {
    test('Security source with no Security events explains LocalService ACL', () {
      final msg = timelineEmptyMessage(
        hasSessionEvents: true,
        filtersActive: true,
        query: const TimelineQuery(source: TimelineSourceFilter.security),
        sessionHasSecurityChannelEvents: false,
        mock: false,
      );
      expect(msg, contains('Security log is unavailable'));
      expect(msg, contains('LocalService'));
      expect(msg, isNot(contains('No events match')));
    });

    test('Security source with Security events uses filter-empty copy', () {
      final msg = timelineEmptyMessage(
        hasSessionEvents: true,
        filtersActive: true,
        query: const TimelineQuery(source: TimelineSourceFilter.security),
        sessionHasSecurityChannelEvents: true,
        mock: false,
      );
      expect(msg, contains('No events match'));
      expect(msg, isNot(contains('LocalService')));
    });

    test('non-Security empty session uses listening copy', () {
      final msg = timelineEmptyMessage(
        hasSessionEvents: false,
        filtersActive: false,
        query: const TimelineQuery(),
        sessionHasSecurityChannelEvents: false,
        mock: false,
      );
      expect(msg, contains('listening across diagnostics'));
    });
  });

  group('sessionContainsSecurityChannelEvents', () {
    test('detects Security channel case-insensitively', () {
      expect(
        sessionContainsSecurityChannelEvents([_ev(channel: 'Security')]),
        isTrue,
      );
      expect(
        sessionContainsSecurityChannelEvents([_ev(channel: 'System')]),
        isFalse,
      );
    });
  });
}
