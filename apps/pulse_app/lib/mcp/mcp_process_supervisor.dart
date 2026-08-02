import 'dart:io';

import '../logging/app_logger.dart';
import 'mcp_launch_resolver.dart';

/// Starts/stops PulseMCP `--status-daemon` when "start with Pulse" is enabled.
class McpProcessSupervisor {
  McpProcessSupervisor({
    required this.logger,
    McpLaunchResolver? resolver,
  }) : _resolver = resolver ?? const McpLaunchResolver();

  final AppLogger logger;
  final McpLaunchResolver _resolver;
  Process? _process;

  bool get isRunning => _process != null;

  Future<void> sync({required bool enabled, required bool startWithPulse}) async {
    if (enabled && startWithPulse) {
      await start();
    } else {
      await stop();
    }
  }

  Future<void> start() async {
    if (_process != null) return;
    final launch = await _resolver.resolve();
    if (launch == null) {
      logger.warn('McpSupervisor', 'PulseMCP launch command not found');
      return;
    }
    try {
      final args = [...launch.args, '--status-daemon'];
      _process = await Process.start(
        launch.command,
        args,
        mode: ProcessStartMode.normal,
      );
      logger.info(
        'McpSupervisor',
        'status-daemon started pid=${_process!.pid} cmd=${launch.display}',
      );
      _process!.exitCode.then((code) {
        logger.info('McpSupervisor', 'status-daemon exited code=$code');
        _process = null;
      });
    } catch (e) {
      logger.warn('McpSupervisor', 'status-daemon failed to start: $e');
      _process = null;
    }
  }

  Future<void> stop() async {
    final p = _process;
    _process = null;
    if (p == null) return;
    try {
      p.kill(ProcessSignal.sigterm);
    } catch (_) {
      try {
        p.kill();
      } catch (_) {}
    }
  }
}
