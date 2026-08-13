import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/application/alert_state_engine.dart';

void main() {
  late AlertStateEngine engine;
  final t0 = DateTime.utc(2026, 7, 30, 12);

  setUp(() {
    engine = AlertStateEngine(
      thresholds: const AlertThresholds(
        criticalPercent: 95,
        recoveryPercent: 85,
        sustainDuration: Duration(seconds: 30),
        cooldown: Duration(minutes: 15),
      ),
    );
  });

  List<AlertEvaluation> sample({
    required DateTime now,
    double? cpu,
    double? mem,
    bool healthCritical = false,
    bool enabled = true,
    bool paused = false,
  }) {
    return engine.onSample(
      now: now,
      cpuPercent: cpu,
      memoryPercent: mem,
      systemHealthCritical: healthCritical,
      notificationsEnabled: enabled,
      notificationsPaused: paused,
    );
  }

  AlertEvaluation cpuOf(List<AlertEvaluation> list) =>
      list.firstWhere((e) => e.kind == AlertKind.cpu);

  test('threshold not exceeded -> no notification', () {
    final r = sample(now: t0, cpu: 50);
    expect(cpuOf(r).shouldNotify, isFalse);
    expect(cpuOf(r).phase, AlertPhase.idle);
  });

  test('threshold briefly exceeded -> no notification', () {
    final a = sample(now: t0, cpu: 96);
    expect(cpuOf(a).shouldNotify, isFalse);
    expect(cpuOf(a).phase, AlertPhase.pending);

    final b = sample(now: t0.add(const Duration(seconds: 10)), cpu: 97);
    expect(cpuOf(b).shouldNotify, isFalse);
    expect(cpuOf(b).phase, AlertPhase.pending);
  });

  test('threshold sustained -> notification', () {
    sample(now: t0, cpu: 96);
    final r = sample(now: t0.add(const Duration(seconds: 30)), cpu: 96);
    expect(cpuOf(r).shouldNotify, isTrue);
    expect(cpuOf(r).title, 'High CPU usage');
    expect(cpuOf(r).phase, AlertPhase.active);
  });

  test('repeated critical samples -> no spam', () {
    sample(now: t0, cpu: 96);
    final first =
        sample(now: t0.add(const Duration(seconds: 30)), cpu: 96);
    expect(cpuOf(first).shouldNotify, isTrue);

    for (var i = 1; i <= 10; i++) {
      final r = sample(
        now: t0.add(Duration(seconds: 30 + i)),
        cpu: 99,
      );
      expect(cpuOf(r).shouldNotify, isFalse, reason: 'second $i');
    }
  });

  test('recovery -> alert resets; critical again after recovery -> notify', () {
    sample(now: t0, cpu: 96);
    expect(
      cpuOf(sample(now: t0.add(const Duration(seconds: 30)), cpu: 96))
          .shouldNotify,
      isTrue,
    );

    // Recover below hysteresis line.
    final cool = sample(
      now: t0.add(const Duration(seconds: 40)),
      cpu: 50,
    );
    expect(cpuOf(cool).shouldNotify, isFalse);
    expect(cpuOf(cool).phase, AlertPhase.cooling);

    // Still in cooldown — no notify.
    sample(now: t0.add(const Duration(minutes: 5)), cpu: 96);
    final duringCool = sample(
      now: t0.add(const Duration(minutes: 5, seconds: 30)),
      cpu: 96,
    );
    expect(cpuOf(duringCool).shouldNotify, isFalse);

    // After cooldown elapses, allow a new sustained alert.
    final afterCool = t0.add(const Duration(minutes: 16));
    sample(now: afterCool, cpu: 50); // idle after cooling expires
    sample(now: afterCool.add(const Duration(seconds: 1)), cpu: 96);
    final again = sample(
      now: afterCool.add(const Duration(seconds: 31)),
      cpu: 96,
    );
    expect(cpuOf(again).shouldNotify, isTrue);
  });

  test('cooldown -> notification suppressed while cooling', () {
    sample(now: t0, cpu: 96);
    sample(now: t0.add(const Duration(seconds: 30)), cpu: 96);
    sample(now: t0.add(const Duration(seconds: 35)), cpu: 50);

    final suppressed = sample(
      now: t0.add(const Duration(minutes: 1)),
      cpu: 99,
    );
    expect(cpuOf(suppressed).shouldNotify, isFalse);
    expect(cpuOf(suppressed).phase, AlertPhase.cooling);
  });

  test('notifications disabled -> no notification', () {
    sample(now: t0, cpu: 96, enabled: false);
    final r = sample(
      now: t0.add(const Duration(seconds: 30)),
      cpu: 96,
      enabled: false,
    );
    expect(cpuOf(r).shouldNotify, isFalse);
  });

  test('notifications paused -> no notification', () {
    sample(now: t0, cpu: 96, paused: true);
    final r = sample(
      now: t0.add(const Duration(seconds: 30)),
      cpu: 96,
      paused: true,
    );
    expect(cpuOf(r).shouldNotify, isFalse);
  });

  test('memory sustained critical notifies once', () {
    AlertEvaluation memOf(List<AlertEvaluation> list) =>
        list.firstWhere((e) => e.kind == AlertKind.memory);

    sample(now: t0, mem: 96);
    final r = sample(now: t0.add(const Duration(seconds: 30)), mem: 96);
    expect(memOf(r).shouldNotify, isTrue);
    expect(memOf(r).title, 'Critical memory usage');
  });

  test('event log critical respects cooldown', () {
    final a = engine.onCriticalEventLog(
      now: t0,
      notificationsEnabled: true,
      notificationsPaused: false,
    );
    expect(a.shouldNotify, isTrue);

    final b = engine.onCriticalEventLog(
      now: t0.add(const Duration(seconds: 5)),
      notificationsEnabled: true,
      notificationsPaused: false,
    );
    expect(b.shouldNotify, isFalse);
  });
}
