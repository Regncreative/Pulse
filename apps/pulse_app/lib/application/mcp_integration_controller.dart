import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';
import '../mcp/mcp_launch_resolver.dart';
import '../mcp/mcp_paths.dart';
import '../mcp/mcp_policy_store.dart';
import '../mcp/mcp_process_supervisor.dart';
import '../mcp/mcp_status.dart';
import '../mcp/providers/chatgpt_mcp_provider.dart';
import '../mcp/providers/claude_desktop_mcp_provider.dart';
import '../mcp/providers/cursor_mcp_provider.dart';
import '../mcp/providers/mcp_client_provider.dart';

/// Settings + Diagnostics surface for Pulse MCP productization (M7).
class McpIntegrationController extends ChangeNotifier {
  McpIntegrationController({
    required this.logger,
    McpPolicyStore? policyStore,
    McpStatusReader? statusReader,
    McpLaunchResolver? launchResolver,
    McpProcessSupervisor? supervisor,
    List<McpClientProvider>? providers,
  })  : _policyStore = policyStore ?? const McpPolicyStore(),
        _statusReader = statusReader ?? const McpStatusReader(),
        _launchResolver = launchResolver ?? const McpLaunchResolver(),
        _supervisor = supervisor ??
            McpProcessSupervisor(logger: logger),
        _providers = providers ??
            [
              CursorMcpProvider(),
              ClaudeDesktopMcpProvider(),
              const ChatGptMcpProvider(),
            ];

  static const _kEnabled = 'mcp.bridge_enabled';
  static const _kStartWithPulse = 'mcp.start_with_pulse';

  final AppLogger logger;
  final McpPolicyStore _policyStore;
  final McpStatusReader _statusReader;
  final McpLaunchResolver _launchResolver;
  final McpProcessSupervisor _supervisor;
  final List<McpClientProvider> _providers;

  SharedPreferences? _prefs;
  bool ready = false;
  bool enabled = false;
  bool startWithPulse = false;
  McpStatusSnapshot status = McpStatusSnapshot.offline();
  McpLaunchCommand? launchCommand;
  final Map<McpClientId, McpClientDetection> detections = {};
  final Map<McpClientId, bool> registered = {};
  String? lastMessage;
  bool busy = false;

  List<McpClientProvider> get providers => List.unmodifiable(_providers);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    enabled = _prefs?.getBool(_kEnabled) ?? false;
    startWithPulse = _prefs?.getBool(_kStartWithPulse) ?? false;
    // Policy file is SSOT for PulseMCP; prefs mirror UX.
    final fileEnabled = await _policyStore.readEnabled();
    if (fileEnabled != enabled) {
      enabled = fileEnabled;
      await _prefs?.setBool(_kEnabled, enabled);
    }
    launchCommand = await _launchResolver.resolve();
    await refreshStatus();
    await refreshClientState();
    await _supervisor.sync(enabled: enabled, startWithPulse: startWithPulse);
    ready = true;
    notifyListeners();
  }

  Future<void> refreshStatus() async {
    status = await _statusReader.read();
    notifyListeners();
  }

  Future<void> refreshClientState() async {
    launchCommand ??= await _launchResolver.resolve();
    for (final p in _providers) {
      detections[p.id] = await p.detect();
      if (launchCommand != null) {
        registered[p.id] = await p.isRegistered(launchCommand!);
      } else {
        registered[p.id] = false;
      }
    }
    notifyListeners();
  }

  Future<String?> setEnabled(bool value) async {
    busy = true;
    notifyListeners();
    try {
      enabled = value;
      await _prefs?.setBool(_kEnabled, value);
      await _policyStore.writeEnabled(value);
      if (!value) {
        // Turning off also stops status-daemon.
        await _supervisor.sync(enabled: false, startWithPulse: false);
      } else {
        await _supervisor.sync(
          enabled: true,
          startWithPulse: startWithPulse,
        );
      }
      await refreshStatus();
      lastMessage = value
          ? 'Pulse MCP enabled'
          : 'Pulse MCP disabled — AI tools return POLICY_DISABLED';
      return lastMessage;
    } catch (e) {
      lastMessage = 'Failed to update MCP policy: $e';
      return lastMessage;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> setStartWithPulse(bool value) async {
    busy = true;
    notifyListeners();
    try {
      startWithPulse = value;
      await _prefs?.setBool(_kStartWithPulse, value);
      await _supervisor.sync(enabled: enabled, startWithPulse: value);
      await refreshStatus();
      lastMessage = value
          ? 'Pulse MCP will start a status heartbeat with Pulse'
          : 'Pulse MCP auto-start with Pulse disabled';
      return lastMessage;
    } catch (e) {
      lastMessage = 'Failed to update auto-start: $e';
      return lastMessage;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<McpRegistrationResult> registerClient(McpClientId id) async {
    busy = true;
    notifyListeners();
    try {
      final launch = launchCommand ?? await _launchResolver.resolve();
      if (launch == null) {
        return const McpRegistrationResult(
          ok: false,
          message:
              'PulseMCP binary not found. Install Pulse or build apps/pulse_mcp.',
        );
      }
      launchCommand = launch;
      final provider = _providers.firstWhere((p) => p.id == id);
      final detection = await provider.detect();
      if (!detection.installed && id != McpClientId.chatgpt) {
        // Still allow writing global config if path is known (Cursor soft path).
        if (detection.configPath == null) {
          return McpRegistrationResult(
            ok: false,
            message: '${id.displayName} is not installed',
          );
        }
      }
      final result = await provider.register(launch);
      lastMessage = result.message;
      await refreshClientState();
      return result;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<McpRegistrationResult> unregisterClient(McpClientId id) async {
    busy = true;
    notifyListeners();
    try {
      final provider = _providers.firstWhere((p) => p.id == id);
      final result = await provider.unregister();
      lastMessage = result.message;
      await refreshClientState();
      return result;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> openLogs() async {
    final dir = Directory(status.logPath ?? McpPaths.logsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await Process.start('explorer.exe', [dir.path]);
  }

  Future<void> openDocumentation() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '$exeDir\\docs\\guides\\ai-integration.md',
      '${Directory.current.path}\\docs\\guides\\ai-integration.md',
      '${Directory.current.path}\\..\\..\\docs\\guides\\ai-integration.md',
    ];
    for (final p in candidates) {
      final f = File(p);
      if (await f.exists()) {
        await Process.start('explorer.exe', [f.path]);
        return;
      }
    }
    // Fallback: open docs folder if present
    final docs = Directory('$exeDir\\docs');
    if (await docs.exists()) {
      await Process.start('explorer.exe', [docs.path]);
      return;
    }
    await Process.start('explorer.exe', [McpPaths.mcpDir]);
  }

  Future<void> disposeSupervisor() async {
    await _supervisor.stop();
  }
}
