import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/mcp/mcp_client_config_encoder.dart';
import 'package:pulse/mcp/mcp_launch_resolver.dart';
import 'package:pulse/mcp/providers/json_config_editor.dart';

void main() {
  const encoder = McpClientConfigEncoder();

  test('Program Files PulseMCP.exe uses cmd.exe /c wrapper on Windows', () {
    const launch = McpLaunchCommand(
      command: r'C:\Program Files\Pulse\PulseMCP.exe',
      args: [],
      display: r'C:\Program Files\Pulse\PulseMCP.exe',
    );
    final entry = encoder.forAiClient(launch);
    if (Platform.isWindows) {
      expect(entry['command'], 'cmd.exe');
      expect(entry['args'], [r'/c', r'C:\Program Files\Pulse\PulseMCP.exe']);
      expect(entry['env'], isA<Map>());
    } else {
      expect(entry['command'], launch.command);
      expect(entry['args'], isEmpty);
    }
  });

  test('Program Files node + main.js quotes both paths in one /c string', () {
    const launch = McpLaunchCommand(
      command: r'C:\Program Files\Pulse\runtime\node.exe',
      args: [r'C:\Program Files\Pulse\mcp\main.js'],
      display: 'node main',
    );
    final entry = encoder.forAiClient(launch);
    if (Platform.isWindows) {
      expect(entry['command'], 'cmd.exe');
      final args = entry['args'] as List;
      expect(args.first, '/c');
      expect(args.length, 2);
      final c = args[1] as String;
      expect(c, contains(r'C:\Program Files\Pulse\runtime\node.exe'));
      expect(c, contains(r'C:\Program Files\Pulse\mcp\main.js'));
      expect(c.startsWith('"'), isTrue);
    }
  });

  test('path without spaces stays direct command + args', () {
    const launch = McpLaunchCommand(
      command: r'C:\Pulse\PulseMCP.exe',
      args: [],
      display: r'C:\Pulse\PulseMCP.exe',
    );
    final entry = encoder.forAiClient(launch);
    expect(entry['command'], r'C:\Pulse\PulseMCP.exe');
    expect(entry['args'], isEmpty);
  });

  test('Cursor-shaped mcp.json round-trip keeps Program Files wrapper', () async {
    final dir = await Directory.systemTemp.createTemp('pulse-mcp-progfiles');
    final file = File('${dir.path}/mcp.json');
    const launch = McpLaunchCommand(
      command: r'C:\Program Files\Pulse\PulseMCP.exe',
      args: [],
      display: r'C:\Program Files\Pulse\PulseMCP.exe',
    );
    const editor = JsonConfigEditor();
    final root = <String, dynamic>{};
    editor.ensureMcpServers(root);
    final servers = root['mcpServers'] as Map<String, dynamic>;
    servers['pulse'] = encoder.forAiClient(launch);
    servers['other'] = {'command': 'x', 'args': <String>[]};
    await editor.writeValidated(file, root);

    final again = await editor.readOrEmpty(file);
    final pulse = (again['mcpServers'] as Map)['pulse'] as Map;
    if (Platform.isWindows) {
      expect(pulse['command'], 'cmd.exe');
      expect(pulse['args'], [r'/c', r'C:\Program Files\Pulse\PulseMCP.exe']);
    }
    expect((again['mcpServers'] as Map).containsKey('other'), isTrue);
    await dir.delete(recursive: true);
  });

  test('matchesRegistration accepts cmd wrapper', () {
    const launch = McpLaunchCommand(
      command: r'C:\Program Files\Pulse\PulseMCP.exe',
      args: [],
      display: 'x',
    );
    final entry = encoder.forAiClient(launch);
    expect(encoder.matchesRegistration(entry, launch), isTrue);
  });
}
