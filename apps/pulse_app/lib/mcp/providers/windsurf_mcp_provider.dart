import 'dart:io';

import 'mcp_client_provider.dart';
import 'mcp_servers_json_provider.dart';

/// Windsurf Cascade MCP registration.
///
/// Config: `%USERPROFILE%\.codeium\windsurf\mcp_config.json`
/// Shape: `{ "mcpServers": { "pulse": { command, args, env } } }` (stdio).
class WindsurfMcpProvider extends McpServersJsonProvider {
  WindsurfMcpProvider({
    super.editor,
    super.encoder,
  });

  @override
  McpClientId get id => McpClientId.windsurf;

  @override
  String get primaryConfigPath {
    final home = Platform.environment['USERPROFILE'] ?? '';
    return '$home\\.codeium\\windsurf\\mcp_config.json';
  }

  @override
  List<String> get configPaths => [primaryConfigPath];

  @override
  String get registerSuccessMessage =>
      'Registered Pulse MCP in Windsurf mcp_config.json';

  @override
  String get unregisterSuccessMessage =>
      'Removed Pulse MCP from Windsurf mcp_config.json';

  @override
  Future<McpClientDetection> detect() async {
    final home = Platform.environment['USERPROFILE'] ?? '';
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    final candidates = <String>[
      '$local\\Programs\\Windsurf\\Windsurf.exe',
      '$local\\Programs\\windsurf\\Windsurf.exe',
      '${Platform.environment['ProgramFiles'] ?? ''}\\Windsurf\\Windsurf.exe',
      '$home\\.codeium\\windsurf',
    ];
    String? found;
    for (final p in candidates) {
      if (p.isEmpty) continue;
      if (await File(p).exists() || await Directory(p).exists()) {
        found = p;
        break;
      }
    }
    final cfgExists = await File(primaryConfigPath).exists();
    if (found == null && !cfgExists) {
      final where = await Process.run('where.exe', ['windsurf']);
      if (where.exitCode == 0) {
        found = (where.stdout as String).split(RegExp(r'\r?\n')).first.trim();
      }
    }
    final installed = found != null || cfgExists;
    return McpClientDetection(
      installed: installed,
      configPath: primaryConfigPath,
      detail: installed
          ? (found ?? 'Windsurf MCP config present')
          : 'Not installed',
    );
  }
}
