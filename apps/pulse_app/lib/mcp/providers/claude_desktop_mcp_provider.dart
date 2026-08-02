import 'dart:convert';
import 'dart:io';

import '../mcp_launch_resolver.dart';
import '../mcp_paths.dart';
import 'json_config_editor.dart';
import 'mcp_client_provider.dart';

/// Claude Desktop MCP registration (`%APPDATA%\Claude\claude_desktop_config.json`).
class ClaudeDesktopMcpProvider implements McpClientProvider {
  ClaudeDesktopMcpProvider({JsonConfigEditor? editor})
      : _editor = editor ?? const JsonConfigEditor();

  static const serverKey = 'pulse';

  final JsonConfigEditor _editor;

  @override
  McpClientId get id => McpClientId.claudeDesktop;

  String get configPath {
    final appData = Platform.environment['APPDATA'] ?? '';
    return '$appData\\Claude\\claude_desktop_config.json';
  }

  @override
  Future<McpClientDetection> detect() async {
    final appData = Platform.environment['APPDATA'] ?? '';
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    final candidates = <String>[
      '$local\\AnthropicClaude\\claude.exe',
      '$local\\Programs\\claude\\Claude.exe',
      '$appData\\Claude',
    ];
    var installed = false;
    for (final p in candidates) {
      if (p.isEmpty) continue;
      if (await File(p).exists() || await Directory(p).exists()) {
        installed = true;
        break;
      }
    }
    if (!installed && await File(configPath).exists()) installed = true;
    return McpClientDetection(
      installed: installed,
      configPath: configPath,
      detail: installed
          ? 'Claude Desktop detected'
          : 'Claude Desktop not detected',
    );
  }

  @override
  Future<bool> isRegistered(McpLaunchCommand launch) async {
    final file = File(configPath);
    if (!await file.exists()) return false;
    try {
      final root = await _editor.readOrEmpty(file);
      final servers = root['mcpServers'];
      return servers is Map && servers.containsKey(serverKey);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<McpRegistrationResult> register(McpLaunchCommand launch) async {
    final file = File(configPath);
    File? backup;
    try {
      if (await file.exists()) backup = await _editor.backup(file);
      final root = await _editor.readOrEmpty(file);
      _editor.ensureMcpServers(root);
      final servers = root['mcpServers'] as Map<String, dynamic>;
      servers[serverKey] = {
        'command': launch.command,
        'args': launch.args,
      };
      await _editor.writeValidated(file, root);
      await _mark(registered: true, backupPath: backup?.path);
      return McpRegistrationResult(
        ok: true,
        message: 'Registered Pulse MCP in Claude Desktop config',
        configPath: file.path,
        backupPath: backup?.path,
      );
    } catch (e) {
      return McpRegistrationResult(
        ok: false,
        message: 'Claude Desktop registration failed: $e',
        configPath: file.path,
        backupPath: backup?.path,
      );
    }
  }

  @override
  Future<McpRegistrationResult> unregister() async {
    final marker = await _readMarker();
    if (marker['registeredByPulse'] != true) {
      return const McpRegistrationResult(
        ok: false,
        message:
            'Unregister skipped — Pulse did not create this Claude registration',
      );
    }
    final file = File(configPath);
    if (!await file.exists()) {
      await _mark(registered: false);
      return McpRegistrationResult(
        ok: true,
        message: 'Claude config already absent',
        configPath: file.path,
      );
    }
    File? backup;
    try {
      backup = await _editor.backup(file);
      final root = await _editor.readOrEmpty(file);
      final servers = root['mcpServers'];
      if (servers is Map) {
        final map = Map<String, dynamic>.from(servers);
        map.remove(serverKey);
        root['mcpServers'] = map;
      }
      await _editor.writeValidated(file, root);
      await _mark(registered: false, backupPath: backup.path);
      return McpRegistrationResult(
        ok: true,
        message: 'Removed Pulse MCP from Claude Desktop config',
        configPath: file.path,
        backupPath: backup.path,
      );
    } catch (e) {
      return McpRegistrationResult(
        ok: false,
        message: 'Claude unregister failed: $e',
        configPath: file.path,
        backupPath: backup?.path,
      );
    }
  }

  Future<void> _mark({required bool registered, String? backupPath}) async {
    final file = File(McpPaths.registrationsFile);
    Map<String, dynamic> root = {};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) root = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    root[id.wireName] = {
      'registeredByPulse': registered,
      'configPath': configPath,
      'serverKey': serverKey,
      'registeredAt': DateTime.now().toUtc().toIso8601String(),
      if (backupPath != null) 'lastBackupPath': backupPath,
    };
    final dir = Directory(McpPaths.mcpDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(root)}\n',
    );
  }

  Future<Map<String, dynamic>> _readMarker() async {
    final file = File(McpPaths.registrationsFile);
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded[id.wireName] is Map) {
        return Map<String, dynamic>.from(decoded[id.wireName] as Map);
      }
    } catch (_) {}
    return {};
  }
}
