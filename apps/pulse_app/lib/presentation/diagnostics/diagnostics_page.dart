import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pulse_protocol/pulse_constants.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../application/client_frame_metrics.dart';
import '../../application/connection_controller.dart';
import '../../application/diagnostics_controller.dart';
import '../../application/timeline_session_controller.dart';
import '../../app/theme/pulse_theme.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../components/connection_indicator.dart';
import '../components/pulse_app_bar.dart';
import '../components/pulse_badge.dart';
import '../components/pulse_button.dart';
import '../components/pulse_card.dart';
import '../components/pulse_section_header.dart';
import '../components/service_lifecycle_controls.dart';
import '../design_system/pulse_skeleton.dart';
import '../health/health_view_models.dart';
import '../health/widgets/health_spec_rows.dart';
import '../utils/pulse_snack.dart';
import '../utils/pulse_user_errors.dart';
import '../../application/service_lifecycle_controller.dart';
import '../../platform/pulse_service_scm.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key, required this.title});

  final String title;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final diag = context.read<DiagnosticsController>();
      diag.frameMetrics.noteRebuild();
      diag.startPolling();
    });
  }

  @override
  void deactivate() {
    context.read<DiagnosticsController>().stopPolling();
    super.deactivate();
  }

  void _snackSuccess(String message) {
    if (!mounted) return;
    PulseSnack.success(context, message);
  }

  void _snackError(String message) {
    if (!mounted) return;
    PulseSnack.error(context, PulseUserErrors.fromMessage(message));
  }

  Future<void> _run(
    Future<String?> Function() action, {
    required String fallbackOk,
  }) async {
    try {
      final detail = await action();
      _snackSuccess(
        (detail == null || detail.trim().isEmpty) ? fallbackOk : detail,
      );
    } catch (e) {
      _snackError(PulseUserErrors.fromObject(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionLabel = context.select<ConnectionController, String>(
      (c) => c.statusLabel,
    );
    final state = context.select<PulseIpcClient, IpcConnectionState>(
      (c) => c.status.state,
    );
    final diag = context.watch<DiagnosticsController>();
    final timeline = context.watch<TimelineSessionController>();
    final ipcStatus = context.watch<PulseIpcClient>().status;
    final snap = diag.snapshot;
    final busy = diag.actionBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseAppBar(
          title: widget.title,
          connectionState: state,
          connectionLabel: connectionLabel,
        ),
        Expanded(
          child: state == IpcConnectionState.disconnected ||
                  state == IpcConnectionState.error
              ? const ServiceOfflineRecovery(
                  titleFallback: 'Diagnostics needs PulseService',
                  showFullControls: true,
                )
              : snap == null && diag.snapshotError == null
                  ? ListView(
                      padding: EdgeInsets.fromLTRB(
                        PulseTokens.pagePadX,
                        20,
                        PulseTokens.pagePadX,
                        PulseTokens.pagePadBottom,
                      ),
                      children: const [
                        PulseSkeletonList(rows: 6, rowHeight: 88, spacing: 12),
                      ],
                    )
                  : LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final pagePad = EdgeInsets.fromLTRB(
                PulseTokens.pagePadX,
                20,
                PulseTokens.pagePadX,
                PulseTokens.pagePadBottom,
              );

              final service = _ServiceCard(
                snap: snap,
                status: ipcStatus,
                error: diag.snapshotError,
                expand: wide,
              );
              final live = _LiveCard(
                snap: snap,
                timeline: timeline,
                status: ipcStatus,
                expand: wide,
              );
              final ipc = _IpcCard(
                status: ipcStatus,
                snap: snap,
                busy: busy,
                snapshotLatencyMs: diag.lastSnapshotLatencyMs,
                expand: wide,
                onPing: () => _run(
                  () async => diag.ping(),
                  fallbackOk: 'Ping complete',
                ),
                onRestart: () => _run(
                  () async {
                    await diag.restartIpc();
                    return 'IPC connection restarted';
                  },
                  fallbackOk: 'IPC connection restarted',
                ),
                onCopy: () => _run(
                  () async => diag.copyDiagnosticsText(),
                  fallbackOk: 'Diagnostics copied',
                ),
              );
              final pipeline = _PipelineCard(
                snap: snap,
                connected: diag.connected,
                liveActive: timeline.liveActive,
                timelineCount: timeline.events.length,
                expand: wide,
              );
              final perf = _PerformanceCard(
                snap: snap,
                error: diag.snapshotError,
                frameMetrics: context.watch<ClientFrameMetrics>(),
                expand: wide,
              );
              final collectors = _CollectorsCard(
                snap: snap,
                error: diag.snapshotError,
                expand: wide,
              );
              final tools = _DeveloperToolsCard(
                busy: busy,
                expand: wide,
                onTestEvent: () => _run(
                  () async {
                    await diag.injectTestEvent();
                    return 'Test event sent to Timeline';
                  },
                  fallbackOk: 'Test event sent',
                ),
                onRestartLive: () => _run(
                  () async {
                    await timeline.restartLiveMonitoring();
                    return 'Live monitoring restarted';
                  },
                  fallbackOk: 'Live monitoring restarted',
                ),
                onClearTimeline: () => _run(
                  () async {
                    await timeline.clearTimeline();
                    return 'Timeline cleared';
                  },
                  fallbackOk: 'Timeline cleared',
                ),
                onExport: () => _run(
                  () async {
                    final path = await diag.exportReport();
                    return 'Exported: $path';
                  },
                  fallbackOk: 'Export complete',
                ),
              );

              return ListView(
                padding: pagePad,
                children: [
                  PulseSectionHeader(
                    title: 'Troubleshooting',
                    subtitle:
                        'When something looks wrong, start here. All data stays on this PC.',
                    trailing: ConnectionIndicator(
                      state: state,
                      label: connectionLabel,
                    ),
                  ),
                  const SizedBox(height: PulseTokens.spaceMd),
                  if (wide) ...[
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: service),
                          const SizedBox(width: 12),
                          Expanded(child: live),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: ipc),
                          const SizedBox(width: 12),
                          Expanded(child: pipeline),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: collectors),
                          const SizedBox(width: 12),
                          Expanded(child: perf),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    tools,
                  ] else ...[
                    service,
                    const SizedBox(height: 12),
                    live,
                    const SizedBox(height: 12),
                    ipc,
                    const SizedBox(height: 12),
                    pipeline,
                    const SizedBox(height: 12),
                    collectors,
                    const SizedBox(height: 12),
                    perf,
                    const SizedBox(height: 12),
                    tools,
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.snap,
    required this.status,
    required this.error,
    this.expand = false,
  });

  final DiagnosticsSnapshot? snap;
  final IpcStatus status;
  final String? error;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final connected = status.state == IpcConnectionState.connected;
    final life = context.watch<ServiceLifecycleController>();
    final unavailable = snap == null
        ? (error ?? 'Unavailable — waiting for PulseService')
        : null;
    return _DiagSection(
      title: 'Service',
      icon: LucideIcons.server,
      expand: expand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HealthSpecSection(
            title: 'Status',
            compact: true,
            rows: [
              HealthSpecRow(label: 'Windows service', value: life.statusLabel),
              HealthSpecRow(
                label: 'IPC',
                value: connected
                    ? 'Connected'
                    : switch (status.state) {
                        IpcConnectionState.connecting => 'Connecting…',
                        IpcConnectionState.disconnected => 'Offline',
                        IpcConnectionState.error => 'Connection issue',
                        IpcConnectionState.connected => 'Connected',
                      },
              ),
              HealthSpecRow(
                label: 'SCM state',
                value: snap?.scmState.isNotEmpty == true
                    ? snap!.scmState
                    : unavailable ?? kUnavailableDash,
              ),
              HealthSpecRow(
                label: 'Startup type',
                value: snap?.scmStartupType.isNotEmpty == true
                    ? snap!.scmStartupType
                    : unavailable ?? kUnavailableDash,
              ),
              HealthSpecRow(
                label: 'Mode',
                value: snap?.runMode.isNotEmpty == true
                    ? snap!.runMode
                    : unavailable ?? kUnavailableDash,
              ),
            ],
          ),
          const SizedBox(height: 12),
          HealthSpecSection(
            title: 'Identity',
            compact: true,
            rows: [
              HealthSpecRow(
                label: 'Service version',
                value: snap?.serviceVersion.isNotEmpty == true
                    ? snap!.serviceVersion
                    : unavailable ?? kUnavailableDash,
              ),
              HealthSpecRow(
                label: 'Build version',
                value: snap?.buildVersion.isNotEmpty == true
                    ? snap!.buildVersion
                    : unavailable ?? kUnavailableDash,
              ),
              HealthSpecRow(
                label: 'Git commit',
                value: snap?.gitCommit.isNotEmpty == true
                    ? snap!.gitCommit
                    : unavailable ?? kUnavailableDash,
              ),
              HealthSpecRow(
                label: 'IPC protocol',
                value: snap != null
                    ? '${snap!.protocolVersion}'
                    : unavailable ?? kUnavailableDash,
              ),
              HealthSpecRow(
                label: 'Binary SHA-256',
                value: snap?.binarySha256.isNotEmpty == true
                    ? snap!.binarySha256
                    : unavailable ?? kUnavailableDash,
              ),
              HealthSpecRow(
                label: 'Executable path',
                value: snap?.executablePath.isNotEmpty == true
                    ? snap!.executablePath
                    : unavailable ?? kUnavailableDash,
              ),
              HealthSpecRow(
                label: 'Install path',
                value: snap?.installPath.isNotEmpty == true
                    ? snap!.installPath
                    : (snap == null
                        ? (unavailable ?? kUnavailableDash)
                        : 'Not installed / no SCM ImagePath'),
              ),
              HealthSpecRow(
                label: 'Paths match',
                value: snap == null
                    ? (unavailable ?? kUnavailableDash)
                    : (snap!.hasPathsMatch
                        ? (snap!.pathsMatch ? 'Yes' : 'No')
                        : kUnavailableDash),
              ),
              HealthSpecRow(
                label: 'Start time',
                value: snap != null && snap!.serviceStartUnixMs > 0
                    ? DateTime.fromMillisecondsSinceEpoch(
                            snap!.serviceStartUnixMs)
                        .toLocal()
                        .toString()
                        .split('.')
                        .first
                    : unavailable ?? kUnavailableDash,
              ),
              HealthSpecRow(
                label: 'Uptime',
                value: snap != null
                    ? _formatDuration(
                        Duration(milliseconds: snap!.serviceUptimeMs),
                      )
                    : unavailable ?? kUnavailableDash,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: PulseTokens.strokeSubtle),
          const SizedBox(height: 14),
          const ServiceLifecycleControls(compact: true),
          if (life.state == PulseServiceScmState.running && !connected) ...[
            const SizedBox(height: 10),
            Text(
              'Service is running — waiting for the local named-pipe connection…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PulseTokens.textTertiary,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({
    required this.snap,
    required this.timeline,
    required this.status,
    this.expand = false,
  });

  final DiagnosticsSnapshot? snap;
  final TimelineSessionController timeline;
  final IpcStatus status;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final lastFromService = snap?.lastLiveEventTitle.trim() ?? '';
    final lastFromClient = timeline.lastLiveEvent?.title.trim() ?? '';
    final lastTitle = lastFromService.isNotEmpty
        ? lastFromService
        : (lastFromClient.isNotEmpty
            ? lastFromClient
            : (snap == null
                ? 'Unavailable — service offline'
                : 'No live event received yet'));

    return _DiagSection(
      title: 'Live Monitoring',
      icon: LucideIcons.radio,
      expand: expand,
      child: Column(
        children: [
          _kv(
            'Status',
            snap == null
                ? (status.state == IpcConnectionState.connected
                    ? 'Waiting for service snapshot…'
                    : 'Unavailable — service offline')
                : (snap!.liveSubscribed ? 'Subscribed' : 'Not subscribed'),
          ),
          _kv(
            'Active channel',
            snap?.liveChannel.isNotEmpty == true
                ? snap!.liveChannel
                : (snap == null ? '—' : 'None'),
          ),
          _kv(
            'Events pushed (service)',
            snap == null ? '—' : '${snap!.liveEventsPushed}',
          ),
          _kv(
            'Events dropped (service)',
            snap == null ? '—' : '${snap!.liveEventsDropped}',
          ),
          _kv(
            'Events / minute (client)',
            timeline.clientEventsPerMinute.toStringAsFixed(0),
          ),
          _kv('Events received (client)', '${timeline.clientLiveReceived}'),
          _kv('Last received event', lastTitle),
          _kv(
            'Subscription reconnects',
            snap == null ? '—' : '${snap!.liveSubscriberReconnects}',
          ),
        ],
      ),
    );
  }
}

class _IpcCard extends StatelessWidget {
  const _IpcCard({
    required this.status,
    required this.snap,
    required this.busy,
    required this.onPing,
    required this.onRestart,
    required this.onCopy,
    this.snapshotLatencyMs,
    this.expand = false,
  });

  final IpcStatus status;
  final DiagnosticsSnapshot? snap;
  final bool busy;
  final VoidCallback onPing;
  final VoidCallback onRestart;
  final VoidCallback onCopy;
  final int? snapshotLatencyMs;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final ipcClient = context.watch<PulseIpcClient>();
    final history = ipcClient.reconnectHistory;
    return _DiagSection(
      title: 'IPC',
      icon: LucideIcons.plug,
      expand: expand,
      trailing: const PulseBadge(
        label: kPipeName,
        compact: true,
        icon: LucideIcons.plug,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HealthSpecSection(
            title: 'Latency',
            compact: true,
            rows: [
              HealthSpecRow(
                label: 'Last ping',
                value: status.lastPingLatencyMs == null
                    ? 'Not measured yet — use Ping Service'
                    : '${status.lastPingLatencyMs} ms',
              ),
              HealthSpecRow(
                label: 'Average ping',
                value: status.avgPingLatencyMs == null
                    ? kUnavailableDash
                    : '${status.avgPingLatencyMs!.toStringAsFixed(1)} ms',
              ),
              HealthSpecRow(
                label: 'Snapshot RPC',
                value: snapshotLatencyMs == null
                    ? kUnavailableDash
                    : '$snapshotLatencyMs ms',
              ),
              HealthSpecRow(
                label: 'Protocol version',
                value: snap != null
                    ? '${snap!.protocolVersion}'
                    : '$kProtocolVersion (client)',
              ),
            ],
          ),
          const SizedBox(height: 12),
          HealthSpecSection(
            title: 'Throughput',
            compact: true,
            rows: [
              HealthSpecRow(
                label: 'Messages received',
                value: snap == null ? kUnavailableDash : '${snap!.ipcMessagesReceived}',
              ),
              HealthSpecRow(
                label: 'Messages sent',
                value: snap == null ? kUnavailableDash : '${snap!.ipcMessagesSent}',
              ),
              HealthSpecRow(
                label: 'Bytes received',
                value: snap == null
                    ? kUnavailableDash
                    : formatBytesBinary(snap!.ipcBytesReceived),
              ),
              HealthSpecRow(
                label: 'Bytes sent',
                value: snap == null
                    ? kUnavailableDash
                    : formatBytesBinary(snap!.ipcBytesSent),
              ),
              HealthSpecRow(
                label: 'Messages / sec',
                value: snap?.hasIpcMessagesPerSec == true
                    ? snap!.ipcMessagesPerSec.toStringAsFixed(1)
                    : (snap == null
                        ? kUnavailableDash
                        : 'Measuring… (needs a second sample)'),
              ),
              HealthSpecRow(
                label: 'Bytes / sec',
                value: snap?.hasIpcBytesPerSec == true
                    ? '${formatBytesBinary(snap!.ipcBytesPerSec.round())}/s'
                    : (snap == null
                        ? kUnavailableDash
                        : 'Measuring… (needs a second sample)'),
              ),
              HealthSpecRow(
                label: 'IPC errors',
                value: snap == null ? kUnavailableDash : '${snap!.ipcErrors}',
              ),
              HealthSpecRow(
                label: 'Client messages',
                value: '${status.messagesSent}',
              ),
              HealthSpecRow(
                label: 'Client failures',
                value: '${status.messagesFailed}',
              ),
              HealthSpecRow(
                label: 'Reconnect count',
                value: '${status.reconnectCount}',
              ),
            ],
          ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 12),
            HealthSpecSection(
              title: 'Reconnect history',
              compact: true,
              rows: [
                for (final e in history.reversed.take(6))
                  HealthSpecRow(
                    label: DateTime.fromMillisecondsSinceEpoch(e.unixMs)
                        .toLocal()
                        .toString()
                        .split('.')
                        .first,
                    value: e.reason,
                  ),
              ],
            ),
          ],
          if (status.lastError.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Last issue: ${PulseUserErrors.fromMessage(status.lastError)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PulseTokens.error,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              PulseButton(
                label: busy ? 'Working…' : 'Ping Service',
                icon: LucideIcons.zap,
                loading: busy,
                onPressed: busy ? null : onPing,
              ),
              PulseButton(
                label: 'Restart IPC Connection',
                icon: LucideIcons.refreshCw,
                variant: PulseButtonVariant.secondary,
                onPressed: busy ? null : onRestart,
              ),
              PulseButton(
                label: 'Copy Diagnostics',
                icon: LucideIcons.copy,
                variant: PulseButtonVariant.secondary,
                onPressed: busy ? null : onCopy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PipelineCard extends StatelessWidget {
  const _PipelineCard({
    required this.snap,
    required this.connected,
    required this.liveActive,
    required this.timelineCount,
    this.expand = false,
  });

  final DiagnosticsSnapshot? snap;
  final bool connected;
  final bool liveActive;
  final int timelineCount;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final offline = !connected || snap == null;
    String stageDetail(int level, String specific, String fallback) {
      if (offline) return 'Unavailable — PulseService offline';
      if (specific.trim().isNotEmpty) return specific;
      if (snap!.stageDetail.isNotEmpty && level > 0) return snap!.stageDetail;
      return fallback;
    }

    final stages = <(String, int, String)>[
      (
        'Windows Event Log',
        offline ? 2 : snap!.stageEventLog,
        stageDetail(
          offline ? 2 : snap!.stageEventLog,
          snap?.stageEventLogDetail ?? '',
          'Service stage report',
        ),
      ),
      (
        'Collector',
        offline ? 2 : snap!.stageCollector,
        stageDetail(
          offline ? 2 : snap!.stageCollector,
          snap?.stageCollectorDetail ?? '',
          'Service stage report',
        ),
      ),
      (
        'Intelligence',
        offline ? 2 : snap!.stageIntelligence,
        stageDetail(
          offline ? 2 : snap!.stageIntelligence,
          snap?.stageIntelligenceDetail ?? '',
          'Service stage report',
        ),
      ),
      (
        'IPC',
        offline ? 2 : snap!.stageIpc,
        stageDetail(
          offline ? 2 : snap!.stageIpc,
          snap?.stageIpcDetail ?? '',
          snap?.ipcListening == true
              ? 'Named pipe listening'
              : 'Not listening',
        ),
      ),
      (
        'Flutter',
        connected ? 0 : 2,
        connected ? 'UI connected to service' : 'Disconnected from service',
      ),
      (
        'Timeline',
        liveActive || timelineCount > 0 ? 0 : (connected ? 1 : 2),
        liveActive
            ? 'Live updates active ($timelineCount events)'
            : (timelineCount > 0
                ? '$timelineCount stored events'
                : 'No events loaded yet'),
      ),
    ];

    return _DiagSection(
      title: 'Event Pipeline',
      icon: LucideIcons.gitBranch,
      expand: expand,
      child: Column(
        children: [
          for (var i = 0; i < stages.length; i++) ...[
            _PipelineStage(
              name: stages[i].$1,
              level: stages[i].$2,
              detail: stages[i].$3,
            ),
            if (i < stages.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 18, top: 2, bottom: 2),
                child: Icon(
                  LucideIcons.arrowDown,
                  size: 14,
                  color: PulseTokens.textDisabled,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PipelineStage extends StatelessWidget {
  const _PipelineStage({
    required this.name,
    required this.level,
    required this.detail,
  });

  final String name;
  final int level;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (level) {
      0 => ('Healthy', PulseBadgeTone.success),
      1 => ('Warning', PulseBadgeTone.warning),
      _ => ('Error', PulseBadgeTone.error),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PulseBadge(label: label, tone: tone, compact: true),
        ],
      ),
    );
  }
}

class _CollectorsCard extends StatelessWidget {
  const _CollectorsCard({
    required this.snap,
    required this.error,
    this.expand = false,
  });

  final DiagnosticsSnapshot? snap;
  final String? error;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final unavailable = snap == null
        ? (error ?? 'Unavailable — waiting for PulseService')
        : null;
    return _DiagSection(
      title: 'Collectors',
      icon: LucideIcons.activity,
      expand: expand,
      child: HealthSpecSection(
        compact: true,
        rows: [
          HealthSpecRow(
            label: 'Health monitoring',
            value: snap == null
                ? (unavailable ?? kUnavailableDash)
                : (snap!.healthMonitoringActive ? 'Active' : 'Idle'),
          ),
          HealthSpecRow(
            label: 'Health sample rate',
            value: snap == null
                ? (unavailable ?? kUnavailableDash)
                : (snap!.healthMonitoringActive
                    ? '${snap!.healthSampleRateHz.toStringAsFixed(0)} Hz'
                    : '0 Hz (starts with health monitoring)'),
          ),
          HealthSpecRow(
            label: 'Network ETW',
            value: snap == null
                ? (unavailable ?? kUnavailableDash)
                : (snap!.networkEtwRunning ? 'Running' : 'Stopped'),
          ),
          HealthSpecRow(
            label: 'Network ETW last error',
            value: snap == null
                ? (unavailable ?? kUnavailableDash)
                : (snap!.networkEtwLastError.isNotEmpty
                    ? snap!.networkEtwLastError
                    : 'None'),
          ),
          const HealthSpecRow(
            label: 'Dropped samples',
            value: kNotSupported,
            description: 'No collector drop counter is instrumented yet',
          ),
        ],
      ),
    );
  }
}

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({
    required this.snap,
    required this.error,
    required this.frameMetrics,
    this.expand = false,
  });

  final DiagnosticsSnapshot? snap;
  final String? error;
  final ClientFrameMetrics frameMetrics;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return _DiagSection(
      title: 'Pulse Performance',
      icon: LucideIcons.gauge,
      expand: expand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HealthSpecSection(
            title: 'Service process',
            compact: true,
            rows: snap == null
                ? [
                    HealthSpecRow(
                      label: 'Status',
                      value: error ??
                          'Service process metrics are unavailable while PulseService is offline.',
                    ),
                  ]
                : [
                    HealthSpecRow(
                      label: 'CPU usage',
                      value: snap!.hasCpuPercent
                          ? '${snap!.cpuPercent.toStringAsFixed(1)} %'
                          : 'Measuring… (needs a second sample)',
                    ),
                    HealthSpecRow(
                      label: 'Memory (working set)',
                      value: formatBytesBinary(snap!.workingSetBytes),
                    ),
                    HealthSpecRow(
                      label: 'Thread count',
                      value: '${snap!.threadCount}',
                    ),
                    HealthSpecRow(
                      label: 'Handle count',
                      value: '${snap!.handleCount}',
                    ),
                    HealthSpecRow(
                      label: 'Queue size',
                      value:
                          '${snap!.liveQueueDepth} / ${snap!.liveQueueCapacity}',
                    ),
                    HealthSpecRow(
                      label: 'Service PID',
                      value: '${snap!.servicePid}',
                    ),
                  ],
          ),
          const SizedBox(height: 12),
          HealthSpecSection(
            title: 'Flutter client',
            compact: true,
            rows: [
              HealthSpecRow(
                label: 'FPS',
                value: frameMetrics.fps == null
                    ? 'Measuring…'
                    : frameMetrics.fps!.toStringAsFixed(1),
              ),
              HealthSpecRow(
                label: 'Frame time',
                value: frameMetrics.avgTotalFrameMs == null
                    ? 'Measuring…'
                    : '${frameMetrics.avgTotalFrameMs!.toStringAsFixed(2)} ms',
              ),
              HealthSpecRow(
                label: 'Build time',
                value: frameMetrics.avgBuildMs == null
                    ? 'Measuring…'
                    : '${frameMetrics.avgBuildMs!.toStringAsFixed(2)} ms',
              ),
              HealthSpecRow(
                label: 'Raster time',
                value: frameMetrics.avgRasterMs == null
                    ? 'Measuring…'
                    : '${frameMetrics.avgRasterMs!.toStringAsFixed(2)} ms',
              ),
              HealthSpecRow(
                label: 'Memory (RSS)',
                value: frameMetrics.rssBytes == null
                    ? kUnavailableDash
                    : formatBytesBinary(frameMetrics.rssBytes!),
              ),
              HealthSpecRow(
                label: 'Rebuild notes',
                value: '${frameMetrics.rebuildCount}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeveloperToolsCard extends StatelessWidget {
  const _DeveloperToolsCard({
    required this.busy,
    required this.onTestEvent,
    required this.onRestartLive,
    required this.onClearTimeline,
    required this.onExport,
    this.expand = false,
  });

  final bool busy;
  final VoidCallback onTestEvent;
  final VoidCallback onRestartLive;
  final VoidCallback onClearTimeline;
  final VoidCallback onExport;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return _DiagSection(
      title: 'Developer Tools',
      icon: LucideIcons.wrench,
      expand: expand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inject Test Event pushes a Pulse.Diagnostics synthetic event over IPC. '
            'It does not write to the Windows Event Log.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              PulseButton(
                label: 'Inject Test Event',
                icon: LucideIcons.beaker,
                onPressed: busy ? null : onTestEvent,
              ),
              PulseButton(
                label: 'Restart Live Monitoring',
                icon: LucideIcons.radio,
                variant: PulseButtonVariant.secondary,
                onPressed: busy ? null : onRestartLive,
              ),
              PulseButton(
                label: 'Clear Timeline',
                icon: LucideIcons.trash2,
                variant: PulseButtonVariant.secondary,
                onPressed: busy ? null : onClearTimeline,
              ),
              PulseButton(
                label: 'Export Diagnostics Report',
                icon: LucideIcons.download,
                variant: PulseButtonVariant.secondary,
                onPressed: busy ? null : onExport,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagSection extends StatelessWidget {
  const _DiagSection({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.expand = false,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    // Avoid LayoutBuilder here — Diagnostics uses IntrinsicHeight rows, and
    // LayoutBuilder cannot compute dry layout inside IntrinsicHeight.
    return PulseCard(
      elevated: true,
      fillHeight: expand,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: PulseTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

Widget _kv(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 2,
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: PulseTokens.textTertiary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Tooltip(
            message: value,
            waitDuration: const Duration(milliseconds: 450),
            child: Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: PulseTokens.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
