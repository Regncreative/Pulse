import 'dart:async';

import 'package:pulse_protocol/pulse_wire.dart';

import '../ipc/pulse_ipc_client.dart';
import 'assistant_tools.dart';
import 'diagnostic_tool_allowlist.dart';

/// Human-readable activity line while a diagnostic tool runs.
String assistantToolActivityLabel(String toolName) {
  final n = AssistantToolAllowlist.normalize(toolName);
  return switch (n) {
    'mcp_self' => 'Checking Assistant status...',
    'system_health' => 'Checking system health...',
    'system_cpu' => 'Checking CPU usage...',
    'system_memory' => 'Checking memory usage...',
    'system_gpu' => 'Checking GPU usage...',
    'system_storage' => 'Checking storage...',
    'system_network' => 'Checking network...',
    'process_list' || 'process_search' || 'process_details' =>
      'Checking running processes...',
    'timeline_list' || 'timeline_search' => 'Checking recent events...',
    'diagnostics_snapshot' => 'Checking Pulse diagnostics...',
    'service_status' => 'Checking PulseService status...',
    _ => 'Checking diagnostics...',
  };
}

/// Read-only diagnostic tools for Pulse Assistant via PulseService IPC.
///
/// Shared backend with PulseMCP: both call PulseService. This layer does not
/// speak MCP and does not mutate Windows or Pulse configuration.
class IpcAssistantToolLayer implements AssistantToolLayer {
  IpcAssistantToolLayer({required this._ipc});

  final PulseIpcClient _ipc;

  @override
  List<AssistantToolDescriptor> listTools() =>
      List.unmodifiable(AssistantToolAllowlist.tools);

  @override
  Future<AssistantToolResult> invoke(
    String toolName, {
    Map<String, Object?> arguments = const {},
  }) async {
    final name = AssistantToolAllowlist.normalize(toolName);

    if (AssistantToolAllowlist.looksDangerous(name) ||
        !AssistantToolAllowlist.isAllowed(name)) {
      return AssistantToolResult(
        ok: false,
        errorCode: 'TOOL_NOT_ALLOWED',
        errorMessage:
            'Tool "$toolName" is not available to Pulse Assistant. '
            'Only read-only diagnostic tools are permitted.',
      );
    }

    try {
      return await _dispatch(name, arguments);
    } on TimeoutException {
      return const AssistantToolResult(
        ok: false,
        errorCode: 'TIMEOUT',
        errorMessage: 'Diagnostic request timed out.',
      );
    } catch (e) {
      final msg = e.toString();
      final ipcDown = msg.contains('not connected') ||
          msg.contains('pipe') ||
          msg.contains('IPC') ||
          msg.contains('Broken pipe');
      return AssistantToolResult(
        ok: false,
        errorCode: ipcDown ? 'PULSE_SERVICE_UNAVAILABLE' : 'TOOL_FAILED',
        errorMessage: ipcDown
            ? 'PulseService is unavailable. Open Pulse and ensure the service is running.'
            : 'Could not read diagnostics for this request.',
      );
    }
  }

  Future<AssistantToolResult> _dispatch(
    String name,
    Map<String, Object?> args,
  ) async {
    switch (name) {
      case 'mcp_self':
        return _mcpSelf();
      case 'system_health':
        return _systemHealth(args);
      case 'system_cpu':
        return _systemSection('cpu');
      case 'system_memory':
        return _systemSection('memory');
      case 'system_gpu':
        return _systemSection('gpu');
      case 'system_storage':
        return _systemSection('storage');
      case 'system_network':
        return _systemSection('network');
      case 'process_list':
        return _processList(args);
      case 'process_search':
        return _processSearch(args);
      case 'process_details':
        return _processDetails(args);
      case 'timeline_list':
        return _timelineList(args);
      case 'timeline_search':
        return _timelineSearch(args);
      case 'diagnostics_snapshot':
        return _diagnosticsSnapshot();
      case 'service_status':
        return _serviceStatus();
      default:
        return AssistantToolResult(
          ok: false,
          errorCode: 'TOOL_NOT_ALLOWED',
          errorMessage: 'Tool "$name" is not allowed.',
        );
    }
  }

