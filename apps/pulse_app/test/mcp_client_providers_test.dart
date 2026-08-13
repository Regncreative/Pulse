import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/mcp/mcp_client_config_encoder.dart';
import 'package:pulse/mcp/mcp_launch_resolver.dart';
import 'package:pulse/mcp/providers/cline_mcp_provider.dart';
import 'package:pulse/mcp/providers/cursor_mcp_provider.dart';
import 'package:pulse/mcp/providers/json_config_editor.dart';
import 'package:pulse/mcp/providers/mcp_client_provider.dart';
import 'package:pulse/mcp/providers/mcp_servers_json_provider.dart';
import 'package:pulse/mcp/providers/vscode_mcp_provider.dart';
import 'package:pulse/mcp/providers/windsurf_mcp_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late JsonConfigEditor editor;
  late McpClientConfigEncoder encoder;
  late McpLaunchCommand launch;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pulse_mcp_reg_');
    editor = const JsonConfigEditor();
    encoder = const McpClientConfigEncoder();
    launch = const McpLaunchCommand(
      command: r'C:\Program Files\Pulse\PulseMCP.exe',
      args: [],
      display: r'"C:\Program Files\Pulse\PulseMCP.exe"',
    );
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('ChatGPT is not a supported McpClientId', () {
    expect(
      McpClientId.values.map((e) => e.wireName),
      isNot(contains('chatgpt')),
    );
    expect(
      McpClientId.values.map((e) => e.displayName).toList(),
      containsAll([
        'Cursor',
        'Claude Desktop',
        'Windsurf',
        'Cline',
        'VS Code / GitHub Copilot',
      ]),
    );
  });

  test('encoder wraps Program Files paths for spaces', () {
    final entry = encoder.forAiClient(launch);
    expect(entry['command'], 'cmd.exe');
    expect(entry['args'], isA<List>());
    final args = (entry['args'] as List).cast<String>();
    expect(args.first, '/c');
    expect(args.last, contains(r'C:\Program Files\Pulse\PulseMCP.exe'));
  });

  test('VS Code encoder adds type stdio', () {
    final entry = encoder.forVsCodeClient(launch);
    expect(entry['type'], 'stdio');
    expect(entry['command'], 'cmd.exe');
  });

  test('Cursor register preserves other servers and unregister removes only Pulse',
      () async {
    final cfg = File('${tmp.path}${Platform.pathSeparator}cursor_mcp.json');
    await cfg.writeAsString(
      '{"mcpServers":{"other":{"command":"npx","args":["x"]}}}\n',
    );

    final provider = _TestCursorProvider(
      configPath: cfg.path,
      editor: editor,
      encoder: encoder,
    );

    final first = await provider.register(launch);
    expect(first.ok, isTrue);
    var root = await editor.readOrEmpty(cfg);
    expect((root['mcpServers'] as Map).containsKey('other'), isTrue);
    expect((root['mcpServers'] as Map).containsKey('pulse'), isTrue);

    final second = await provider.register(launch);
    expect(second.ok, isTrue);
    root = await editor.readOrEmpty(cfg);
    expect((root['mcpServers'] as Map).length, 2);

    final un = await provider.unregister();
    expect(un.ok, isTrue);
    root = await editor.readOrEmpty(cfg);
    expect((root['mcpServers'] as Map).containsKey('other'), isTrue);
    expect((root['mcpServers'] as Map).containsKey('pulse'), isFalse);
  });

  test('Windsurf register writes mcpServers.pulse', () async {
    final cfg = File('${tmp.path}${Platform.pathSeparator}mcp_config.json');
    await cfg.parent.create(recursive: true);
    final provider = _TestMcpServersProvider(
      idOverride: McpClientId.windsurf,
      configPath: cfg.path,
      editor: editor,
      encoder: encoder,
      registerMsg: 'Registered Pulse MCP in Windsurf mcp_config.json',
      unregisterMsg: 'Removed Pulse MCP from Windsurf mcp_config.json',
    );
    final result = await provider.register(launch);
    expect(result.ok, isTrue);
    final root = await editor.readOrEmpty(cfg);
    expect(root['mcpServers'], isA<Map>());
    expect((root['mcpServers'] as Map)['pulse'], isA<Map>());
  });

  test('Cline register merges and sets disabled false', () async {
    final cfg =
        File('${tmp.path}${Platform.pathSeparator}cline_mcp_settings.json');
    await cfg.writeAsString(
      '{"mcpServers":{"keep":{"command":"node","args":["a.js"]}}}\n',
    );
    final provider = _TestMcpServersProvider(
      idOverride: McpClientId.cline,
      configPath: cfg.path,
      editor: editor,
      encoder: encoder,
      registerMsg: 'Registered Pulse MCP in Cline MCP settings',
      unregisterMsg: 'Removed Pulse MCP from Cline MCP settings',
      decorate: (entry) => {...entry, 'disabled': false},
    );
    final result = await provider.register(launch);
    expect(result.ok, isTrue);
    final root = await editor.readOrEmpty(cfg);
    final servers = root['mcpServers'] as Map;
    expect(servers.containsKey('keep'), isTrue);
    expect(servers['pulse'], isA<Map>());
    expect((servers['pulse'] as Map)['disabled'], isFalse);
  });

  test('VS Code register uses servers key and preserves peers', () async {
    final cfg = File('${tmp.path}${Platform.pathSeparator}mcp.json');
    await cfg.writeAsString(
      '{"servers":{"github":{"type":"http","url":"https://example.test"}}}\n',
    );
    final provider = _TestVsCodeProvider(
      configPath: cfg.path,
      editor: editor,
      encoder: encoder,
    );
    final result = await provider.register(launch);
    expect(result.ok, isTrue);
    final root = await editor.readOrEmpty(cfg);
    final servers = root['servers'] as Map;
    expect(servers.containsKey('github'), isTrue);
    expect(servers['pulse'], isA<Map>());
    expect((servers['pulse'] as Map)['type'], 'stdio');

    final un = await provider.unregister();
    expect(un.ok, isTrue);
    final after = await editor.readOrEmpty(cfg);
    expect((after['servers'] as Map).containsKey('github'), isTrue);
    expect((after['servers'] as Map).containsKey('pulse'), isFalse);
  });

  test('malformed config does not crash register', () async {
    final cfg = File('${tmp.path}${Platform.pathSeparator}bad.json');
    await cfg.writeAsString('[]\n');
    final provider = _TestMcpServersProvider(
      idOverride: McpClientId.windsurf,
      configPath: cfg.path,
      editor: editor,
      encoder: encoder,
      registerMsg: 'ok',
      unregisterMsg: 'ok',
    );
    final result = await provider.register(launch);
    expect(result.ok, isFalse);
    expect(result.message.toLowerCase(), contains('failed'));
  });

  test('missing client detection does not throw', () async {
    expect(await WindsurfMcpProvider().detect(), isA<McpClientDetection>());
    expect(await ClineMcpProvider().detect(), isA<McpClientDetection>());
    expect(await VsCodeMcpProvider().detect(), isA<McpClientDetection>());
  });
}

