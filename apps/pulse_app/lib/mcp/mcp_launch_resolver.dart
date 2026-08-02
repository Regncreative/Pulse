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
  /// Production installs ship [PulseMCP.exe] + private `runtime\node.exe`
  /// and never require a system Node.js on PATH.
  Future<McpLaunchCommand?> resolve() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    final exeBeside = File('$exeDir\\PulseMCP.exe');
    if (await exeBeside.exists()) {
      return McpLaunchCommand(
        command: exeBeside.path,
        args: const [],
        display: exeBeside.path,
      );
    }

    final runtimeNode = File('$exeDir\\runtime\\node.exe');
    final mainBeside = File('$exeDir\\mcp\\main.js');
    if (await runtimeNode.exists() && await mainBeside.exists()) {
      return McpLaunchCommand(
        command: runtimeNode.path,
        args: [mainBeside.path],
        display: '${runtimeNode.path} ${mainBeside.path}',
      );
    }

    final cmdBeside = File('$exeDir\\PulseMCP.cmd');
    if (await cmdBeside.exists()) {
      return McpLaunchCommand(
        command: cmdBeside.path,
        args: const [],
        display: cmdBeside.path,
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
      final candidate = File('${dir.path}\\apps\\pulse_mcp\\dist\\main.js');
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
}
