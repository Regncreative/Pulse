import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/application/service_lifecycle_controller.dart';
import 'package:pulse/logging/app_logger.dart';
import 'package:pulse/platform/pulse_deployment.dart';
import 'package:pulse/platform/pulse_service_launcher.dart';
import 'package:pulse/platform/pulse_service_scm.dart';
import 'package:pulse/presentation/utils/pulse_user_errors.dart';

class _FakeScm implements PulseServiceScm {
  _FakeScm(this.snapshot);
  PulseServiceScmSnapshot snapshot;

  @override
  PulseServiceScmSnapshot query() => snapshot;
}

class _FakeLauncher implements PulseServiceLauncher {
  _FakeLauncher({this.exitCode = 0, this.throwOnRun});

  int exitCode;
  Object? throwOnRun;
  final calls = <String>[];

  @override
  String? resolvePackageServiceExePath() => r'C:\Pulse\PulseService.exe';

  @override
  String? resolveInstalledServiceExePath() => r'C:\Pulse\PulseService.exe';

  @override
  Future<int> runElevated(
    String args, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    calls.add(args);
    final err = throwOnRun;
    if (err != null) {
      if (err is Exception) throw err;
      throw Exception(err.toString());
    }
    return exitCode;
  }
}

class _SequentialLauncher implements PulseServiceLauncher {
  _SequentialLauncher(this.codes);
  final List<int> codes;
  final calls = <String>[];
  var _i = 0;

  @override
  String? resolvePackageServiceExePath() => r'C:\Pulse\PulseService.exe';

  @override
  String? resolveInstalledServiceExePath() => r'C:\Pulse\PulseService.exe';

  @override
  Future<int> runElevated(
    String args, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    calls.add(args);
    final code = codes[_i.clamp(0, codes.length - 1)];
    _i++;
    return code;
  }
}

