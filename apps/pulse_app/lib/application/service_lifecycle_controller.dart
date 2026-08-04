import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';
import '../platform/pulse_service_launcher.dart';
import '../platform/pulse_service_scm.dart';

/// Shared PulseService SCM lifecycle for Diagnostics + first-run recovery.
///
/// IPC connectivity stays in [PulseIpcClient]. This controller only manages
/// Windows service install/start/stop/restart and exposes human-readable copy.
class ServiceLifecycleController extends ChangeNotifier {
  ServiceLifecycleController({
    required this.logger,
    this._scm = const WindowsPulseServiceScm(),
    this._launcher = const WindowsPulseServiceLauncher(),
  });

  final AppLogger logger;
  final PulseServiceScm _scm;
  final PulseServiceLauncher _launcher;

  PulseServiceScmSnapshot _snapshot = const PulseServiceScmSnapshot(
    state: PulseServiceScmState.unknown,
  );
  bool actionBusy = false;
  String? lastError;
  String? lastSuccess;
  Timer? _pollTimer;
  bool _started = false;

  PulseServiceScmState get state => _snapshot.state;
  PulseServiceScmSnapshot get snapshot => _snapshot;

  bool get canStart =>
      !actionBusy &&
      (state == PulseServiceScmState.stopped ||
          state == PulseServiceScmState.unknown);

  bool get canStop => !actionBusy && state == PulseServiceScmState.running;

  bool get canRestart => !actionBusy && state == PulseServiceScmState.running;

  bool get canRepair =>
      !actionBusy && state == PulseServiceScmState.notInstalled;

  bool get isTransitioning =>
      state == PulseServiceScmState.startPending ||
      state == PulseServiceScmState.stopPending;

  String get statusLabel => _snapshot.label;

  /// Level-1 explanation for offline / recovery surfaces.
  String get recoveryTitle => switch (state) {
        PulseServiceScmState.notInstalled => 'PulseService is not installed',
        PulseServiceScmState.stopped => 'PulseService is stopped',
        PulseServiceScmState.startPending => 'PulseService is starting…',
        PulseServiceScmState.stopPending => 'PulseService is stopping…',
        PulseServiceScmState.running => 'PulseService is running',
        PulseServiceScmState.unknown => 'PulseService is not available',
      };

  String get recoveryMessage => switch (state) {
        PulseServiceScmState.notInstalled =>
          'Pulse needs its Windows service to observe Event Log activity on this PC. '
              'The service is not registered yet — repair the install to continue.',
        PulseServiceScmState.stopped =>
          'Pulse is ready, but PulseService is not running. Timeline, System Health, '
              'and Diagnostics need the service to connect over a local named pipe.',
        PulseServiceScmState.startPending =>
          'Windows is starting PulseService. Pulse will connect automatically when it is ready.',
        PulseServiceScmState.stopPending =>
          'Windows is stopping PulseService. Timeline and Health will go offline until it runs again.',
        PulseServiceScmState.running =>
          'PulseService is running. If the app still shows Offline, wait a moment for the local connection.',
        PulseServiceScmState.unknown =>
          'Pulse could not determine the Windows service state. You can try starting '
              'PulseService, or open Diagnostics for more detail.',
      };

  String? get primaryActionLabel => switch (state) {
        PulseServiceScmState.notInstalled => 'Repair / Install service',
        PulseServiceScmState.stopped || PulseServiceScmState.unknown =>
          'Start PulseService',
        _ => null,
      };

  void startPolling({Duration interval = const Duration(seconds: 2)}) {
    if (_started) return;
    _started = true;
    refresh();
    _pollTimer = Timer.periodic(interval, (_) => refresh());
  }

  void stopPolling() {
    _started = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void refresh() {
    try {
      _snapshot = _scm.query();
      notifyListeners();
    } catch (e) {
      logger.warn('ServiceLifecycle', 'SCM query failed: $e');
      _snapshot = const PulseServiceScmSnapshot(
        state: PulseServiceScmState.unknown,
      );
      notifyListeners();
    }
  }

  Future<void> startService() => _runAction(
        label: 'start',
        action: () async {
          if (state == PulseServiceScmState.notInstalled) {
            return _elevated('--install-start');
          }
          final code = await _elevated('--start');
          if (code == 2) {
            // Not installed — fall through to repair.
            return _elevated('--install-start');
          }
          return code;
        },
        successMessage: 'PulseService started. Connecting…',
      );

  Future<void> stopService() => _runAction(
        label: 'stop',
        action: () => _elevated('--stop'),
        successMessage:
            'PulseService stopped. Timeline and Health are offline until it starts again.',
      );

  Future<void> restartService() => _runAction(
        label: 'restart',
        action: () => _elevated('--restart'),
        successMessage: 'PulseService restarted. Reconnecting…',
      );

  Future<void> repairInstall() => _runAction(
        label: 'install-start',
        action: () => _elevated('--install-start'),
        successMessage: 'PulseService installed and started. Connecting…',
      );

  /// Runs the recovery primary action for the current SCM state.
  Future<void> runPrimaryRecoveryAction() async {
    if (state == PulseServiceScmState.notInstalled) {
      await repairInstall();
      return;
    }
    if (state == PulseServiceScmState.stopped ||
        state == PulseServiceScmState.unknown) {
      await startService();
    }
  }

  Future<int> _elevated(String args) => _launcher.runElevated(args);

  Future<void> _runAction({
    required String label,
    required Future<int> Function() action,
    required String successMessage,
  }) async {
    if (actionBusy) {
      throw StateError('Another service action is already running.');
    }
    actionBusy = true;
    lastError = null;
    lastSuccess = null;
    notifyListeners();
    logger.info('ServiceLifecycle', 'Begin $label');
    try {
      final code = await action();
      refresh();
      if (code != 0) {
        lastError = _messageForExitCode(code, label);
        logger.warn('ServiceLifecycle', '$label failed exit=$code');
        throw StateError(lastError!);
      }
      lastSuccess = successMessage;
      logger.info('ServiceLifecycle', '$label succeeded');
      // Poll briefly so pending → running transitions refresh the UI.
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        refresh();
        if (state == PulseServiceScmState.running ||
            state == PulseServiceScmState.stopped ||
            state == PulseServiceScmState.notInstalled) {
          break;
        }
      }
    } on PulseServiceLaunchException catch (e) {
      lastError = e.message;
      logger.warn('ServiceLifecycle', '$label launch error: ${e.message}');
      rethrow;
    } catch (e) {
      lastError ??= e.toString();
      rethrow;
    } finally {
      actionBusy = false;
      refresh();
      notifyListeners();
    }
  }

  static String _messageForExitCode(int code, String label) {
    if (code == 2) {
      return 'PulseService is not installed. Use Repair / Install service.';
    }
    return 'Could not $label PulseService (exit code $code). '
        'Approve UAC if prompted, or reinstall Pulse.';
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
