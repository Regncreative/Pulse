import 'dart:io';

import '../mcp_client_config_encoder.dart';
import '../mcp_launch_resolver.dart';
import 'json_config_editor.dart';
import 'mcp_client_provider.dart';
import 'mcp_registration_marker.dart';

/// Shared register/unregister for clients using top-level `mcpServers` (stdio).
abstract class McpServersJsonProvider implements McpClientProvider {
  McpServersJsonProvider({
    JsonConfigEditor? editor,
    McpClientConfigEncoder? encoder,
  })  : editor = editor ?? const JsonConfigEditor(),
        encoder = encoder ?? const McpClientConfigEncoder();

  static const serverKey = 'pulse';

  final JsonConfigEditor editor;
  final McpClientConfigEncoder encoder;

  /// Preferred path shown in Settings / markers.
  String get primaryConfigPath;

  /// All config files Pulse should keep in sync for this client.
  List<String> get configPaths;

  String get registerSuccessMessage;
  String get unregisterSuccessMessage;

  /// Optional extra fields merged into the Pulse server entry (e.g. Cline).
  Map<String, dynamic> decorateServerEntry(Map<String, dynamic> entry) => entry;

  @override
  Future<bool> isRegistered(McpLaunchCommand launch) async {
    for (final path in configPaths) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final root = await editor.readOrEmpty(file);
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
      return McpRegistrationResult(
        ok: false,
        message: '${id.displayName} config path not found',
      );
    }

    final entry = decorateServerEntry(encoder.forAiClient(launch));
    String? lastBackup;
    final written = <String>[];
    Object? lastError;

    for (final path in paths) {
      final file = File(path);
      try {
        File? backup;
        if (await file.exists()) {
          backup = await editor.backup(file);
          lastBackup = backup.path;
        } else {
          await file.parent.create(recursive: true);
        }
        final root = await editor.readOrEmpty(file);
        editor.ensureMcpServers(root);
        final servers = root['mcpServers'] as Map<String, dynamic>;
        servers[serverKey] = Map<String, dynamic>.from(entry);
        await editor.writeValidated(file, root);
        written.add(path);
      } catch (e) {
        lastError = e;
      }
    }

    if (written.isEmpty) {
      return McpRegistrationResult(
        ok: false,
        message: '${id.displayName} registration failed: $lastError',
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
          ? registerSuccessMessage
          : 'Registered Pulse MCP in ${written.length} ${id.displayName} config locations',
      configPath: written.first,
      backupPath: lastBackup,
    );
  }

  @override
  Future<McpRegistrationResult> unregister() async {
    final marker = await readMcpRegistrationMarker(id);
    if (marker['registeredByPulse'] != true) {
      return McpRegistrationResult(
        ok: false,
        message:
            'Unregister skipped — Pulse did not create this ${id.displayName} registration',
      );
    }

    String? lastBackup;
    final cleared = <String>[];
    for (final path in configPaths) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final backup = await editor.backup(file);
        lastBackup = backup.path;
        final root = await editor.readOrEmpty(file);
        final servers = root['mcpServers'];
        if (servers is Map) {
          final map = Map<String, dynamic>.from(servers);
          map.remove(serverKey);
          root['mcpServers'] = map;
        }
        await editor.writeValidated(file, root);
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
          ? '${id.displayName} config already absent'
          : unregisterSuccessMessage,
      configPath: primaryConfigPath,
      backupPath: lastBackup,
    );
  }
}
