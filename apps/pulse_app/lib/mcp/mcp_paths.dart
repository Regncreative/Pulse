import 'dart:io';

/// Local paths for Pulse MCP policy, status, logs, and registration markers.
class McpPaths {
  McpPaths._();

  static String get localAppData {
    final env = Platform.environment['LOCALAPPDATA'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['USERPROFILE'] ?? '';
    return '$home\\AppData\\Local';
  }

  static String get mcpDir => '$localAppData\\Pulse\\mcp';

  static String get policyFile => '$mcpDir\\policy.json';

  static String get statusFile => '$mcpDir\\status.json';

  static String get registrationsFile => '$mcpDir\\client-registrations.json';

  static String get logsDir => '$localAppData\\Pulse\\logs\\pulsemcp';

  /// Docs shipped with the product (install dir) or repo docs in development.
  static String docsRelative = 'docs\\guides\\ai-integration.md';
}
