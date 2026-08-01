import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pulse_protocol/pulse_constants.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../ipc/pulse_ipc_client.dart';
import '../logging/app_logger.dart';
import '../presentation/utils/pulse_user_errors.dart';
import 'client_frame_metrics.dart';
import 'settings_controller.dart';
import 'timeline_session_controller.dart';

/// Owns Diagnostics page polling, actions, and export.
class DiagnosticsController extends ChangeNotifier {
  DiagnosticsController({
    required this.ipc,
    required this.timeline,
    required this.settings,
    required this.logger,
    required this.frameMetrics,
  }) {
    ipc.addListener(_onIpc);
    frameMetrics.addListener(_onFrames);
  }

  final PulseIpcClient ipc;
  final TimelineSessionController timeline;
  final SettingsController settings;
  final AppLogger logger;
  final ClientFrameMetrics frameMetrics;

  DiagnosticsSnapshot? snapshot;
  String? snapshotError;
  bool polling = false;
  bool actionBusy = false;
  Timer? _pollTimer;
  HealthStaticInfo? lastHealthInfo;
  HealthSample? lastHealthSample;

  /// Client-measured round-trip of GetDiagnosticsSnapshot (ms).
  int? lastSnapshotLatencyMs;

  bool get connected => ipc.status.state == IpcConnectionState.connected;

