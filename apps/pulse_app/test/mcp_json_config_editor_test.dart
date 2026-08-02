import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/mcp/providers/json_config_editor.dart';

void main() {
  test('merges mcpServers without dropping siblings', () async {
    final dir = await Directory.systemTemp.createTemp('pulse-mcp-cfg');
    final file = File('${dir.path}/mcp.json');
    await file.writeAsString('''
{
  "mcpServers": {
    "other": { "command": "x" }
  }
}
''');
    const editor = JsonConfigEditor();
    final backup = await editor.backup(file);
    expect(await backup.exists(), isTrue);

    final root = await editor.readOrEmpty(file);
    editor.ensureMcpServers(root);
    final servers = root['mcpServers'] as Map<String, dynamic>;
    servers['pulse'] = {'command': 'PulseMCP.cmd', 'args': <String>[]};
    await editor.writeValidated(file, root);

    final again = await editor.readOrEmpty(file);
    final againServers = again['mcpServers'] as Map<String, dynamic>;
    expect(againServers.containsKey('other'), isTrue);
    expect(againServers.containsKey('pulse'), isTrue);

    await dir.delete(recursive: true);
  });
}
