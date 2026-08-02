import 'dart:io';

/// Resolved command used to launch PulseMCP (AI clients + status-daemon).
class McpLaunchCommand {
  const McpLaunchCommand({
    required this.command,
    required this.args,
    required this.display,
  });

  final String command;
  final List<String> args;
  final String display;
}

class McpLaunchResolver {
  const McpLaunchResolver();

  /// Prefer installed self-contained PulseMCP next to Pulse.exe.
  ///
  /// Production installs ship [PulseMCP.exe] + private `runtime\node.exe`.
  /// Never returns a `.cmd` launcher for AI registration — `.cmd` paths under
  /// `Program Files` are routinely broken by MCP hosts that shell out via cmd.
  Future<McpLaunchCommand?> resolve() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return resolveFromInstallDir(exeDir);
  }

  /// Resolve from an explicit install directory (tests + packaging checks).
  Future<McpLaunchCommand?> resolveFromInstallDir(String exeDir) async {
    exeDir = _preferAsciiPath(exeDir);
    final exeBeside = File('$exeDir${Platform.pathSeparator}PulseMCP.exe');
    if (await exeBeside.exists()) {
      final command = _preferAsciiPath(exeBeside.path);
      return McpLaunchCommand(
        command: command,
        args: const [],
        display: command,
      );
    }

    final runtimeNode =
        File('$exeDir${Platform.pathSeparator}runtime${Platform.pathSeparator}node.exe');
    final mainBeside =
        File('$exeDir${Platform.pathSeparator}mcp${Platform.pathSeparator}main.js');
    if (await runtimeNode.exists() && await mainBeside.exists()) {
      return McpLaunchCommand(
        command: runtimeNode.path,
        args: [mainBeside.path],
        display: '${runtimeNode.path} ${mainBeside.path}',
      );
    }

    // Legacy payload: PulseMCP.cmd only — expand to private runtime, never
    // hand the .cmd path to Cursor/Claude.
    final cmdBeside = File('$exeDir${Platform.pathSeparator}PulseMCP.cmd');
    if (await cmdBeside.exists() &&
        await runtimeNode.exists() &&
        await mainBeside.exists()) {
      return McpLaunchCommand(
        command: runtimeNode.path,
        args: [mainBeside.path],
        display: '${runtimeNode.path} ${mainBeside.path}',
      );
    }

    if (await mainBeside.exists()) {
      final node = await _findNode();
      if (node != null) {
        return McpLaunchCommand(
          command: node,
          args: [mainBeside.path],
          display: '$node ${mainBeside.path}',
        );
      }
    }

    // Dev: walk up from CWD looking for apps/pulse_mcp/dist/main.js
    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      final candidate = File(
        '${dir.path}${Platform.pathSeparator}apps${Platform.pathSeparator}pulse_mcp${Platform.pathSeparator}dist${Platform.pathSeparator}main.js',
      );
      if (await candidate.exists()) {
        final node = await _findNode();
        if (node != null) {
          return McpLaunchCommand(
            command: node,
            args: [candidate.path],
            display: '$node ${candidate.path}',
          );
        }
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  Future<String?> _findNode() async {
    final where = await Process.run('where.exe', ['node']);
    if (where.exitCode != 0) return null;
    final lines = (where.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    return lines.isEmpty ? null : lines.first;
  }

  /// Claude Desktop / some MCP hosts mishandle non-ASCII install paths
  /// (e.g. `Masaüstü` → `Masa??st??` in config). Prefer the ASCII junction
  /// `C:\dev\Pulse-src` when it points at the same tree.
  static String _preferAsciiPath(String path) {
    if (!_hasNonAscii(path)) return path;
    const asciiRoot = r'C:\dev\Pulse-src';
    final normalized = path.replaceAll('/', r'\');
    final marker = r'\Pulse\';
    final idx = normalized.toLowerCase().lastIndexOf(marker.toLowerCase());
    if (idx < 0) return path;
    final suffix = normalized.substring(idx + marker.length - 1); // keep leading \
    final candidate = '$asciiRoot$suffix';
    if (File(candidate).existsSync() || Directory(candidate).existsSync()) {
      return candidate;
    }
    // Dev Release layout: ...\Pulse\apps\pulse_app\...
    final appsIdx = normalized.toLowerCase().indexOf(r'\apps\pulse_app\');
    if (appsIdx >= 0) {
      final fromApps = normalized.substring(appsIdx);
      final alt = '$asciiRoot$fromApps';
      if (File(alt).existsSync() || Directory(alt).existsSync()) return alt;
    }
    return path;
  }

  static bool _hasNonAscii(String value) {
    for (final unit in value.codeUnits) {
      if (unit > 0x7f) return true;
    }
    return false;
  }
}
