import '../mcp_launch_resolver.dart';

enum McpClientId {
  cursor,
  claudeDesktop,
  windsurf,
  cline,
  vsCode,
}

extension McpClientIdX on McpClientId {
  String get wireName => switch (this) {
        McpClientId.cursor => 'cursor',
        McpClientId.claudeDesktop => 'claude_desktop',
        McpClientId.windsurf => 'windsurf',
        McpClientId.cline => 'cline',
        McpClientId.vsCode => 'vscode',
      };

  String get displayName => switch (this) {
        McpClientId.cursor => 'Cursor',
        McpClientId.claudeDesktop => 'Claude Desktop',
        McpClientId.windsurf => 'Windsurf',
        McpClientId.cline => 'Cline',
        McpClientId.vsCode => 'VS Code / GitHub Copilot',
      };
}

class McpClientDetection {
  const McpClientDetection({
    required this.installed,
    required this.configPath,
    required this.detail,
  });

  final bool installed;
  final String? configPath;
  final String detail;
}

class McpRegistrationResult {
  const McpRegistrationResult({
    required this.ok,
    required this.message,
    this.configPath,
    this.backupPath,
  });

  final bool ok;
  final String message;
  final String? configPath;
  final String? backupPath;
}

/// Abstraction for local stdio MCP client registration (PulseMCP.exe).
abstract class McpClientProvider {
  McpClientId get id;

  Future<McpClientDetection> detect();

  Future<bool> isRegistered(McpLaunchCommand launch);

  /// Register with explicit user consent. Must backup + validate JSON.
  Future<McpRegistrationResult> register(McpLaunchCommand launch);

  /// Unregister only if Pulse created the entry.
  Future<McpRegistrationResult> unregister();
}
