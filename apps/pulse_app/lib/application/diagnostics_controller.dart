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
import 'settings_controller.dart';
import 'timeline_session_controller.dart';

/// Owns Diagnostics page polling, actions, and export. TASK-008.
class DiagnosticsController extends ChangeNotifier {
  DiagnosticsController({
    required this.ipc,
    required this.timeline,
    required this.settings,
    required this.logger,
  }) {
    ipc.addListener(_onIpc);
  }

  final PulseIpcClient ipc;
  final TimelineSessionController timeline;
  final SettingsController settings;
  final AppLogger logger;

  DiagnosticsSnapshot? snapshot;
  String? snapshotError;
  bool polling = false;
  bool actionBusy = false;
  Timer? _pollTimer;
  HealthStaticInfo? lastHealthInfo;
  HealthSample? lastHealthSample;

  bool get connected => ipc.status.state == IpcConnectionState.connected;

  void startPolling() {
    if (polling) return;
    polling = true;
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
          'PulseService is offline. Start PulseService.exe --console to load service diagnostics.';
      notifyListeners();
      return;
    }
    try {
      snapshot = await ipc.getDiagnosticsSnapshot();
      snapshotError = null;
      notifyListeners();
    } catch (e) {
      snapshotError = e.toString();
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
    final buf = StringBuffer()
      ..writeln('Pulse Diagnostics')
      ..writeln('App: $kAppVersion')
      ..writeln('Protocol: ${s?.protocolVersion ?? kProtocolVersion}')
      ..writeln('IPC state: ${st.state.name}')
      ..writeln(
          'Service version: ${s?.serviceVersion.isNotEmpty == true ? s!.serviceVersion : (st.serviceVersion.isEmpty ? '—' : st.serviceVersion)}')
      ..writeln('Client reconnects: ${st.reconnectCount}')
      ..writeln('Last ping: ${st.lastPingLatencyMs ?? '—'} ms')
      ..writeln('Avg ping: ${st.avgPingLatencyMs?.toStringAsFixed(1) ?? '—'} ms')
      ..writeln('Messages sent: ${st.messagesSent}')
      ..writeln('Messages failed: ${st.messagesFailed}');
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
        ..writeln('Threads: ${s.threadCount} Handles: ${s.handleCount}');
    } else if (snapshotError != null) {
      buf.writeln('Snapshot error: $snapshotError');
    }
    return buf.toString();
  }

  Future<String> exportReport() => _guarded(() async {
        // Refresh service snapshot + hardware before packaging.
        if (connected) {
          try {
            snapshot = await ipc.getDiagnosticsSnapshot();
            snapshotError = null;
          } catch (e) {
            snapshotError = e.toString();
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
            'service_messages_received': s?.ipcMessagesReceived,
            'service_messages_sent': s?.ipcMessagesSent,
            'service_ipc_errors': s?.ipcErrors,
            'connected_clients': s?.connectedClients,
            'last_transport_error':
                ipc.status.lastError.isEmpty ? null : ipc.status.lastError,
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

  @override
  void dispose() {
    stopPolling();
    ipc.removeListener(_onIpc);
    super.dispose();
  }
}
