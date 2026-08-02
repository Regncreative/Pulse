import 'package:pulse_protocol/pulse_wire.dart';

import 'timeline_display.dart';
import 'timeline_query.dart';

/// True when the retained session already contains at least one Security-channel event.
///
/// Used to distinguish "Security unavailable under LocalService" from an empty
/// filter result. Pulse does not invent Security availability.
bool sessionContainsSecurityChannelEvents(Iterable<TimelineEvent> events) {
  for (final e in events) {
    if (e.displayChannel.toLowerCase() == 'security') return true;
  }
  return false;
}

/// Timeline empty-state copy for list / filtered views.
String timelineEmptyMessage({
  required bool hasSessionEvents,
  required bool filtersActive,
  required TimelineQuery query,
  required bool sessionHasSecurityChannelEvents,
  required bool mock,
}) {
  final securitySource = query.source == TimelineSourceFilter.security;
  if (securitySource && !sessionHasSecurityChannelEvents) {
    return 'Security log is unavailable because PulseService runs as LocalService.\n\n'
        'Windows often denies LocalService read access to the Security Event Log. '
        'Pulse skips the channel and does not fake Security events. '
        'Other diagnostics channels continue normally.';
  }

  if (!hasSessionEvents) {
    return mock
        ? 'No sample events are loaded. Rebuild with PULSE_MOCK_TIMELINE or connect PulseService.'
        : 'Pulse is connected and listening across diagnostics Event Log channels.\n\n'
            'New events appear here as Windows works. Use Refresh if you expect a historical snapshot.';
  }
  if (filtersActive) {
    return 'No events match the current search and filters.\n\n'
        'Clear filters or try a different severity, source, category, provider, or date range.';
  }
  return 'Nothing to show in this view.';
}
