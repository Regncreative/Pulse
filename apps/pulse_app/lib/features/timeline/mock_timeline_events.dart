import 'package:pulse_protocol/pulse_wire.dart';

/// Returns a fresh copy of the development mock snapshot
/// (same wire model as IPC, gated behind PULSE_MOCK_TIMELINE).
List<TimelineEvent> mockTimelineEvents() =>
    List<TimelineEvent>.from(kMockTimelineEvents);

/// Development mock snapshot — same wire model as IPC (PULSE_MOCK_TIMELINE).
final kMockTimelineEvents = <TimelineEvent>[
  TimelineEvent(
    eventId: 'mock|1|10016',
    timestampUnixMs: DateTime.now()
        .subtract(const Duration(seconds: 20))
        .millisecondsSinceEpoch,
    timestampIso: DateTime.now().toUtc().toIso8601String(),
    severity: Severity.warning,
    channel: 'System',
    providerName: 'Microsoft-Windows-DistributedCOM',
    winEventId: 10016,
    recordId: 1,
    computerName: 'DESKTOP',
    title: 'COM Permission Warning',
    summary:
        'An application attempted to access a COM component without sufficient permissions.',
    recommendation:
        'Usually harmless unless an application is failing to start.',
    actionRequired: false,
    importance: Importance.low,
    category: 'COM',
    technicalSummary:
        'Microsoft-Windows-DistributedCOM Event ID 10016 · System · COM',
    message:
        'The application-specific permission settings do not grant Local Activation '
        'permission for the COM Server application with CLSID\n'
        '{D63B10C5-BB46-4990-A94F-E40B9D520160}\n'
        'and APPID\n'
        '{5152791C-AAE0-4007-8E2D-948D5BB704B7}\n'
        'to the user NT AUTHORITY\\LOCAL SERVICE SID (S-1-5-19) from address '
        'LocalHost (Using LRPC) running in the application container Unavailable SID '
        '(Unavailable). This security permission can be modified using the Component '
        'Services administrative tool.',
  ),
  TimelineEvent(
    eventId: 'mock|2|0',
    timestampUnixMs: DateTime.now()
        .subtract(const Duration(minutes: 2))
        .millisecondsSinceEpoch,
    severity: Severity.info,
    channel: 'Application',
    providerName: 'Chrome',
    title: 'Chrome started',
    summary: 'Chrome started.',
    message: 'Chrome started.',
  ),
  TimelineEvent(
    eventId: 'mock|3|7040',
    timestampUnixMs: DateTime.now()
        .subtract(const Duration(minutes: 5))
        .millisecondsSinceEpoch,
    severity: Severity.info,
    channel: 'System',
    providerName: 'Service Control Manager',
    winEventId: 7040,
    recordId: 3,
    computerName: 'DESKTOP',
    title: 'Windows Service Configuration Changed',
    summary:
        'Windows updated the startup configuration of a background service.',
    actionRequired: false,
    importance: Importance.low,
    category: 'Service',
    technicalSummary:
        'Service Control Manager Event ID 7040 · System · Service',
    message:
        'The start type of the Background Intelligent Transfer Service service '
        'was changed from auto start to demand start.',
  ),
  TimelineEvent(
    eventId: 'mock|4|1000',
    timestampUnixMs: DateTime.now()
        .subtract(const Duration(minutes: 12))
        .millisecondsSinceEpoch,
    severity: Severity.error,
    channel: 'Application',
    providerName: 'Application Error',
    winEventId: 1000,
    title: 'Application stopped responding',
    summary: 'explorer.exe stopped responding and was closed.',
    message: 'Faulting application name: explorer.exe',
  ),
  TimelineEvent(
    eventId: 'mock|5|12',
    timestampUnixMs: DateTime.now()
        .subtract(const Duration(minutes: 28))
        .millisecondsSinceEpoch,
    severity: Severity.info,
    channel: 'System',
    providerName: 'Microsoft-Windows-Kernel-General',
    winEventId: 12,
    recordId: 5,
    computerName: 'DESKTOP',
    title: 'Windows Started',
    summary: 'Windows has started successfully.',
    technicalSummary:
        'Microsoft-Windows-Kernel-General Event ID 12 · System · Boot',
    message: 'The operating system started at system time ...',
  ),
];
