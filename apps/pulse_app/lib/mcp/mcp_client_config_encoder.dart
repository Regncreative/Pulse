import 'dart:io';

import 'mcp_launch_resolver.dart';

/// Builds `mcpServers` entries for AI clients (Cursor, Claude Desktop).
///
/// Cursor on Windows historically splits [McpLaunchCommand.command] on spaces
/// when launching stdio MCP servers (error: `'C:\Program' is not recognized`).
/// Default install path `C:\Program Files\Pulse\...` always hits that bug.
///
/// Fix: on Windows, when the executable path contains whitespace, register
/// `cmd.exe` with `/c` and put the full path in [args] as a single element
/// (plus any server args, quoted into one `/c` string when needed).
class McpClientConfigEncoder {
  const McpClientConfigEncoder();

  /// JSON object written under `mcpServers.pulse` (Cursor, Claude, Windsurf, Cline).
  Map<String, dynamic> forAiClient(
    McpLaunchCommand launch, {
    Map<String, String> env = const {},
  }) {
    if (Platform.isWindows && _needsWindowsCmdWrapper(launch)) {
      return <String, dynamic>{
        'command': 'cmd.exe',
        'args': _windowsCmdArgs(launch),
        'env': Map<String, String>.from(env),
      };
    }
    return <String, dynamic>{
      'command': launch.command,
      'args': List<String>.from(launch.args),
      'env': Map<String, String>.from(env),
    };
  }

  /// VS Code / GitHub Copilot `mcp.json` entry under top-level `servers`.
  ///
  /// Uses `"type": "stdio"` per current VS Code MCP schema.
  Map<String, dynamic> forVsCodeClient(
    McpLaunchCommand launch, {
    Map<String, String> env = const {},
  }) {
    final base = forAiClient(launch, env: env);
    return <String, dynamic>{
      'type': 'stdio',
      ...base,
    };
  }

  /// Whether [entry] looks like a Pulse registration for [launch]
  /// (direct path or Windows cmd.exe wrapper).
  bool matchesRegistration(
    Map<String, dynamic> entry,
    McpLaunchCommand launch,
  ) {
    final command = entry['command'];
    if (command is! String) return false;
    final args = entry['args'];
    final argList = args is List
        ? args.map((e) => e.toString()).toList()
        : const <String>[];

    if (command == launch.command) {
      return listEquals(argList, launch.args);
    }

    // cmd.exe /c … wrapper
    if (_isCmdExe(command) && argList.isNotEmpty) {
      final joined = argList.join(' ');
      if (joined.contains(launch.command)) return true;
      if (argList.any((a) => a == launch.command || a.contains(launch.command))) {
        return true;
      }
    }
    return false;
  }

  static bool _isCmdExe(String command) {
    final base = command.split(RegExp(r'[\\/]')).last.toLowerCase();
    return base == 'cmd.exe' || base == 'cmd';
  }

  static bool _needsWindowsCmdWrapper(McpLaunchCommand launch) {
    if (_hasWhitespace(launch.command) || _hasNonAscii(launch.command)) {
      return true;
    }
    return launch.args.any((a) => _hasWhitespace(a) || _hasNonAscii(a));
  }

  static bool _hasWhitespace(String value) =>
      value.contains(' ') || value.contains('\t');

  static bool _hasNonAscii(String value) {
    for (final unit in value.codeUnits) {
      if (unit > 0x7f) return true;
    }
    return false;
  }

  /// `cmd.exe /c …` — path lives in args so Cursor does not split on spaces.
  static List<String> _windowsCmdArgs(McpLaunchCommand launch) {
    if (launch.args.isEmpty) {
      // Proven Cursor workaround: full exe path is a single argv after /c.
      return <String>['/c', launch.command];
    }
    // Multiple tokens must be one /c string with each segment quoted.
    final inner = StringBuffer(_quoteWinArg(launch.command));
    for (final arg in launch.args) {
      inner.write(' ');
      inner.write(_quoteWinArg(arg));
    }
    return <String>['/c', inner.toString()];
  }

  static String _quoteWinArg(String arg) {
    if (arg.isEmpty) return '""';
    final needsQuote = _hasWhitespace(arg) || arg.contains('"');
    if (!needsQuote) return arg;
    final escaped = arg.replaceAll('"', r'\"');
    return '"$escaped"';
  }
}

bool listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