  Future<AssistantToolResult> _mcpSelf() async {
    DiagnosticsSnapshot? diag;
    try {
      diag = await _ipc.getDiagnosticsSnapshot();
    } catch (_) {
      diag = null;
    }
    return AssistantToolResult(
      ok: true,
      data: {
        'role': 'pulse_assistant',
        'mode': 'read_only_diagnostics',
        'pulseServiceConnected': diag != null,
        if (diag != null) ...{
          'serviceVersion': diag.serviceVersion,
          'protocolVersion': diag.protocolVersion,
          'runMode': diag.runMode,
          'ipcListening': diag.ipcListening,
        },
        'allowedTools': AssistantToolAllowlist.names.toList()..sort(),
      },
    );
  }

  Future<AssistantToolResult> _systemHealth(Map<String, Object?> args) async {
    final snap = await _ipc.getHealthSnapshot();
    final sections = _stringList(args['sections']);
    final data = <String, Object?>{};
    final want = sections.isEmpty
        ? const ['cpu', 'memory', 'gpu', 'storage', 'network', 'static']
        : sections;
    for (final s in want) {
      data[s] = _sectionMap(snap, s);
    }
    return AssistantToolResult(ok: true, data: data);
  }

  Future<AssistantToolResult> _systemSection(String section) async {
    final snap = await _ipc.getHealthSnapshot();
    return AssistantToolResult(
      ok: true,
      data: {section: _sectionMap(snap, section)},
    );
  }

  Map<String, Object?> _sectionMap(HealthSnapshot snap, String section) {
    final sample = snap.sample;
    final info = snap.info;
    switch (section) {
      case 'cpu':
        return {
          if (sample.hasCpuPercent) 'cpuPercent': sample.cpuPercent,
          if (sample.hasCpuTempC) 'cpuTempC': sample.cpuTempC,
          if (sample.hasCpuCurrentMhz) 'cpuCurrentMhz': sample.cpuCurrentMhz,
          if (sample.cpuCorePercent.isNotEmpty)
            'coreCount': sample.cpuCorePercent.length,
          'topCpu': sample.topCpu.take(8).map(_processBrief).toList(),
        };
      case 'memory':
        return {
          'memoryUsedBytes': sample.memoryUsedBytes,
          'memoryTotalBytes': sample.memoryTotalBytes,
          'memoryAvailableBytes': sample.memoryAvailableBytes,
          if (sample.memoryTotalBytes > 0)
            'memoryUsedPercent':
                (100.0 * sample.memoryUsedBytes) / sample.memoryTotalBytes,
          'topMemory': sample.topMemory.take(8).map(_processBrief).toList(),
        };
      case 'gpu':
        return {
          if (sample.hasGpuPercent) 'gpuPercent': sample.gpuPercent,
          if (sample.hasGpuTempC) 'gpuTempC': sample.gpuTempC,
          'topGpu': sample.topGpu.take(8).map(_processBrief).toList(),
        };
      case 'storage':
        return {
          'diskUsedBytes': sample.diskUsedBytes,
          'diskTotalBytes': sample.diskTotalBytes,
          if (sample.hasDiskReadBps) 'diskReadBps': sample.diskReadBps,
          if (sample.hasDiskWriteBps) 'diskWriteBps': sample.diskWriteBps,
          'volumes': sample.volumes
              .take(12)
              .map(
                (v) => {
                  'mountPoint': v.mountPoint,
                  'label': v.label,
                  'usedBytes': v.usedBytes,
                  'totalBytes': v.totalBytes,
                },
              )
              .toList(),
        };
      case 'network':
        return {
          if (sample.hasNetDownloadBps) 'downloadBps': sample.netDownloadBps,
          if (sample.hasNetUploadBps) 'uploadBps': sample.netUploadBps,
          'ipv4': sample.ipv4,
          'gateway': sample.gateway,
          'topNetwork': sample.topNetwork.take(8).map(_processBrief).toList(),
        };
      case 'static':
        return {
          'windowsEdition': info.windowsEdition,
          'windowsVersion': info.windowsVersion,
          'cpuModel': info.cpuModel,
          'gpuModel': info.gpuModel,
          'installedRamBytes': info.installedRamBytes,
          'primaryStorageBytes': info.primaryStorageBytes,
          'cpuCores': info.cpuCores,
          'cpuLogicalProcessors': info.cpuLogicalProcessors,
        };
      default:
        return {'note': 'Unknown section'};
    }
  }

