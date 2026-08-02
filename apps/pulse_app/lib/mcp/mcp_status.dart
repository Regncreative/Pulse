import 'dart:convert';
import 'dart:io';

import 'mcp_paths.dart';

/// Snapshot of PulseMCP `status.json` (UI bridge — not MCP protocol).
class McpStatusSnapshot {
  const McpStatusSnapshot({
    required this.running,
    required this.fresh,
    required this.version,
    required this.uptimeSeconds,
    required this.transport,
    required this.mode,
    required this.policyEnabled,
    required this.requestsServed,
    required this.requestsFailed,
    required this.averageLatencyMs,
    required this.averageIpcLatencyMs,
    required this.activeSubscriptions,
    required this.connectedClients,
    required this.clientNames,
    required this.namespaces,
    required this.memoryBytes,
    required this.lastReconnectAt,
    required this.servicePipeConnected,
    required this.pid,
    required this.logPath,
    required this.updatedAt,
    required this.rawPath,
  });

  final bool running;
  final bool fresh;
  final String? version;
  final int uptimeSeconds;
  final String? transport;
  final String? mode;
  final bool policyEnabled;
  final int requestsServed;
  final int requestsFailed;
  final int averageLatencyMs;
  final int averageIpcLatencyMs;
  final List<String> activeSubscriptions;
  final int connectedClients;
  final List<String> clientNames;
  final List<String> namespaces;
  final int? memoryBytes;
  final String? lastReconnectAt;
  final bool servicePipeConnected;
  final int? pid;
  final String? logPath;
  final DateTime? updatedAt;
  final String rawPath;

  static McpStatusSnapshot offline() => McpStatusSnapshot(
        running: false,
        fresh: false,
        version: null,
        uptimeSeconds: 0,
        transport: null,
        mode: null,
        policyEnabled: false,
        requestsServed: 0,
        requestsFailed: 0,
        averageLatencyMs: 0,
        averageIpcLatencyMs: 0,
        activeSubscriptions: const [],
        connectedClients: 0,
        clientNames: const [],
        namespaces: const [],
        memoryBytes: null,
        lastReconnectAt: null,
        servicePipeConnected: false,
        pid: null,
        logPath: McpPaths.logsDir,
        updatedAt: null,
        rawPath: McpPaths.statusFile,
      );
}

class McpStatusReader {
  const McpStatusReader({this.staleAfter = const Duration(seconds: 6)});

  final Duration staleAfter;

  Future<McpStatusSnapshot> read() async {
    final file = File(McpPaths.statusFile);
    if (!await file.exists()) {
      return McpStatusSnapshot.offline();
    }
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return McpStatusSnapshot.offline();
      final map = Map<String, dynamic>.from(raw);
      final updatedAt = DateTime.tryParse('${map['updatedAt'] ?? ''}');
      final fresh = updatedAt != null &&
          DateTime.now().toUtc().difference(updatedAt.toUtc()) <= staleAfter;
      final running = map['running'] == true && fresh;
      return McpStatusSnapshot(
        running: running,
        fresh: fresh,
        version: map['version'] as String?,
        uptimeSeconds: (map['uptimeSeconds'] as num?)?.toInt() ?? 0,
        transport: map['transport'] as String?,
        mode: map['mode'] as String?,
        policyEnabled: map['policyEnabled'] == true,
        requestsServed: (map['requestsServed'] as num?)?.toInt() ?? 0,
        requestsFailed: (map['requestsFailed'] as num?)?.toInt() ?? 0,
        averageLatencyMs: (map['averageLatencyMs'] as num?)?.toInt() ?? 0,
        averageIpcLatencyMs: (map['averageIpcLatencyMs'] as num?)?.toInt() ?? 0,
        activeSubscriptions: _stringList(map['activeSubscriptions']),
        connectedClients: (map['connectedClients'] as num?)?.toInt() ?? 0,
        clientNames: _stringList(map['clientNames']),
        namespaces: _stringList(map['namespaces']),
        memoryBytes: (map['memoryBytes'] as num?)?.toInt(),
        lastReconnectAt: map['lastReconnectAt'] as String?,
        servicePipeConnected: map['servicePipeConnected'] == true,
        pid: (map['pid'] as num?)?.toInt(),
        logPath: map['logPath'] as String? ?? McpPaths.logsDir,
        updatedAt: updatedAt,
        rawPath: file.path,
      );
    } catch (_) {
      return McpStatusSnapshot.offline();
    }
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }
}
