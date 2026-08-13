import 'dart:io';

import '../mcp_client_config_encoder.dart';
import '../mcp_launch_resolver.dart';
import 'json_config_editor.dart';
import 'mcp_client_provider.dart';
import 'mcp_registration_marker.dart';

/// Visual Studio Code / GitHub Copilot Agent MCP registration (user profile).
///
/// Config: `%APPDATA%\Code\User\mcp.json` (also Insiders / VSCodium when present).
/// Shape: `{ "servers": { "pulse": { "type": "stdio", "command", "args", "env" } } }`
///
/// Workspace `.vscode/mcp.json` is intentionally not written — Register is
/// user-global so Copilot Agent mode can use Pulse across projects.
class VsCodeMcpProvider implements McpClientProvider {
  VsCodeMcpProvider({
    JsonConfigEditor? editor,
    McpClientConfigEncoder? encoder,
  })  : _editor = editor ?? const JsonConfigEditor(),
        _encoder = encoder ?? const McpClientConfigEncoder();

  static const serverKey = 'pulse';

  final JsonConfigEditor _editor;
  final McpClientConfigEncoder _encoder;

  @override
  McpClientId get id => McpClientId.vsCode;

  String get primaryConfigPath {
    final paths = configPaths;
    return paths.isEmpty
        ? '${Platform.environment['APPDATA'] ?? ''}\\Code\\User\\mcp.json'
        : paths.first;
  }

  List<String> get configPaths {
    final appData = Platform.environment['APPDATA'] ?? '';
    if (appData.isEmpty) return const [];
    final out = <String>[
      '$appData\\Code\\User\\mcp.json',
      '$appData\\Code - Insiders\\User\\mcp.json',
      '$appData\\VSCodium\\User\\mcp.json',
    ];
    final seen = <String>{};
    return out.where((p) => seen.add(p.toLowerCase())).toList();
  }

  /// Prefer writing only where the editor user folder already exists.
  List<String> get writableConfigPaths {
    final out = <String>[];
    for (final path in configPaths) {
      final userDir = Directory(File(path).parent.path);
      if (userDir.existsSync() || File(path).existsSync()) {
        out.add(path);
      }
    }
    if (out.isEmpty && configPaths.isNotEmpty) {
      out.add(configPaths.first);
    }
    return out;
  }

  @override
  Future<McpClientDetection> detect() async {
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    final appData = Platform.environment['APPDATA'] ?? '';
    final candidates = <String>[
      '$local\\Programs\\Microsoft VS Code\\Code.exe',
      '$local\\Programs\\Microsoft VS Code Insiders\\Code - Insiders.exe',
      '${Platform.environment['ProgramFiles'] ?? ''}\\Microsoft VS Code\\Code.exe',
      '$appData\\Code',
      '$appData\\Code - Insiders',
    ];
    String? found;
    for (final p in candidates) {
      if (p.isEmpty) continue;
      if (await File(p).exists() || await Directory(p).exists()) {
        found = p;
        break;
      }
    }
    if (found == null) {
      final where = await Process.run('where.exe', ['code']);
      if (where.exitCode == 0) {
        found = (where.stdout as String).split(RegExp(r'\r?\n')).first.trim();
      }
    }
    final installed = found != null;
    return McpClientDetection(
      installed: installed,
      configPath: primaryConfigPath,
      detail: found ?? 'Not installed',
    );
  }

  @override
  Future<bool> isRegistered(McpLaunchCommand launch) async {
    for (final path in configPaths) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final root = await _editor.readOrEmpty(file);
        final servers = root['servers'];
        if (servers is Map && servers.containsKey(serverKey)) return true;
      } catch (_) {}
    }
    return false;
  }

  @override
  Future<McpRegistrationResult> register(McpLaunchCommand launch) async {
    final paths = writableConfigPaths;
    if (paths.isEmpty) {
      return const McpRegistrationResult(
        ok: false,
        message: 'VS Code user MCP config path not found',
      );
    }

    final entry = _encoder.forVsCodeClient(launch);
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
        _editor.ensureVsCodeServers(root);
        final servers = root['servers'] as Map<String, dynamic>;
        servers[serverKey] = Map<String, dynamic>.from(entry);
        await _editor.writeValidated(file, root);
        written.add(path);
      } catch (e) {
        lastError = e;
      }
    }

    if (written.isEmpty) {
      return McpRegistrationResult(
        ok: false,
        message: 'VS Code registration failed: $lastError',
        configPath: primaryConfigPath,
        backupPath: lastBackup,
      );
    }

    await writeMcpRegistrationMarker(
      id: id,
      registered: true,
      configPath: written.first,
      configPaths: written,
      serverKey: serverKey,
      backupPath: lastBackup,
    );
    return McpRegistrationResult(
      ok: true,
      message: written.length == 1
          ? 'Registered Pulse MCP in VS Code user mcp.json'
          : 'Registered Pulse MCP in ${written.length} VS Code mcp.json locations',
      configPath: written.first,
      backupPath: lastBackup,
    );
  }

  @override
  Future<McpRegistrationResult> unregister() async {
    final marker = await readMcpRegistrationMarker(id);
    if (marker['registeredByPulse'] != true) {
      return const McpRegistrationResult(
        ok: false,
        message:
            'Unregister skipped — Pulse did not create this VS Code registration',
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
        final servers = root['servers'];
        if (servers is Map) {
          final map = Map<String, dynamic>.from(servers);
          map.remove(serverKey);
          root['servers'] = map;
        }
        await _editor.writeValidated(file, root);
        cleared.add(path);
      } catch (_) {}
    }

    await writeMcpRegistrationMarker(
      id: id,
      registered: false,
      configPath: primaryConfigPath,
      configPaths: cleared,
      serverKey: serverKey,
      backupPath: lastBackup,
    );
    return McpRegistrationResult(
      ok: true,
      message: cleared.isEmpty
          ? 'VS Code MCP config already absent'
          : 'Removed Pulse MCP from VS Code user mcp.json',
      configPath: primaryConfigPath,
      backupPath: lastBackup,
    );
  }
}