class _TestCursorProvider extends CursorMcpProvider {
  _TestCursorProvider({
    required this.configPath,
    required JsonConfigEditor editor,
    required McpClientConfigEncoder encoder,
  }) : super(editor: editor, encoder: encoder);

  final String configPath;

  @override
  String get globalConfigPath => configPath;
}

class _TestMcpServersProvider extends McpServersJsonProvider {
  _TestMcpServersProvider({
    required this.idOverride,
    required this.configPath,
    required JsonConfigEditor editor,
    required McpClientConfigEncoder encoder,
    required this.registerMsg,
    required this.unregisterMsg,
    this._decorate,
  }) : super(editor: editor, encoder: encoder);

  final McpClientId idOverride;
  final String configPath;
  final String registerMsg;
  final String unregisterMsg;
  final Map<String, dynamic> Function(Map<String, dynamic>)? _decorate;

  @override
  McpClientId get id => idOverride;

  @override
  String get primaryConfigPath => configPath;

  @override
  List<String> get configPaths => [configPath];

  @override
  String get registerSuccessMessage => registerMsg;

  @override
  String get unregisterSuccessMessage => unregisterMsg;

  @override
  Map<String, dynamic> decorateServerEntry(Map<String, dynamic> entry) {
    return _decorate?.call(entry) ?? entry;
  }

  @override
  Future<McpClientDetection> detect() async {
    return McpClientDetection(
      installed: true,
      configPath: configPath,
      detail: 'test',
    );
  }
}

class _TestVsCodeProvider extends VsCodeMcpProvider {
  _TestVsCodeProvider({
    required this.configPath,
    required JsonConfigEditor editor,
    required McpClientConfigEncoder encoder,
  }) : super(editor: editor, encoder: encoder);

  final String configPath;

  @override
  String get primaryConfigPath => configPath;

  @override
  List<String> get configPaths => [configPath];

  @override
  List<String> get writableConfigPaths => [configPath];
}
