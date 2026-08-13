import 'dart:convert';
import 'dart:io';

import '../mcp_paths.dart';
import 'mcp_client_provider.dart';

/// Persists Pulse-owned registration markers under `%LOCALAPPDATA%\Pulse\mcp\`.
Future<void> writeMcpRegistrationMarker({
  required McpClientId id,
  required bool registered,
  required String configPath,
  required String serverKey,
  String? backupPath,
  List<String>? configPaths,
}) async {
  final file = File(McpPaths.registrationsFile);
  Map<String, dynamic> root = {};
  if (await file.exists()) {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) root = Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  root[id.wireName] = {
    'registeredByPulse': registered,
    'configPath': configPath,
    'configPaths': ?configPaths,
    'serverKey': serverKey,
    'registeredAt': DateTime.now().toUtc().toIso8601String(),
    'lastBackupPath': ?backupPath,
  };
  final dir = Directory(McpPaths.mcpDir);
  if (!await dir.exists()) await dir.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(root)}\n',
  );
}

Future<Map<String, dynamic>> readMcpRegistrationMarker(McpClientId id) async {
  final file = File(McpPaths.registrationsFile);
  if (!await file.exists()) return {};
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map && decoded[id.wireName] is Map) {
      return Map<String, dynamic>.from(decoded[id.wireName] as Map);
    }
  } catch (_) {}
  return {};
}
