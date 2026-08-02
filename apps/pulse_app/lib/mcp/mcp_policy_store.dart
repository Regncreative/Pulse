import 'dart:convert';
import 'dart:io';

import 'mcp_paths.dart';

/// Writes/reads `%LOCALAPPDATA%\Pulse\mcp\policy.json` (PulseMCP SSOT).
class McpPolicyStore {
  const McpPolicyStore();

  Future<bool> readEnabled() async {
    final file = File(McpPaths.policyFile);
    if (!await file.exists()) return false;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map && raw['enabled'] == true) return true;
    } catch (_) {
      // Corrupt policy → treat as disabled.
    }
    return false;
  }

  Future<void> writeEnabled(bool enabled) async {
    final dir = Directory(McpPaths.mcpDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(McpPaths.policyFile);
    final payload = <String, dynamic>{
      'enabled': enabled,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString('${const JsonEncoder.withIndent('  ').convert(payload)}\n');
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }
}
