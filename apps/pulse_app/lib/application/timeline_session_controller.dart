import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../app/dev_flags.dart';
import '../features/timeline/mock_timeline_events.dart';
import '../ipc/pulse_ipc_client.dart';
import '../logging/app_logger.dart';
import 'settings_controller.dart';

/// Shared Timeline session so Diagnostics tools can clear / restart live.
class TimelineSessionController extends ChangeNotifier {
  TimelineSessionController({
    required this.ipc,
    required this.settings,
    required this.logger,
  }) {
    ipc.addListener(_onIpc);
    settings.addListener(_onSettings);
    _liveSub = ipc.liveEvents.listen(_onLiveEvent);
  }

  final PulseIpcClient ipc;
  final SettingsController settings;
  final AppLogger logger;

  List<TimelineEvent> _events = const [];
  List<TimelineEvent> get events => _events;

  bool _liveActive = false;
  bool get liveActive => _liveActive;

  bool _loadingSnapshot = false;
  bool get loadingSnapshot => _loadingSnapshot;

  String? _loadError;
  String? get loadError => _loadError;

  int _pendingNewCount = 0;
  int get pendingNewCount => _pendingNewCount;

  bool stickToTop = true;
  int _clientLiveReceived = 0;
  int get clientLiveReceived => _clientLiveReceived;
  final List<DateTime> _recentLiveTimestamps = [];
  TimelineEvent? _lastLiveEvent;
  TimelineEvent? get lastLiveEvent => _lastLiveEvent;

  IpcConnectionState? _lastState;
  StreamSubscription<TimelineEvent>? _liveSub;
  int _fetchGeneration = 0;
  bool _started = false;
  /// When false (Timeline tab not visible), pause EvtSubscribe to idle CPU.
  bool _pageVisible = true;
  bool get pageVisible => _pageVisible;

  double get clientEventsPerMinute {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    _recentLiveTimestamps.removeWhere((t) => t.isBefore(cutoff));
    return _recentLiveTimestamps.length.toDouble();
  }

  void attach() {
    if (_started) return;
    _started = true;
    _onIpc();
  }

  /// Pause live IPC when the Timeline page is not on screen.
  Future<void> setPageVisible(bool visible) async {
    if (_pageVisible == visible) return;
    _pageVisible = visible;
    if (!visible) {
      if (_liveActive) {
        try {
          await ipc.stopLiveMonitoring();
        } catch (_) {}
        _liveActive = false;
        notifyListeners();
      }
      return;
    }
    if (settings.liveMonitoringEnabled &&
        ipc.status.state == IpcConnectionState.connected) {
      try {
        await ipc.startLiveMonitoring();
        _liveActive = true;
        notifyListeners();
      } catch (e) {
        logger.warn('TimelineSession', 'Resume live failed: $e');
      }
    }
  }

  void setStickToTop(bool value) {
    if (stickToTop == value) return;
    stickToTop = value;
    if (value) _pendingNewCount = 0;
    notifyListeners();
  }

  void clearPending() {
    if (_pendingNewCount == 0) return;
    _pendingNewCount = 0;
    notifyListeners();
  }

  Future<void> clearTimeline() async {
    _events = const [];
    _pendingNewCount = 0;
    _lastLiveEvent = null;
    notifyListeners();
    logger.info('TimelineSession', 'Timeline cleared');
  }

  Future<void> restartLiveMonitoring() async {
    if (ipc.status.state != IpcConnectionState.connected) {
      throw StateError('Service is offline — cannot restart live monitoring.');
    }
    try {
      await ipc.stopLiveMonitoring();
    } catch (_) {
      // Best-effort stop.
    }
    if (!settings.liveMonitoringEnabled) {
      _liveActive = false;
      notifyListeners();
      return;
    }
    await ipc.startLiveMonitoring();
    _liveActive = true;
    notifyListeners();
    logger.info('TimelineSession', 'Live monitoring restarted');
  }

  Future<void> applyLiveMonitoringPreference() async {
    if (ipc.status.state != IpcConnectionState.connected) return;
    if (!_pageVisible) {
      _liveActive = false;
      notifyListeners();
      return;
    }
    if (settings.liveMonitoringEnabled) {
      await ipc.startLiveMonitoring();
      _liveActive = true;
    } else {
      try {
        await ipc.stopLiveMonitoring();
      } catch (_) {}
      _liveActive = false;
    }
    notifyListeners();
  }

  Future<void> reloadSnapshot() async {
    if (kUseMockTimeline) {
      _events = mockTimelineEvents();
      _loadError = null;
      _loadingSnapshot = false;
      notifyListeners();
      return;
    }
    if (ipc.status.state != IpcConnectionState.connected) return;
    final gen = ++_fetchGeneration;
    _loadingSnapshot = true;
    _loadError = null;
    notifyListeners();
    try {
      final snap = await ipc.getTimelineSnapshot(
        limit: settings.startupSnapshotSize,
      );
      if (gen != _fetchGeneration) return;
      _events = List<TimelineEvent>.from(snap.events);
      _trim();
      _loadingSnapshot = false;
      _loadError = null;
      if (settings.liveMonitoringEnabled && _pageVisible) {
        await ipc.startLiveMonitoring();
        _liveActive = true;
      }
      notifyListeners();
    } catch (e) {
      if (gen != _fetchGeneration) return;
      _loadingSnapshot = false;
      _loadError = e.toString();
      notifyListeners();
    }
  }

  void _onLiveEvent(TimelineEvent event) {
    if (kUseMockTimeline) return;
    if (event.eventId.isNotEmpty &&
        _events.any((e) => e.eventId == event.eventId)) {
      return;
    }
    _clientLiveReceived++;
    _lastLiveEvent = event;
    _recentLiveTimestamps.add(DateTime.now());
    final stick = stickToTop && settings.autoScroll;
    _events = [event, ..._events];
    _trim();
    _liveActive = true;
    if (!stick) _pendingNewCount += 1;
    notifyListeners();
  }

  void _trim() {
    final max = settings.maxStoredEvents;
    if (_events.length > max) {
      _events = _events.sublist(0, max);
    }
  }

  void _onSettings() {
    // Trim only — live preference is applied explicitly from Settings /
    // reload paths so unrelated prefs do not restart EvtSubscribe.
    _trim();
    notifyListeners();
  }

  void _onIpc() {
    final state = ipc.status.state;
    if (_lastState == state) return;
    final previous = _lastState;
    _lastState = state;
    final becameConnected = state == IpcConnectionState.connected &&
        previous != IpcConnectionState.connected;
    if (becameConnected) {
      unawaited(reloadSnapshot());
    } else if (state == IpcConnectionState.disconnected ||
        state == IpcConnectionState.error) {
      _liveActive = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    ipc.removeListener(_onIpc);
    settings.removeListener(_onSettings);
    super.dispose();
  }
}
