import 'dart:convert';
import 'dart:io';

import '../mcp_launch_resolver.dart';
import '../mcp_paths.dart';
import 'json_config_editor.dart';
import 'mcp_client_provider.dart';

/// Cursor global MCP registration (`%USERPROFILE%\.cursor\mcp.json`).
class CursorMcpProvider implements McpClientProvider {
  CursorMcpProvider({JsonConfigEditor? editor})
      : _editor = editor ?? const JsonConfigEditor();

  static const serverKey = 'pulse';

  final JsonConfigEditor _editor;

  @override
  McpClientId get id => McpClientId.cursor;

  String get globalConfigPath {
    final home = Platform.environment['USERPROFILE'] ?? '';
    return '$home\\.cursor\\mcp.json';
  }

  @override
  Future<McpClientDetection> detect() async {
    final home = Platform.environment['USERPROFILE'] ?? '';
    final candidates = <String>[
      '$home\\AppData\\Local\\Programs\\cursor\\Cursor.exe',
      '$home\\AppData\\Local\\Programs\\Cursor\\Cursor.exe',
      '${Platform.environment['LOCALAPPDATA'] ?? ''}\\Programs\\cursor\\Cursor.exe',
      '${Platform.environment['ProgramFiles'] ?? ''}\\Cursor\\Cursor.exe',
    ];
    String? found;
    for (final p in candidates) {
      if (p.isEmpty) continue;
      if (await File(p).exists()) {
        found = p;
        break;
      }
    }
    // Also treat existing global mcp.json as Cursor present.
    final cfg = File(globalConfigPath);
    final cfgExists = await cfg.exists();
    if (found == null && !cfgExists) {
      // Soft detect via where
      final where = await Process.run('where.exe', ['cursor']);
      if (where.exitCode == 0) {
        found = (where.stdout as String).split(RegExp(r'\r?\n')).first.trim();
      }
    }
    final installed = found != null || cfgExists;
    return McpClientDetection(
      installed: installed,
      configPath: globalConfigPath,
      detail: installed
          ? (found ?? 'Cursor config present')
          : 'Cursor installation not detected',
    );
  }

  @override
  Future<bool> isRegistered(McpLaunchCommand launch) async {
    final file = File(globalConfigPath);
    if (!await file.exists()) return false;
    try {
      final root = await _editor.readOrEmpty(file);
      final servers = root['mcpServers'];
      if (servers is! Map) return false;
      return servers.containsKey(serverKey);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<McpRegistrationResult> register(McpLaunchCommand launch) async {
    final file = File(globalConfigPath);
    File? backup;
    try {
      if (await file.exists()) {
        backup = await _editor.backup(file);
      }
      final root = await _editor.readOrEmpty(file);
      _editor.ensureMcpServers(root);
      final servers = root['mcpServers'] as Map<String, dynamic>;
      servers[serverKey] = <String, dynamic>{
        'command': launch.command,
        'args': launch.args,
        'env': <String, String>{
          // Policy file is SSOT; env left empty so Settings toggle controls enablement.
        },
      };
      await _editor.writeValidated(file, root);
      await _markRegistration(registered: true, backupPath: backup?.path);
      return McpRegistrationResult(
        ok: true,
        message: 'Registered Pulse MCP in Cursor global config',
        configPath: file.path,
        backupPath: backup?.path,
      );
    } on FormatException catch (e) {
      return McpRegistrationResult(
        ok: false,
        message: 'Invalid Cursor MCP JSON: ${e.message}. Restored from backup if available.',
        configPath: file.path,
        backupPath: backup?.path,
      );
    } catch (e) {
      return McpRegistrationResult(
        ok: false,
        message: 'Cursor registration failed: $e',
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
            'Unregister skipped — Pulse did not create this Cursor registration',
      );
    }
    final file = File(globalConfigPath);
    if (!await file.exists()) {
      await _markRegistration(registered: false);
      return McpRegistrationResult(
        ok: true,
        message: 'Cursor MCP config already absent',
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
      await _markRegistration(registered: false, backupPath: backup.path);
      return McpRegistrationResult(
        ok: true,
        message: 'Removed Pulse MCP from Cursor global config',
        configPath: file.path,
        backupPath: backup.path,
      );
    } catch (e) {
      return McpRegistrationResult(
        ok: false,
        message: 'Cursor unregister failed: $e',
        configPath: file.path,
        backupPath: backup?.path,
      );
    }
  }

  Future<void> _markRegistration({
    required bool registered,
    String? backupPath,
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
      'configPath': globalConfigPath,
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
