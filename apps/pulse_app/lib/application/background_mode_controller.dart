import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:path/path.dart' as p;
import 'package:pulse_protocol/pulse_wire.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../ipc/pulse_ipc_client.dart';
import '../logging/app_logger.dart';
import '../presentation/health/health_view_models.dart';
import 'alert_state_engine.dart';
import 'settings_controller.dart';
import 'shell_navigation.dart';
import 'startup_helper.dart';
import 'window_close_behavior.dart';

/// Coordinates tray icon, hide-on-close, health/event alerts, and local toasts.
///
/// Never starts/stops PulseService — UI process lifecycle only.
class BackgroundModeController extends ChangeNotifier
    with WindowListener, TrayListener {
  BackgroundModeController({
    required this.settings,
    required this.ipc,
    required this.shellNavigation,
    required this.logger,
    AlertStateEngine? alertEngine,
  }) : _alerts = alertEngine ??
            AlertStateEngine(
              thresholds: AlertThresholds(
                criticalPercent: 95,
                recoveryPercent: 85,
                sustainDuration: const Duration(seconds: 30),
                cooldown: Duration(
                  minutes: settings.notificationCooldownMinutes.clamp(1, 180),
                ),
              ),
            );

  final SettingsController settings;
  final PulseIpcClient ipc;
  final ShellNavigation shellNavigation;
  final AppLogger logger;
  final AlertStateEngine _alerts;

  StreamSubscription<HealthUpdate>? _healthSub;
  StreamSubscription<TimelineEvent>? _liveSub;
  bool _started = false;
  bool _trayReady = false;
  bool _exiting = false;
  bool _windowHidden = false;

  bool get isWindowHidden => _windowHidden;
  bool get isExiting => _exiting;

  Future<void> start({required bool launchHidden}) async {
    if (_started) return;
    _started = true;

    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    settings.addListener(_onSettingsChanged);

    try {
      await localNotifier.setup(
        appName: 'Pulse Diagnostics',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
    } catch (e) {
      logger.warn('BackgroundMode', 'local_notifier setup failed: $e');
    }

    await _ensureTray();
    await _syncHealthMonitoring();
    await configureLaunchAtStartup(
      enabled: settings.startWithWindows,
      logger: logger,
    );
    _healthSub = ipc.healthUpdates.listen(_onHealthUpdate);
    _liveSub = ipc.liveEvents.listen(_onLiveEvent);

    if (launchHidden && settings.backgroundMode) {
      await hideToTray();
    }

    notifyListeners();
  }

  Future<void> disposeAsync() async {
    settings.removeListener(_onSettingsChanged);
    await _healthSub?.cancel();
    await _liveSub?.cancel();
    _healthSub = null;
    _liveSub = null;
    windowManager.removeListener(this);
    if (_trayReady) {
      trayManager.removeListener(this);
      try {
        await trayManager.destroy();
      } catch (_) {}
      _trayReady = false;
    }
  }

  @override
  void dispose() {
    unawaited(disposeAsync());
    super.dispose();
  }

  void _onSettingsChanged() {
    _alerts.updateCooldown(
      Duration(minutes: settings.notificationCooldownMinutes.clamp(1, 180)),
    );
    unawaited(_rebuildTrayMenu());
    unawaited(_syncHealthMonitoring());
    unawaited(
      configureLaunchAtStartup(
        enabled: settings.startWithWindows,
        logger: logger,
      ),
    );
  }

  Future<void> _syncHealthMonitoring() async {
    if (!settings.backgroundMode && !settings.systemNotifications) return;
    try {
      await ipc.startHealthMonitoring();
    } catch (e) {
      logger.debug('BackgroundMode', 'startHealthMonitoring: $e');
    }
  }

  Future<void> _ensureTray() async {
    if (!Platform.isWindows) return;
    if (_trayReady) {
      await _rebuildTrayMenu();
      return;
    }
    try {
      trayManager.addListener(this);
      final icon = _resolveTrayIconPath();
      await trayManager.setIcon(icon);
      await trayManager.setToolTip('Pulse Diagnostics');
      await _rebuildTrayMenu();
      _trayReady = true;
    } catch (e) {
      logger.warn('BackgroundMode', 'tray init failed: $e');
    }
  }

  String _resolveTrayIconPath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      p.join(
        exeDir,
        'data',
        'flutter_assets',
        'assets',
        'branding',
        'app_icon.ico',
      ),
      p.join(
        exeDir,
        'data',
        'flutter_assets',
        'assets',
        'branding',
        'app_icon_32.png',
      ),
      p.join('assets', 'branding', 'app_icon.ico'),
      p.join('windows', 'runner', 'resources', 'app_icon.ico'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return candidates.first;
  }

  Future<void> _rebuildTrayMenu() async {
    if (!Platform.isWindows) return;
    final menu = Menu(
      items: [
        MenuItem(key: 'open', label: 'Open Pulse'),
        MenuItem.separator(),
        MenuItem(key: 'dashboard', label: 'Dashboard'),
        MenuItem(key: 'health', label: 'System Health'),
        MenuItem(key: 'processes', label: 'Processes'),
        MenuItem(key: 'hardware', label: 'Hardware'),
        MenuItem(key: 'storage', label: 'Storage'),
        MenuItem(key: 'network', label: 'Network'),
        MenuItem(key: 'events', label: 'Event Logs'),
        MenuItem(key: 'settings', label: 'Settings'),
        MenuItem.separator(),
        MenuItem.checkbox(
          key: 'pause_notifications',
          label: 'Pause Notifications',
          checked: settings.notificationsPaused,
        ),
        MenuItem.checkbox(
          key: 'background_mode',
          label: 'Background Mode',
          checked: settings.backgroundMode,
        ),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Exit Pulse'),
      ],
    );
    try {
      await trayManager.setContextMenu(menu);
    } catch (e) {
      logger.debug('BackgroundMode', 'setContextMenu: $e');
    }
  }

  Future<void> hideToTray() async {
    _windowHidden = true;
    await _ensureTray();
    try {
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
    } catch (e) {
      logger.warn('BackgroundMode', 'hideToTray failed: $e');
    }
    notifyListeners();
  }

  Future<void> showMainWindow() async {
    _windowHidden = false;
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      logger.warn('BackgroundMode', 'showMainWindow failed: $e');
    }
    notifyListeners();
  }

  /// Terminates Pulse.exe only. Does not stop or uninstall PulseService.
  Future<void> exitPulseUi() async {
    if (_exiting) return;
    _exiting = true;
    logger.info('BackgroundMode', 'Exit Pulse (UI only; service unchanged)');
    try {
      await windowManager.setPreventClose(false);
    } catch (_) {}
    try {
      if (_trayReady) {
        trayManager.removeListener(this);
        await trayManager.destroy();
        _trayReady = false;
      }
    } catch (_) {}
    try {
      await windowManager.destroy();
    } catch (_) {
      exit(0);
    }
  }

  @override
  void onWindowClose() {
    if (_exiting) return;
    final decision = resolveWindowCloseDecision(
      backgroundModeEnabled: settings.backgroundMode,
    );
    switch (decision) {
      case PulseUiCloseDecision.hideToTray:
        unawaited(hideToTray());
      case PulseUiCloseDecision.exitUi:
        unawaited(exitPulseUi());
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showMainWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key == null) return;
    unawaited(_handleTrayKey(key));
  }

  Future<void> _handleTrayKey(String key) async {
    switch (key) {
      case 'open':
        await showMainWindow();
        shellNavigation.open(PulseNavTarget.open);
      case 'dashboard':
        await showMainWindow();
        shellNavigation.open(PulseNavTarget.dashboard);
      case 'health':
        await showMainWindow();
        shellNavigation.open(PulseNavTarget.systemHealth);
      case 'processes':
        await showMainWindow();
        shellNavigation.open(PulseNavTarget.processes);
      case 'hardware':
        await showMainWindow();
        shellNavigation.open(PulseNavTarget.hardware);
      case 'storage':
        await showMainWindow();
        shellNavigation.open(PulseNavTarget.storage);
      case 'network':
        await showMainWindow();
        shellNavigation.open(PulseNavTarget.network);
      case 'events':
        await showMainWindow();
        shellNavigation.open(PulseNavTarget.eventLogs);
      case 'settings':
        await showMainWindow();
        shellNavigation.open(PulseNavTarget.settings);
      case 'pause_notifications':
        await settings.setNotificationsPaused(!settings.notificationsPaused);
        await _rebuildTrayMenu();
      case 'background_mode':
        await settings.setBackgroundMode(!settings.backgroundMode);
        await _rebuildTrayMenu();
        if (!settings.backgroundMode && _windowHidden) {
          await showMainWindow();
        }
      case 'exit':
        await exitPulseUi();
    }
  }

  void _onHealthUpdate(HealthUpdate update) {
    final sample = update.sample;
    final memPct = sample.memoryTotalBytes > 0
        ? sample.memoryUsedBytes * 100.0 / sample.memoryTotalBytes
        : null;
    final cpuPct = sample.hasCpuPercent ? sample.cpuPercent : null;
    final status = deriveSystemStatus(sample);
    // Avoid duplicate toasts: CPU/memory have dedicated kinds; systemHealth
    // covers other critical posture (e.g. disk ≥95%) from the same sample.
    final cpuCritical =
        cpuPct != null && cpuPct >= _alerts.thresholds.criticalPercent;
    final memCritical =
        memPct != null && memPct >= _alerts.thresholds.criticalPercent;
    final systemHealthCritical = status.level == SystemStatusLevel.critical &&
        !cpuCritical &&
        !memCritical;

    final results = _alerts.onSample(
      now: DateTime.now().toUtc(),
      cpuPercent: cpuPct,
      memoryPercent: memPct,
      systemHealthCritical: systemHealthCritical,
      notificationsEnabled: settings.systemNotifications,
      notificationsPaused: settings.notificationsPaused,
    );
    for (final ev in results) {
      if (ev.shouldNotify && ev.title != null && ev.body != null) {
        unawaited(_showNotification(ev));
      }
    }
  }

  void _onLiveEvent(TimelineEvent event) {
    final critical = event.severity == Severity.critical ||
        event.importance == Importance.critical;
    if (!critical) return;
    final ev = _alerts.onCriticalEventLog(
      now: DateTime.now().toUtc(),
      notificationsEnabled: settings.systemNotifications,
      notificationsPaused: settings.notificationsPaused,
    );
    if (ev.shouldNotify && ev.title != null && ev.body != null) {
      unawaited(_showNotification(ev));
    }
  }

  Future<void> _showNotification(AlertEvaluation ev) async {
    try {
      final n = LocalNotification(
        identifier: 'pulse-alert:${ev.kind.name}',
        title: ev.title!,
        body: ev.body!,
      );
      n.onClick = () {
        unawaited(showMainWindow());
        shellNavigation.openForAlert(ev.kind);
      };
      await n.show();
    } catch (e) {
      logger.warn('BackgroundMode', 'notification failed: $e');
    }
  }
}
