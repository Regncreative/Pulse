/// Pure alert state machine for background Windows notifications.
///
/// Uses sustained-threshold + hysteresis + cooldown. No Flutter/UI deps so it
/// can be unit-tested without plugins.
library;

enum AlertKind { cpu, memory, systemHealth, eventLog }

enum AlertPhase { idle, pending, active, cooling }

class AlertThresholds {
  const AlertThresholds({
    this.criticalPercent = 95.0,
    this.recoveryPercent = 85.0,
    this.sustainDuration = const Duration(seconds: 30),
    this.cooldown = const Duration(minutes: 15),
  });

  /// Matches [deriveSystemStatus] critical band (≥95%).
  final double criticalPercent;

  /// Hysteresis recovery line (below Attention band in System Health).
  final double recoveryPercent;

  final Duration sustainDuration;
  final Duration cooldown;
}

class AlertEvaluation {
  const AlertEvaluation({
    required this.kind,
    required this.shouldNotify,
    required this.phase,
    this.title,
    this.body,
  });

  final AlertKind kind;
  final bool shouldNotify;
  final AlertPhase phase;
  final String? title;
  final String? body;
}

class _AlertSlot {
  AlertPhase phase = AlertPhase.idle;
  DateTime? pendingSince;
  DateTime? lastNotifiedAt;
  DateTime? coolingUntil;
}

/// Debounced alert engine. Call [onSample] with wall-clock [now] for tests.
class AlertStateEngine {
  // ignore: prefer_initializing_formals — keep public named param `thresholds`.
  AlertStateEngine({AlertThresholds thresholds = const AlertThresholds()})
      : _thresholds = thresholds;

  AlertThresholds _thresholds;
  final Map<AlertKind, _AlertSlot> _slots = {
    for (final k in AlertKind.values) k: _AlertSlot(),
  };

  AlertThresholds get thresholds => _thresholds;

  /// Updates cooldown without resetting active alert phases.
  void updateCooldown(Duration cooldown) {
    _thresholds = AlertThresholds(
      criticalPercent: _thresholds.criticalPercent,
      recoveryPercent: _thresholds.recoveryPercent,
      sustainDuration: _thresholds.sustainDuration,
      cooldown: cooldown,
    );
  }

  AlertPhase phaseOf(AlertKind kind) => _slots[kind]!.phase;

  /// Evaluate CPU / memory / overall system-health critical flags.
  ///
  /// [systemHealthCritical] should reflect existing Pulse posture (e.g.
  /// [SystemStatusLevel.critical]), not a second metric collector.
  List<AlertEvaluation> onSample({
    required DateTime now,
    required double? cpuPercent,
    required double? memoryPercent,
    required bool systemHealthCritical,
    required bool notificationsEnabled,
    required bool notificationsPaused,
  }) {
    final out = <AlertEvaluation>[];
    out.add(
      _step(
        kind: AlertKind.cpu,
        now: now,
        isCritical: cpuPercent != null && cpuPercent >= _thresholds.criticalPercent,
        isRecovered: cpuPercent == null || cpuPercent < _thresholds.recoveryPercent,
        notificationsEnabled: notificationsEnabled,
        notificationsPaused: notificationsPaused,
        title: 'High CPU usage',
        body: 'CPU usage has remained above the critical threshold.',
      ),
    );
    out.add(
      _step(
        kind: AlertKind.memory,
        now: now,
        isCritical:
            memoryPercent != null && memoryPercent >= _thresholds.criticalPercent,
        isRecovered:
            memoryPercent == null || memoryPercent < _thresholds.recoveryPercent,
        notificationsEnabled: notificationsEnabled,
        notificationsPaused: notificationsPaused,
        title: 'Critical memory usage',
        body: 'Available memory is critically low.',
      ),
    );
    out.add(
      _step(
        kind: AlertKind.systemHealth,
        now: now,
        isCritical: systemHealthCritical,
        isRecovered: !systemHealthCritical,
        notificationsEnabled: notificationsEnabled,
        notificationsPaused: notificationsPaused,
        title: 'Critical system condition',
        body:
            'Pulse detected a critical system condition. Open Pulse for details.',
      ),
    );
    return out;
  }

