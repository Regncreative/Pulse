import 'dart:convert';
import 'dart:io';

import '../mcp_client_config_encoder.dart';
import '../mcp_launch_resolver.dart';
import '../mcp_paths.dart';
import 'json_config_editor.dart';
import 'mcp_client_provider.dart';

/// Claude Desktop MCP registration.
///
/// Classic install: `%APPDATA%\Claude\claude_desktop_config.json`
/// Microsoft Store / MSIX: `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude_desktop_config.json`
class ClaudeDesktopMcpProvider implements McpClientProvider {
  ClaudeDesktopMcpProvider({
    JsonConfigEditor? editor,
    McpClientConfigEncoder? encoder,
  })  : _editor = editor ?? const JsonConfigEditor(),
        _encoder = encoder ?? const McpClientConfigEncoder();

  static const serverKey = 'pulse';

  final JsonConfigEditor _editor;
  final McpClientConfigEncoder _encoder;

  @override
  McpClientId get id => McpClientId.claudeDesktop;

  /// Preferred config path for UI / markers (Store package wins when present).
  String get configPath {
    final paths = configPaths;
    return paths.isEmpty
        ? '${Platform.environment['APPDATA'] ?? ''}\\Claude\\claude_desktop_config.json'
        : paths.first;
  }

  /// All Claude config locations that Pulse should keep in sync.
  List<String> get configPaths {
    final out = <String>[];
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    final appData = Platform.environment['APPDATA'] ?? '';

    if (local.isNotEmpty) {
      final packages = Directory('$local\\Packages');
      if (packages.existsSync()) {
        for (final entity in packages.listSync()) {
          if (entity is! Directory) continue;
          final name = entity.uri.pathSegments.isEmpty
              ? entity.path.split(Platform.pathSeparator).last
              : entity.path.split(Platform.pathSeparator).last;
          if (!name.toLowerCase().startsWith('claude_')) continue;
          final cfg =
              '${entity.path}\\LocalCache\\Roaming\\Claude\\claude_desktop_config.json';
          out.add(cfg);
        }
      }
    }

    if (appData.isNotEmpty) {
      out.add('$appData\\Claude\\claude_desktop_config.json');
    }

    // De-dupe while preserving order (Store first).
    final seen = <String>{};
    return out.where((p) => seen.add(p.toLowerCase())).toList();
  }

  @override
  Future<McpClientDetection> detect() async {
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    final appData = Platform.environment['APPDATA'] ?? '';
    final candidates = <String>[
      ...configPaths,
      '$local\\AnthropicClaude\\claude.exe',
      '$local\\Programs\\claude\\Claude.exe',
      '$appData\\Claude',
    ];
    // WindowsApps package folder (Store install).
    if (local.isNotEmpty) {
      final packages = Directory('$local\\Packages');
      if (await packages.exists()) {
        await for (final entity in packages.list()) {
          if (entity is Directory &&
              entity.path.toLowerCase().contains('\\packages\\claude_')) {
            candidates.add(entity.path);
          }
        }
      }
    }

    var installed = false;
    String? found;
    for (final p in candidates) {
      if (p.isEmpty) continue;
      if (await File(p).exists() || await Directory(p).exists()) {
        installed = true;
        found = p;
        break;
      }
    }
    return McpClientDetection(
      installed: installed,
      configPath: configPath,
      detail: installed
          ? (found != null && found.toLowerCase().contains('\\packages\\claude_')
              ? 'Claude Desktop (Microsoft Store) detected'
              : 'Claude Desktop detected')
          : 'Claude Desktop not detected',
    );
  }

  @override
  Future<bool> isRegistered(McpLaunchCommand launch) async {
    for (final path in configPaths) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final root = await _editor.readOrEmpty(file);
        final servers = root['mcpServers'];
        if (servers is Map && servers.containsKey(serverKey)) return true;
      } catch (_) {}
    }
    return false;
  }

  @override
  Future<McpRegistrationResult> register(McpLaunchCommand launch) async {
    final paths = configPaths;
    if (paths.isEmpty) {
      return const McpRegistrationResult(
        ok: false,
        message: 'Claude Desktop config path not found',
      );
    }

    final entry = _encoder.forAiClient(launch);
    final pulseEntry = <String, dynamic>{
      'command': entry['command'],
      'args': entry['args'],
    };

    String? lastBackup;
    final written = <String>[];
    Object? lastError;

    for (final path in paths) {
      final file = File(path);
      try {
        File? backup;
        if (await file.exists()) {
          backup = await _editor.backup(file);
          lastBackup = backup.path;
        } else {
          await file.parent.create(recursive: true);
        }
        final root = await _editor.readOrEmpty(file);
        _editor.ensureMcpServers(root);
        final servers = root['mcpServers'] as Map<String, dynamic>;
        servers[serverKey] = Map<String, dynamic>.from(pulseEntry);
        await _editor.writeValidated(file, root);
        written.add(path);
      } catch (e) {
        lastError = e;
      }
    }

    if (written.isEmpty) {
      return McpRegistrationResult(
        ok: false,
        message: 'Claude Desktop registration failed: $lastError',
        configPath: configPath,
        backupPath: lastBackup,
      );
    }

    await _mark(registered: true, backupPath: lastBackup, paths: written);
    return McpRegistrationResult(
      ok: true,
      message: written.length == 1
          ? 'Registered Pulse MCP in Claude Desktop config'
          : 'Registered Pulse MCP in ${written.length} Claude config locations (Store + classic)',
      configPath: written.first,
      backupPath: lastBackup,
    );
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

    String? lastBackup;
    final cleared = <String>[];

    for (final path in configPaths) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final backup = await _editor.backup(file);
        lastBackup = backup.path;
        final root = await _editor.readOrEmpty(file);
        final servers = root['mcpServers'];
        if (servers is Map) {
          final map = Map<String, dynamic>.from(servers);
          map.remove(serverKey);
          root['mcpServers'] = map;
        }
        await _editor.writeValidated(file, root);
        cleared.add(path);
      } catch (_) {}
    }

    await _mark(registered: false, backupPath: lastBackup, paths: cleared);
    return McpRegistrationResult(
      ok: true,
      message: cleared.isEmpty
          ? 'Claude config already absent'
          : 'Removed Pulse MCP from Claude Desktop config',
      configPath: configPath,
      backupPath: lastBackup,
    );
  }

  Future<void> _mark({
    required bool registered,
    String? backupPath,
    List<String>? paths,
  }) async {
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
      'configPaths': paths ?? configPaths,
      'serverKey': serverKey,
      'registeredAt': DateTime.now().toUtc().toIso8601String(),
      'lastBackupPath': ?backupPath,
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