void main() {
  test('recovery copy distinguishes not installed vs stopped', () {
    final logger = AppLogger();
    final scm = _FakeScm(
      const PulseServiceScmSnapshot(state: PulseServiceScmState.notInstalled),
    );
    final life = ServiceLifecycleController(
      logger: logger,
      scm: scm,
    );
    life.refresh();
    expect(life.recoveryTitle, contains('not installed'));
    expect(life.primaryActionLabel, 'Repair / Install service');
    expect(life.canRepair, isTrue);
    expect(life.canStart, isFalse);

    scm.snapshot =
        const PulseServiceScmSnapshot(state: PulseServiceScmState.stopped);
    life.refresh();
    expect(life.recoveryTitle, contains('stopped'));
    expect(life.primaryActionLabel, 'Start PulseService');
    expect(life.canStart, isTrue);
    expect(life.canStop, isFalse);

    scm.snapshot =
        const PulseServiceScmSnapshot(state: PulseServiceScmState.running);
    life.refresh();
    expect(life.canStop, isTrue);
    expect(life.canRestart, isTrue);
    expect(life.primaryActionLabel, isNull);
  });

  test('pending states disable start/stop and mark transitioning', () {
    final life = ServiceLifecycleController(
      logger: AppLogger(),
      scm: _FakeScm(
        const PulseServiceScmSnapshot(state: PulseServiceScmState.startPending),
      ),
    );
    life.refresh();
    expect(life.isTransitioning, isTrue);
    expect(life.canStart, isFalse);
    expect(life.canStop, isFalse);
  });

  test('successful start clears error and sets success message', () async {
    final scm = _FakeScm(
      const PulseServiceScmSnapshot(state: PulseServiceScmState.stopped),
    );
    final launcher = _FakeLauncher(exitCode: 0);
    final life = ServiceLifecycleController(
      logger: AppLogger(),
      scm: scm,
      launcher: launcher,
    );
    life.refresh();

    final future = life.startService();
    scm.snapshot =
        const PulseServiceScmSnapshot(state: PulseServiceScmState.running);
    await future;

    expect(launcher.calls, contains('--start'));
    expect(life.lastError, isNull);
    expect(life.lastSuccess, contains('started'));
    expect(life.actionBusy, isFalse);
  });

  test('failed start surfaces exit code error', () async {
    final life = ServiceLifecycleController(
      logger: AppLogger(),
      scm: _FakeScm(
        const PulseServiceScmSnapshot(state: PulseServiceScmState.stopped),
      ),
      launcher: _FakeLauncher(exitCode: 1),
    );
    life.refresh();

    await expectLater(life.startService(), throwsA(isA<StateError>()));
    expect(life.lastError, contains('Could not start'));
    expect(life.actionBusy, isFalse);
  });

  test('failed stop surfaces exit code error', () async {
    final life = ServiceLifecycleController(
      logger: AppLogger(),
      scm: _FakeScm(
        const PulseServiceScmSnapshot(state: PulseServiceScmState.running),
      ),
      launcher: _FakeLauncher(exitCode: 1),
    );
    life.refresh();

    await expectLater(life.stopService(), throwsA(isA<StateError>()));
    expect(life.lastError, contains('Could not stop'));
    expect(life.actionBusy, isFalse);
  });

  test('UAC cancellation leaves service unchanged and reports clearly',
      () async {
    final life = ServiceLifecycleController(
      logger: AppLogger(),
      scm: _FakeScm(
        const PulseServiceScmSnapshot(state: PulseServiceScmState.stopped),
      ),
      launcher: _FakeLauncher(
        throwOnRun: const PulseServiceLaunchException(
          'Administrator approval was cancelled. Pulse did not change the service.',
        ),
      ),
    );
    life.refresh();

    await expectLater(
      life.startService(),
      throwsA(isA<PulseServiceLaunchException>()),
    );
    expect(life.lastError, contains('cancelled'));
    expect(
      PulseUserErrors.fromMessage(life.lastError!),
      contains('Administrator approval'),
    );
    expect(life.actionBusy, isFalse);
    expect(life.state, PulseServiceScmState.stopped);
  });

  test('not installed primary action repairs via install-start', () async {
    final scm = _FakeScm(
      const PulseServiceScmSnapshot(state: PulseServiceScmState.notInstalled),
    );
    final launcher = _FakeLauncher();
    final life = ServiceLifecycleController(
      logger: AppLogger(),
      scm: scm,
      launcher: launcher,
    );
    life.refresh();

    final future = life.runPrimaryRecoveryAction();
    scm.snapshot =
        const PulseServiceScmSnapshot(state: PulseServiceScmState.running);
    await future;

    expect(launcher.calls, contains('--install-start'));
    expect(life.lastSuccess, contains('installed'));
  });

  test('start with exit 2 falls back to install-start', () async {
    final scm = _FakeScm(
      const PulseServiceScmSnapshot(state: PulseServiceScmState.unknown),
    );
    final launcher = _SequentialLauncher([2, 0]);
    final life = ServiceLifecycleController(
      logger: AppLogger(),
      scm: scm,
      launcher: launcher,
    );
    life.refresh();

    final future = life.startService();
    scm.snapshot =
        const PulseServiceScmSnapshot(state: PulseServiceScmState.running);
    await future;

    expect(launcher.calls, ['--start', '--install-start']);
    expect(life.lastSuccess, contains('started'));
  });

  test('Store packaged: never repair or install-start', () async {
    final scm = _FakeScm(
      const PulseServiceScmSnapshot(state: PulseServiceScmState.notInstalled),
    );
    final launcher = _FakeLauncher();
    final life = ServiceLifecycleController(
      logger: AppLogger(),
      scm: scm,
      launcher: launcher,
      deployment: const FixedPulseDeployment(isPackagedMsix: true),
    );
    life.refresh();

    expect(life.isPackagedMsix, isTrue);
    expect(life.canRepair, isFalse);
    expect(life.primaryActionLabel, isNull);
    expect(life.recoveryMessage, contains('Store'));

    await expectLater(
      life.repairInstall(),
      throwsA(isA<PulseServiceLaunchException>()),
    );
    await expectLater(
      life.runPrimaryRecoveryAction(),
      throwsA(isA<PulseServiceLaunchException>()),
    );
    expect(launcher.calls, isEmpty);
  });

  test('Store packaged: start uses --start only', () async {
    final scm = _FakeScm(
      const PulseServiceScmSnapshot(state: PulseServiceScmState.stopped),
    );
    final launcher = _FakeLauncher();
    final life = ServiceLifecycleController(
      logger: AppLogger(),
      scm: scm,
      launcher: launcher,
      deployment: const FixedPulseDeployment(isPackagedMsix: true),
    );
    life.refresh();

    final future = life.startService();
    scm.snapshot =
        const PulseServiceScmSnapshot(state: PulseServiceScmState.running);
    await future;

    expect(launcher.calls, ['--start']);
    expect(life.lastSuccess, contains('started'));
  });
}
