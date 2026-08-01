import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Real Flutter frame timings + process RSS for Diagnostics (Phase 5).
///
/// FPS / build / raster come from [SchedulerBinding.addTimingsCallback].
/// Memory uses [ProcessInfo.currentRss] (WorkingSet on Windows).
class ClientFrameMetrics extends ChangeNotifier {
  ClientFrameMetrics({this.maxSamples = 120});

  final int maxSamples;

  bool _listening = false;
  final ListQueue<FrameTiming> _recent = ListQueue<FrameTiming>();
  int _rebuildCount = 0;

  double? fps;
  double? avgBuildMs;
  double? avgRasterMs;
  double? avgTotalFrameMs;
  int? rssBytes;
  int get rebuildCount => _rebuildCount;

  void start() {
    if (_listening) return;
    _listening = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!_listening) return;
    _listening = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  /// Lightweight counter for Diagnostics / Timeline rebuild observation.
  void noteRebuild() {
    _rebuildCount++;
  }

  void refreshMemory() {
    try {
      final rss = ProcessInfo.currentRss;
      if (rss > 0) {
        rssBytes = rss;
      }
    } catch (_) {
      // Leave previous / null — never invent.
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    for (final t in timings) {
      _recent.addLast(t);
      while (_recent.length > maxSamples) {
        _recent.removeFirst();
      }
    }
    _recompute();
    refreshMemory();
    notifyListeners();
  }

  void _recompute() {
    if (_recent.isEmpty) return;
    var buildUs = 0;
    var rasterUs = 0;
    var totalUs = 0;
    for (final t in _recent) {
      buildUs += t.buildDuration.inMicroseconds;
      rasterUs += t.rasterDuration.inMicroseconds;
      totalUs += t.totalSpan.inMicroseconds;
    }
    final n = _recent.length;
    avgBuildMs = buildUs / n / 1000.0;
    avgRasterMs = rasterUs / n / 1000.0;
    avgTotalFrameMs = totalUs / n / 1000.0;
    final spanUs = totalUs / n;
    if (spanUs > 0) {
      fps = 1e6 / spanUs;
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