  Future<AssistantToolResult> _processList(Map<String, Object?> args) async {
    final limit = _clampInt(args['limit'], fallback: 15, min: 1, max: 50);
    final sortBy = (args['sortBy']?.toString() ?? 'memory').toLowerCase();
    final processes = await _collectProcesses();
    _sortProcesses(processes, sortBy);
    return AssistantToolResult(
      ok: true,
      data: {
        'sortBy': sortBy,
        'count': processes.length,
        'processes': processes.take(limit).map(_processBrief).toList(),
      },
    );
  }

  Future<AssistantToolResult> _processSearch(Map<String, Object?> args) async {
    final query = args['query']?.toString().trim() ?? '';
    if (query.isEmpty) {
      return const AssistantToolResult(
        ok: false,
        errorCode: 'INVALID_ARGUMENTS',
        errorMessage: 'query is required',
      );
    }
    final limit = _clampInt(args['limit'], fallback: 15, min: 1, max: 50);
    final q = query.toLowerCase();
    final processes = await _collectProcesses();
    final matches = processes
        .where((p) => p.name.toLowerCase().contains(q))
        .take(limit)
        .map(_processBrief)
        .toList();
    return AssistantToolResult(
      ok: true,
      data: {
        'query': query,
        'count': matches.length,
        'processes': matches,
      },
    );
  }

  Future<AssistantToolResult> _processDetails(Map<String, Object?> args) async {
    final pid = _asInt(args['pid']);
    if (pid == null || pid < 1) {
      return const AssistantToolResult(
        ok: false,
        errorCode: 'INVALID_ARGUMENTS',
        errorMessage: 'pid is required',
      );
    }
    final details = await _ipc.getProcessDetails(pid);
    return AssistantToolResult(
      ok: true,
      data: {
        'pid': details.pid,
        'name': details.name,
        if (details.hasPath) 'path': details.path,
        if (details.hasCompany) 'company': details.company,
        'threadCount': details.threadCount,
        'handleCount': details.handleCount,
        if (details.hasParentPid) 'parentPid': details.parentPid,
        if (details.hasParentName) 'parentName': details.parentName,
        if (details.hasUser) 'user': details.user,
      },
    );
  }

  Future<AssistantToolResult> _timelineList(Map<String, Object?> args) async {
    final limit = _clampInt(args['limit'], fallback: 20, min: 1, max: 50);
    final snap = await _ipc.getTimelineSnapshot(limit: limit);
    return AssistantToolResult(
      ok: true,
      data: {
        'count': snap.events.length,
        'events': snap.events.take(limit).map(_eventBrief).toList(),
      },
    );
  }

