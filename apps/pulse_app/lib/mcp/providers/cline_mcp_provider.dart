import 'dart:io';

import 'mcp_client_provider.dart';
import 'mcp_servers_json_provider.dart';

/// Cline MCP registration (VS Code extension + optional Cline CLI).
///
/// Extension (authoritative for IDE):
/// `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json`
///
/// CLI (when present):
/// `%USERPROFILE%\.cline\mcp.json`
///
/// Shape: `{ "mcpServers": { "pulse": { command, args, env, disabled } } }`
class ClineMcpProvider extends McpServersJsonProvider {
  ClineMcpProvider({
    super.editor,
    super.encoder,
  });

  static const extensionId = 'saoudrizwan.claude-dev';

  @override
  McpClientId get id => McpClientId.cline;

  String get _cliConfigPath {
    final home = Platform.environment['USERPROFILE'] ?? '';
    return '$home\\.cline\\mcp.json';
  }

  List<String> get _candidatePaths {
    final out = <String>[];
    final appData = Platform.environment['APPDATA'] ?? '';
    if (appData.isNotEmpty) {
      for (final product in const ['Code', 'Code - Insiders', 'VSCodium']) {
        out.add(
          '$appData\\$product\\User\\globalStorage\\$extensionId\\settings\\cline_mcp_settings.json',
        );
      }
    }
    out.add(_cliConfigPath);
    final seen = <String>{};
    return out.where((p) => seen.add(p.toLowerCase())).toList();
  }

  @override
  String get primaryConfigPath {
    final writable = configPaths;
    return writable.isEmpty ? _cliConfigPath : writable.first;
  }

  @override
  List<String> get configPaths {
    final out = <String>[];
    for (final path in _candidatePaths) {
      final file = File(path);
      if (file.existsSync()) {
        out.add(path);
        continue;
      }
      if (path.contains('globalStorage')) {
        final storage = Directory(file.parent.parent.path);
        if (storage.existsSync()) out.add(path);
      } else {
        final clineDir = Directory(file.parent.path);
        if (clineDir.existsSync()) out.add(path);
      }
    }
    if (out.isEmpty) out.add(_cliConfigPath);
    final seen = <String>{};
    return out.where((p) => seen.add(p.toLowerCase())).toList();
  }

  @override
  String get registerSuccessMessage =>
      'Registered Pulse MCP in Cline MCP settings';

  @override
  String get unregisterSuccessMessage =>
      'Removed Pulse MCP from Cline MCP settings';

  @override
  Map<String, dynamic> decorateServerEntry(Map<String, dynamic> entry) {
    return <String, dynamic>{
      ...entry,
      'disabled': false,
    };
  }

  @override
  Future<McpClientDetection> detect() async {
    final appData = Platform.environment['APPDATA'] ?? '';
    final home = Platform.environment['USERPROFILE'] ?? '';
    var installed = false;
    String? found;

    for (final product in const ['Code', 'Code - Insiders', 'VSCodium']) {
      final storage = Directory(
        '$appData\\$product\\User\\globalStorage\\$extensionId',
      );
      if (await storage.exists()) {
        installed = true;
        found = storage.path;
        break;
      }
    }
    final cliDir = Directory('$home\\.cline');
    if (!installed && await cliDir.exists()) {
      installed = true;
      found = cliDir.path;
    }
    if (!installed) {
      final where = await Process.run('where.exe', ['cline']);
      if (where.exitCode == 0) {
        installed = true;
        found = (where.stdout as String).split(RegExp(r'\r?\n')).first.trim();
      }
    }

    return McpClientDetection(
      installed: installed,
      configPath: primaryConfigPath,
      detail: installed ? (found ?? 'Cline detected') : 'Not installed',
    );
  }
}