  /// Event Log critical — only when the existing timeline already classifies
  /// Critical severity/importance. Still subject to cooldown / pause / enable.
  AlertEvaluation onCriticalEventLog({
    required DateTime now,
    required bool notificationsEnabled,
    required bool notificationsPaused,
  }) {
    final ev = _step(
      kind: AlertKind.eventLog,
      now: now,
      isCritical: true,
      isRecovered: false,
      forceImmediate: true,
      notificationsEnabled: notificationsEnabled,
      notificationsPaused: notificationsPaused,
      title: 'Critical system condition',
      body:
          'Pulse detected a critical Event Log condition. Open Pulse for details.',
    );
    if (ev.shouldNotify) {
      final slot = _slots[AlertKind.eventLog]!;
      slot.phase = AlertPhase.cooling;
      slot.coolingUntil = now.toUtc().add(_thresholds.cooldown);
      slot.pendingSince = null;
    }
    return ev;
  }

  /// Optional reset for tests.
  void resetForTest() {
    for (final slot in _slots.values) {
      slot.phase = AlertPhase.idle;
      slot.pendingSince = null;
      slot.lastNotifiedAt = null;
      slot.coolingUntil = null;
    }
  }

  AlertEvaluation _step({
    required AlertKind kind,
    required DateTime now,
    required bool isCritical,
    required bool isRecovered,
    required bool notificationsEnabled,
    required bool notificationsPaused,
    required String title,
    required String body,
    bool forceImmediate = false,
  }) {
    final slot = _slots[kind]!;
    final utc = now.toUtc();

    if (slot.phase == AlertPhase.cooling) {
      if (slot.coolingUntil != null && utc.isBefore(slot.coolingUntil!)) {
        if (isRecovered && !isCritical) {
          // Stay cooling until timer elapses.
        }
        return AlertEvaluation(
          kind: kind,
          shouldNotify: false,
          phase: AlertPhase.cooling,
        );
      }
      slot.phase = AlertPhase.idle;
      slot.coolingUntil = null;
      slot.pendingSince = null;
    }

    if (!notificationsEnabled || notificationsPaused) {
      if (isRecovered) {
        slot.phase = AlertPhase.idle;
        slot.pendingSince = null;
      }
      return AlertEvaluation(
        kind: kind,
        shouldNotify: false,
        phase: slot.phase,
      );
    }

    if (slot.phase == AlertPhase.active) {
      if (isRecovered) {
        slot.phase = AlertPhase.cooling;
        slot.coolingUntil = utc.add(_thresholds.cooldown);
        slot.pendingSince = null;
        return AlertEvaluation(
          kind: kind,
          shouldNotify: false,
          phase: AlertPhase.cooling,
        );
      }
      return AlertEvaluation(
        kind: kind,
        shouldNotify: false,
        phase: AlertPhase.active,
      );
    }

    if (!isCritical) {
      slot.phase = AlertPhase.idle;
      slot.pendingSince = null;
      return AlertEvaluation(
        kind: kind,
        shouldNotify: false,
        phase: AlertPhase.idle,
      );
    }

    // Critical path.
    if (slot.phase == AlertPhase.idle) {
      if (forceImmediate || _thresholds.sustainDuration == Duration.zero) {
        slot.phase = AlertPhase.active;
        slot.lastNotifiedAt = utc;
        slot.pendingSince = null;
        return AlertEvaluation(
          kind: kind,
          shouldNotify: true,
          phase: AlertPhase.active,
          title: title,
          body: body,
        );
      }
      slot.phase = AlertPhase.pending;
      slot.pendingSince = utc;
      return AlertEvaluation(
        kind: kind,
        shouldNotify: false,
        phase: AlertPhase.pending,
      );
    }

    // pending
    final since = slot.pendingSince ?? utc;
    if (forceImmediate ||
        utc.difference(since) >= _thresholds.sustainDuration) {
      slot.phase = AlertPhase.active;
      slot.lastNotifiedAt = utc;
      slot.pendingSince = null;
      return AlertEvaluation(
        kind: kind,
        shouldNotify: true,
        phase: AlertPhase.active,
        title: title,
        body: body,
      );
    }
    return AlertEvaluation(
      kind: kind,
      shouldNotify: false,
      phase: AlertPhase.pending,
    );
  }
}
