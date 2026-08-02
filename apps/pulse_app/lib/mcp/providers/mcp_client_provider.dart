import '../mcp_launch_resolver.dart';

enum McpClientId {
  cursor,
  claudeDesktop,
  chatgpt,
}

extension McpClientIdX on McpClientId {
  String get wireName => switch (this) {
        McpClientId.cursor => 'cursor',
        McpClientId.claudeDesktop => 'claude_desktop',
        McpClientId.chatgpt => 'chatgpt',
      };

  String get displayName => switch (this) {
        McpClientId.cursor => 'Cursor',
        McpClientId.claudeDesktop => 'Claude Desktop',
        McpClientId.chatgpt => 'ChatGPT',
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

/// Abstraction for AI-client MCP registration (Cursor today; others later).
abstract class McpClientProvider {
  McpClientId get id;

  Future<McpClientDetection> detect();

  Future<bool> isRegistered(McpLaunchCommand launch);

  /// Register with explicit user consent. Must backup + validate JSON.
  Future<McpRegistrationResult> register(McpLaunchCommand launch);

  /// Unregister only if Pulse created the entry.
  Future<McpRegistrationResult> unregister();
}