  void startPolling() {
    if (polling) return;
    polling = true;
    frameMetrics.noteRebuild();
    unawaited(refresh());
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(refresh());
    });
    notifyListeners();
  }

  void stopPolling() {
    polling = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    // Do not notifyListeners here — stopPolling runs from State.deactivate
    // during route transitions (AnimatedSwitcher), which forbids rebuilds.
  }

  Future<void> refresh() async {
    if (!connected) {
      snapshot = null;
      snapshotError =
          'PulseService is offline. Start it to load service diagnostics.';
      lastSnapshotLatencyMs = null;
      notifyListeners();
      return;
    }
    try {
      final started = DateTime.now();
      snapshot = await ipc.getDiagnosticsSnapshot();
      lastSnapshotLatencyMs =
          DateTime.now().difference(started).inMilliseconds.clamp(0, 60000);
      snapshotError = null;
      frameMetrics.refreshMemory();
      notifyListeners();
    } catch (e) {
      snapshotError = PulseUserErrors.fromObject(e);
      notifyListeners();
    }
  }

  Future<T> _guarded<T>(Future<T> Function() action) async {
    if (actionBusy) {
      throw StateError('Another diagnostics action is already running.');
    }
    actionBusy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      actionBusy = false;
      notifyListeners();
    }
  }

  Future<String> ping() => _guarded(() async {
        final pong = await ipc.ping();
        final msg =
            'Pong nonce=${pong.nonce} service=${pong.serviceVersion} '
            'latency=${ipc.status.lastPingLatencyMs ?? '—'} ms';
        logger.info('Diagnostics', msg);
        return msg;
      });

  Future<void> restartIpc() => _guarded(() async {
        logger.info('Diagnostics', 'Restarting IPC connection');
        await ipc.restartConnection();
      });

  Future<void> injectTestEvent() => _guarded(() async {
        await ipc.injectDiagnosticsTestEvent();
        logger.info('Diagnostics', 'Injected diagnostics test event');
      });

  Future<String> copyDiagnosticsText() => _guarded(() async {
        final text = buildDiagnosticsText();
        await Clipboard.setData(ClipboardData(text: text));
        return 'Copied to clipboard';
      });

  String buildDiagnosticsText() {
    final s = snapshot;
    final st = ipc.status;
    final fm = frameMetrics;
    final buf = StringBuffer()
      ..writeln('Pulse Diagnostics')
      ..writeln('App: $kAppVersion')
      ..writeln('Protocol: ${s?.protocolVersion ?? kProtocolVersion}')
      ..writeln('IPC state: ${st.state.name}')
      ..writeln(
          'Service version: ${s?.serviceVersion.isNotEmpty == true ? s!.serviceVersion : (st.serviceVersion.isEmpty ? '—' : st.serviceVersion)}')
      ..writeln(
          'Build version: ${s?.buildVersion.isNotEmpty == true ? s!.buildVersion : '—'}')
      ..writeln(
          'Git commit: ${s?.gitCommit.isNotEmpty == true ? s!.gitCommit : '—'}')
      ..writeln(
          'Executable: ${s?.executablePath.isNotEmpty == true ? s!.executablePath : '—'}')
      ..writeln(
          'Install path: ${s?.installPath.isNotEmpty == true ? s!.installPath : '—'}')
      ..writeln(
          'SHA256: ${s?.binarySha256.isNotEmpty == true ? s!.binarySha256 : '—'}')
      ..writeln(
          'SCM: ${s?.scmState.isNotEmpty == true ? s!.scmState : '—'} / ${s?.scmStartupType.isNotEmpty == true ? s!.scmStartupType : '—'}')
      ..writeln('Client reconnects: ${st.reconnectCount}')
      ..writeln('Last ping: ${st.lastPingLatencyMs ?? '—'} ms')
      ..writeln('Snapshot RPC: ${lastSnapshotLatencyMs ?? '—'} ms')
      ..writeln(
          'Avg ping: ${st.avgPingLatencyMs?.toStringAsFixed(1) ?? '—'} ms')
      ..writeln('Messages sent: ${st.messagesSent}')
      ..writeln('Messages failed: ${st.messagesFailed}')
      ..writeln('Client FPS: ${fm.fps?.toStringAsFixed(1) ?? '—'}')
      ..writeln(
          'Client frame ms: ${fm.avgTotalFrameMs?.toStringAsFixed(2) ?? '—'}')
      ..writeln('Client RSS: ${fm.rssBytes ?? '—'}');
    if (s != null) {
      buf
        ..writeln('Run mode: ${s.runMode}')
        ..writeln('Service uptime ms: ${s.serviceUptimeMs}')
        ..writeln('Windows: ${s.windowsEdition} ${s.windowsVersion}'.trim())
        ..writeln('Live subscribed: ${s.liveSubscribed}')
        ..writeln('Live channel: ${s.liveChannel}')
        ..writeln('Live events pushed: ${s.liveEventsPushed}')
        ..writeln('Live dropped: ${s.liveEventsDropped}')
        ..writeln('Queue: ${s.liveQueueDepth}/${s.liveQueueCapacity}')
        ..writeln(
            'Service CPU: ${s.hasCpuPercent ? '${s.cpuPercent.toStringAsFixed(1)}%' : '—'}')
        ..writeln('Working set: ${s.workingSetBytes}')
        ..writeln('Threads: ${s.threadCount} Handles: ${s.handleCount}')
        ..writeln('IPC bytes rx/tx: ${s.ipcBytesReceived}/${s.ipcBytesSent}')
        ..writeln(
            'IPC msg/s: ${s.hasIpcMessagesPerSec ? s.ipcMessagesPerSec.toStringAsFixed(1) : '—'}')
        ..writeln(
            'IPC bytes/s: ${s.hasIpcBytesPerSec ? s.ipcBytesPerSec.toStringAsFixed(0) : '—'}')
        ..writeln('Health monitoring: ${s.healthMonitoringActive}')
        ..writeln('Health sample Hz: ${s.healthSampleRateHz}')
        ..writeln('Network ETW: ${s.networkEtwRunning}')
        ..writeln(
            'Network ETW error: ${s.networkEtwLastError.isEmpty ? '—' : s.networkEtwLastError}');
    } else if (snapshotError != null) {
      buf.writeln('Snapshot error: $snapshotError');
    }
    if (ipc.reconnectHistory.isNotEmpty) {
      buf.writeln('Reconnect history:');
      for (final e in ipc.reconnectHistory.reversed) {
        buf.writeln(
            '  ${DateTime.fromMillisecondsSinceEpoch(e.unixMs).toLocal()} — ${e.reason}');
      }
    }
    return buf.toString();
  }

  Future<String> exportReport() => _guarded(() async {
        // Refresh service snapshot + hardware before packaging.
        if (connected) {
          try {
            final started = DateTime.now();
            snapshot = await ipc.getDiagnosticsSnapshot();
            lastSnapshotLatencyMs = DateTime.now()
                .difference(started)
                .inMilliseconds
                .clamp(0, 60000);
            snapshotError = null;
          } catch (e) {
            snapshotError = PulseUserErrors.fromObject(e);
          }
          try {
            final hs = await ipc.getHealthSnapshot();
            lastHealthInfo = hs.info;
            lastHealthSample = hs.sample;
          } catch (_) {}
        }

        final dir = await getApplicationDocumentsDirectory();
        final exportDir = Directory(
          '${dir.path}${Platform.pathSeparator}Pulse${Platform.pathSeparator}exports',
        );
        if (!await exportDir.exists()) {
          await exportDir.create(recursive: true);
        }
        final stamp = DateTime.now()
            .toIso8601String()
            .replaceAll(':', '-')
            .split('.')
            .first;
        final jsonName = 'pulse-diagnostics-$stamp.json';
        final zipName = 'pulse-diagnostics-$stamp.zip';

        final recentErrors = logger.lines
            .where((l) => l.contains('level=error') || l.contains('level=warn'))
            .toList();
        final recentErrorSlice = recentErrors.length > 50
            ? recentErrors.sublist(recentErrors.length - 50)
            : recentErrors;

        final recentEvents = timeline.events.take(25).map((e) {
          return {
            'event_id': e.eventId,
            'title': e.title,
            'channel': e.channel,
            'provider': e.providerName,
            'win_event_id': e.winEventId,
            'timestamp_unix_ms': e.timestampUnixMs,
            'severity': e.severity,
            'summary': e.summary,
          };
        }).toList();

        final s = snapshot;
        final fm = frameMetrics;
        final payload = <String, dynamic>{
          'exported_at': DateTime.now().toIso8601String(),
          'pulse_version': kAppVersion,
          'service_version': s?.serviceVersion.isNotEmpty == true
              ? s!.serviceVersion
              : ipc.status.serviceVersion,
          'protocol_version': s?.protocolVersion ?? kProtocolVersion,
          'build_date': SettingsController.buildDate,
          'windows_version': s == null
              ? null
              : {
                  'edition': s.windowsEdition,
                  'version': s.windowsVersion,
                },
          'service_identity': s == null
              ? null
              : {
                  'executable_path': s.executablePath,
                  'build_version': s.buildVersion,
                  'git_commit': s.gitCommit,
                  'binary_sha256': s.binarySha256,
                  'install_path': s.installPath,
                  'has_paths_match': s.hasPathsMatch,
                  'paths_match': s.hasPathsMatch ? s.pathsMatch : null,
                  'scm_state': s.scmState,
                  'scm_startup_type': s.scmStartupType,
                },
          'hardware_summary': lastHealthInfo == null
              ? null
              : {
                  'cpu': lastHealthInfo!.cpuModel,
                  'gpu': lastHealthInfo!.gpuModel,
                  'ram_bytes': lastHealthInfo!.installedRamBytes,
                  'storage_bytes': lastHealthInfo!.primaryStorageBytes,
                  'network_adapter': lastHealthInfo!.activeNetworkAdapter,
                  'windows':
                      '${lastHealthInfo!.windowsEdition} ${lastHealthInfo!.windowsVersion}'
                          .trim(),
                },
          'current_settings': settings.toMap(),
          'ipc_statistics': {
            'state': ipc.status.state.name,
            'client_reconnect_count': ipc.status.reconnectCount,
            'client_messages_sent': ipc.status.messagesSent,
            'client_messages_failed': ipc.status.messagesFailed,
            'last_ping_ms': ipc.status.lastPingLatencyMs,
            'avg_ping_ms': ipc.status.avgPingLatencyMs,
            'last_snapshot_rpc_ms': lastSnapshotLatencyMs,
            'service_messages_received': s?.ipcMessagesReceived,
            'service_messages_sent': s?.ipcMessagesSent,
            'service_ipc_errors': s?.ipcErrors,
            'service_ipc_bytes_received': s?.ipcBytesReceived,
            'service_ipc_bytes_sent': s?.ipcBytesSent,
            'has_ipc_messages_per_sec': s?.hasIpcMessagesPerSec,
            'ipc_messages_per_sec':
                s?.hasIpcMessagesPerSec == true ? s!.ipcMessagesPerSec : null,
            'has_ipc_bytes_per_sec': s?.hasIpcBytesPerSec,
            'ipc_bytes_per_sec':
                s?.hasIpcBytesPerSec == true ? s!.ipcBytesPerSec : null,
            'connected_clients': s?.connectedClients,
            'last_transport_error':
                ipc.status.lastError.isEmpty ? null : ipc.status.lastError,
            'reconnect_history': ipc.reconnectHistory
                .map((e) => {'unix_ms': e.unixMs, 'reason': e.reason})
                .toList(),
          },
          'collectors': s == null
              ? null
              : {
                  'health_monitoring_active': s.healthMonitoringActive,
                  'health_sample_rate_hz': s.healthSampleRateHz,
                  'network_etw_running': s.networkEtwRunning,
                  'network_etw_last_error': s.networkEtwLastError.isEmpty
                      ? null
                      : s.networkEtwLastError,
                },
          'flutter_client': {
            'fps': fm.fps,
            'avg_build_ms': fm.avgBuildMs,
            'avg_raster_ms': fm.avgRasterMs,
            'avg_total_frame_ms': fm.avgTotalFrameMs,
            'rss_bytes': fm.rssBytes,
            'rebuild_count': fm.rebuildCount,
          },
          'live_monitoring': {
            'client_active': timeline.liveActive,
            'preference_enabled': settings.liveMonitoringEnabled,
            'service_subscribed': s?.liveSubscribed,
            'channel': s?.liveChannel,
            'events_pushed': s?.liveEventsPushed,
            'events_dropped': s?.liveEventsDropped,
            'subscriber_reconnects': s?.liveSubscriberReconnects,
            'last_event_title': s?.lastLiveEventTitle,
            'last_event_unix_ms': s?.lastLiveEventUnixMs,
            'client_events_received': timeline.clientLiveReceived,
            'client_events_per_minute': timeline.clientEventsPerMinute,
            'queue_depth': s?.liveQueueDepth,
            'queue_capacity': s?.liveQueueCapacity,
          },
          'recent_errors': recentErrorSlice,
          'recent_events': recentEvents,
          'service_metrics': s == null
              ? null
              : {
                  'pid': s.servicePid,
                  'run_mode': s.runMode,
                  'uptime_ms': s.serviceUptimeMs,
                  'start_unix_ms': s.serviceStartUnixMs,
                  'has_cpu_percent': s.hasCpuPercent,
                  'cpu_percent': s.hasCpuPercent ? s.cpuPercent : null,
                  'working_set_bytes': s.workingSetBytes,
                  'thread_count': s.threadCount,
                  'handle_count': s.handleCount,
                  'stage_event_log': s.stageEventLog,
                  'stage_collector': s.stageCollector,
                  'stage_intelligence': s.stageIntelligence,
                  'stage_ipc': s.stageIpc,
                  'stage_detail': s.stageDetail,
                  'stage_event_log_detail': s.stageEventLogDetail,
                  'stage_collector_detail': s.stageCollectorDetail,
                  'stage_intelligence_detail': s.stageIntelligenceDetail,
                  'stage_ipc_detail': s.stageIpcDetail,
                },
          'recent_logs': logger.lines.length > 200
              ? logger.lines.sublist(logger.lines.length - 200)
              : List<String>.from(logger.lines),
          'snapshot_error': snapshotError,
        };

        final jsonText = const JsonEncoder.withIndent('  ').convert(payload);
        final archive = Archive()
          ..addFile(
              ArchiveFile(jsonName, jsonText.length, utf8.encode(jsonText)));
        final zipBytes = ZipEncoder().encode(archive);
        final zipPath = '${exportDir.path}${Platform.pathSeparator}$zipName';
        await File(zipPath).writeAsBytes(zipBytes, flush: true);
        logger.info('Diagnostics', 'Exported $zipPath');
        notifyListeners();
        return zipPath;
      });

  Future<String> exportLogsOnly() => _guarded(() async {
        final dir = await getApplicationDocumentsDirectory();
        final exportDir = Directory(
          '${dir.path}${Platform.pathSeparator}Pulse${Platform.pathSeparator}exports',
        );
        if (!await exportDir.exists()) {
          await exportDir.create(recursive: true);
        }
        final stamp = DateTime.now()
            .toIso8601String()
            .replaceAll(':', '-')
            .split('.')
            .first;
        final path =
            '${exportDir.path}${Platform.pathSeparator}pulse-logs-$stamp.txt';
        await File(path).writeAsString(logger.lines.join('\n'), flush: true);
        return path;
      });

  void resetClientCounters() {
    ipc.resetDiagnosticsCounters();
    notifyListeners();
  }

  void _onIpc() => notifyListeners();
  void _onFrames() {
    if (polling) notifyListeners();
  }

  @override
  void dispose() {
    stopPolling();
    ipc.removeListener(_onIpc);
    frameMetrics.removeListener(_onFrames);
    super.dispose();
  }
}