  Future<AssistantToolResult> _timelineSearch(Map<String, Object?> args) async {
    final query = args['query']?.toString().trim() ?? '';
    if (query.isEmpty) {
      return const AssistantToolResult(
        ok: false,
        errorCode: 'INVALID_ARGUMENTS',
        errorMessage: 'query is required',
      );
    }
    final limit = _clampInt(args['limit'], fallback: 20, min: 1, max: 50);
    final snap = await _ipc.getTimelineSnapshot(limit: 100);
    final q = query.toLowerCase();
    final matches = snap.events.where((e) {
      final hay = [
        e.title,
        e.summary,
        e.technicalSummary,
        e.message,
        e.providerName,
        e.processName,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).take(limit).toList();
    return AssistantToolResult(
      ok: true,
      data: {
        'query': query,
        'count': matches.length,
        'events': matches.map(_eventBrief).toList(),
      },
    );
  }

  Future<AssistantToolResult> _diagnosticsSnapshot() async {
    final d = await _ipc.getDiagnosticsSnapshot();
    return AssistantToolResult(
      ok: true,
      data: {
        'serviceVersion': d.serviceVersion,
        'protocolVersion': d.protocolVersion,
        'runMode': d.runMode,
        'serviceUptimeMs': d.serviceUptimeMs,
        'ipcListening': d.ipcListening,
        'connectedClients': d.connectedClients,
        'stageEventLog': d.stageEventLog,
        'stageCollector': d.stageCollector,
        'stageIntelligence': d.stageIntelligence,
        'stageIpc': d.stageIpc,
        'stageDetail': d.stageDetail,
        if (d.hasCpuPercent) 'serviceCpuPercent': d.cpuPercent,
        'workingSetBytes': d.workingSetBytes,
      },
    );
  }

  Future<AssistantToolResult> _serviceStatus() async {
    final d = await _ipc.getDiagnosticsSnapshot();
    return AssistantToolResult(
      ok: true,
      data: {
        'serviceVersion': d.serviceVersion,
        'runMode': d.runMode,
        'scmState': d.scmState,
        'scmStartupType': d.scmStartupType,
        'servicePid': d.servicePid,
        'ipcListening': d.ipcListening,
        'executablePath': d.executablePath,
      },
    );
  }

  Future<List<HealthProcessEntry>> _collectProcesses() async {
    final byPid = <int, HealthProcessEntry>{};
    final snap = await _ipc.getHealthSnapshot();
    for (final p in [
      ...snap.sample.topCpu,
      ...snap.sample.topMemory,
      ...snap.sample.topGpu,
      ...snap.sample.topDisk,
      ...snap.sample.topNetwork,
    ]) {
      if (p.pid > 0) byPid[p.pid] = p;
    }

    try {
      await _ipc.startHealthMonitoring();
    } catch (_) {
      // Already monitoring or unavailable — continue with tops.
    }

    try {
      await for (final update in _ipc.healthUpdates.timeout(
        const Duration(milliseconds: 1800),
      )) {
        final inv = update.processInventory;
        if (inv == null) continue;
        if (inv.fullResync) byPid.clear();
        for (final e in inv.upserts) {
          if (e.pid > 0) byPid[e.pid] = e;
        }
        for (final pid in inv.removedPids) {
          byPid.remove(pid);
        }
        if (byPid.length >= 40) break;
      }
    } on TimeoutException {
      // Enough data collected.
    } catch (_) {
      // Stream closed / IPC issues — use what we have.
    }

    return byPid.values.toList();
  }

  void _sortProcesses(List<HealthProcessEntry> list, String sortBy) {
    switch (sortBy) {
      case 'cpu':
        list.sort((a, b) => (b.cpuPercent).compareTo(a.cpuPercent));
      case 'name':
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      default:
        list.sort((a, b) {
          final am = a.hasWorkingSetBytes ? a.workingSetBytes : a.memoryBytes;
          final bm = b.hasWorkingSetBytes ? b.workingSetBytes : b.memoryBytes;
          return bm.compareTo(am);
        });
    }
  }

  Map<String, Object?> _processBrief(HealthProcessEntry p) => {
    'pid': p.pid,
    'name': p.name,
    if (p.hasCpuPercent) 'cpuPercent': p.cpuPercent,
    if (p.hasMemoryBytes) 'memoryBytes': p.memoryBytes,
    if (p.hasWorkingSetBytes) 'workingSetBytes': p.workingSetBytes,
    if (p.path.isNotEmpty) 'path': p.path,
  };

  Map<String, Object?> _eventBrief(TimelineEvent e) => {
    'title': e.title,
    'summary': e.summary,
    'severity': e.severity,
    'channel': e.channel,
    'providerName': e.providerName,
    'timestampIso': e.timestampIso,
    if (e.processName.isNotEmpty) 'processName': e.processName,
    if (e.winEventId != 0) 'winEventId': e.winEventId,
  };

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.map((e) => e.toString()).toList();
  }

  int _clampInt(Object? value, {required int fallback, required int min, required int max}) {
    final n = _asInt(value) ?? fallback;
    if (n < min) return min;
    if (n > max) return max;
    return n;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
