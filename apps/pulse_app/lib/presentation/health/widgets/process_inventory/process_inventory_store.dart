import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import 'process_window_classifier.dart';

enum ProcessCategory { application, background, windows }

/// Live Task Manager–style process inventory keyed by PID.
///
/// Identity for metrics is (PID + CreateTime). When CreateTime changes for the
/// same PID (PID recycling), the row is replaced and stale metrics are dropped.
/// Order within a section stays name-sorted and is not reshuffled by CPU.
class ProcessInventoryStore extends ChangeNotifier {
  final Map<int, HealthProcessEntry> _byPid = {};
  final List<int> _orderApps = [];
  final List<int> _orderBackground = [];
  final List<int> _orderWindows = [];
  final Map<int, ProcessCategory> _category = {};

  Set<int> _appPids = {};
  int _seq = 0;
  int? _selectedPid;

  int get seq => _seq;
  int? get selectedPid => _selectedPid;
  int get totalCount => _byPid.length;

  UnmodifiableListView<int> get applicationPids =>
      UnmodifiableListView(_orderApps);
  UnmodifiableListView<int> get backgroundPids =>
      UnmodifiableListView(_orderBackground);
  UnmodifiableListView<int> get windowsPids =>
      UnmodifiableListView(_orderWindows);

  HealthProcessEntry? entry(int pid) => _byPid[pid];

  ProcessCategory? categoryOf(int pid) => _category[pid];

  /// Snapshot of live entries (for presentation-layer grouping).
  List<HealthProcessEntry> allEntries() => _byPid.values.toList(growable: false);

  void clear() {
    _byPid.clear();
    _orderApps.clear();
    _orderBackground.clear();
    _orderWindows.clear();
    _category.clear();
    _appPids = {};
    _seq = 0;
    _selectedPid = null;
    notifyListeners();
  }

  void select(int? pid) {
    if (_selectedPid == pid) return;
    _selectedPid = pid;
    notifyListeners();
  }

  Future<void> refreshAppWindows() async {
    _appPids = await ProcessWindowClassifier.visibleApplicationPids();
    _recategorizeAll();
    notifyListeners();
  }

  /// Test-only: mark PIDs as visible application window owners.
  @visibleForTesting
  void debugSetApplicationPids(Set<int> pids) {
    _appPids = Set<int>.from(pids);
    _recategorizeAll();
    notifyListeners();
  }

  void applyUpdate(HealthProcessInventoryUpdate update) {
    _seq = update.seq;
    if (update.fullResync) {
      final keep = <int>{};
      for (final e in update.upserts) {
        keep.add(e.pid);
        _upsert(e, forceNameSort: true);
      }
      final removed = _byPid.keys.where((p) => !keep.contains(p)).toList();
      for (final pid in removed) {
        _removePid(pid);
      }
    } else {
      for (final pid in update.removedPids) {
        _removePid(pid);
      }
      for (final e in update.upserts) {
        _upsert(e, forceNameSort: false);
      }
    }
    notifyListeners();
  }

  void _upsert(HealthProcessEntry incoming, {required bool forceNameSort}) {
    final pid = incoming.pid;
    if (pid <= 0) return;
    final existing = _byPid[pid];

    // PID recycled → new CreateTime: drop stale metrics / selection.
    if (existing != null &&
        incoming.hasCreateTime &&
        existing.hasCreateTime &&
        incoming.createTimeUnixMs != 0 &&
        existing.createTimeUnixMs != 0 &&
        incoming.createTimeUnixMs != existing.createTimeUnixMs) {
      final wasSelected = _selectedPid == pid;
      _removeFromOrders(pid);
      _category.remove(pid);
      _byPid[pid] = incoming;
      final cat = _classify(incoming);
      _category[pid] = cat;
      _insertSorted(pid, incoming.name, cat);
      if (wasSelected) _selectedPid = pid;
      return;
    }

    if (existing == null) {
      _byPid[pid] = incoming;
      final cat = _classify(incoming);
      _category[pid] = cat;
      _insertSorted(pid, incoming.name, cat);
      return;
    }

    // Merge fields in place — keep stable list identity.
    if (incoming.name.isNotEmpty) existing.name = incoming.name;
    if (incoming.hasCpuPercent) {
      existing.hasCpuPercent = true;
      existing.cpuPercent = incoming.cpuPercent;
    }
    if (incoming.hasMemoryBytes) {
      existing.hasMemoryBytes = true;
      existing.memoryBytes = incoming.memoryBytes;
    }
    if (incoming.hasWorkingSetBytes) {
      existing.hasWorkingSetBytes = true;
      existing.workingSetBytes = incoming.workingSetBytes;
    }
    if (incoming.hasCommitBytes) {
      existing.hasCommitBytes = true;
      existing.commitBytes = incoming.commitBytes;
    }
    if (incoming.hasPagedPoolBytes) {
      existing.hasPagedPoolBytes = true;
      existing.pagedPoolBytes = incoming.pagedPoolBytes;
    }
    if (incoming.hasNonpagedPoolBytes) {
      existing.hasNonpagedPoolBytes = true;
      existing.nonpagedPoolBytes = incoming.nonpagedPoolBytes;
    }
    if (incoming.hasDiskBps) {
      existing.hasDiskBps = true;
      existing.diskBps = incoming.diskBps;
    }
    if (incoming.hasNetBps) {
      existing.hasNetBps = true;
      existing.netBps = incoming.netBps;
    } else if (incoming.hasCpuPercent || incoming.hasMemoryBytes) {
      // Unchanged net omitted on delta — keep prior rate only if still live.
      // Prefer honesty: clear net when service stopped reporting.
      // (Service omits has_net when unchanged; leave previous.)
    }
    if (incoming.path.isNotEmpty) existing.path = incoming.path;
    if (incoming.threadCount > 0) existing.threadCount = incoming.threadCount;
    if (incoming.handleCount > 0) existing.handleCount = incoming.handleCount;
    if (incoming.hasCreateTime) {
      existing.hasCreateTime = true;
      existing.createTimeUnixMs = incoming.createTimeUnixMs;
    }
    if (incoming.hasIsCritical) {
      existing.hasIsCritical = true;
      existing.isCritical = incoming.isCritical;
    }

    final cat = _classify(existing);
    final prev = _category[pid];
    if (prev != cat) {
      _removeFromOrders(pid);
      _category[pid] = cat;
      _insertSorted(pid, existing.name, cat);
    } else if (forceNameSort) {
      _removeFromOrders(pid);
      _insertSorted(pid, existing.name, cat);
    }
  }

  ProcessCategory _classify(HealthProcessEntry e) {
    if (_appPids.contains(e.pid)) return ProcessCategory.application;
    if (e.hasIsCritical && e.isCritical) return ProcessCategory.windows;
    if (_looksLikeWindows(e)) return ProcessCategory.windows;
    return ProcessCategory.background;
  }

  bool _looksLikeWindows(HealthProcessEntry e) {
    final n = e.name.trim().toLowerCase();
    const names = {
      'system',
      'smss.exe',
      'csrss.exe',
      'wininit.exe',
      'services.exe',
      'lsass.exe',
      'winlogon.exe',
      'svchost.exe',
      'dwm.exe',
      'fontdrvhost.exe',
      'memory compression',
      'registry',
      'conhost.exe',
      'taskhostw.exe',
    };
    if (names.contains(n)) return true;
    final path = e.path.toLowerCase().replaceAll('/', '\\');
    if (path.contains('\\windows\\system32\\') ||
        path.contains('\\windows\\syswow64\\')) {
      return true;
    }
    return false;
  }

  void _recategorizeAll() {
    final entries = _byPid.values.toList();
    _orderApps.clear();
    _orderBackground.clear();
    _orderWindows.clear();
    _category.clear();
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    for (final e in entries) {
      final cat = _classify(e);
      _category[e.pid] = cat;
      _listFor(cat).add(e.pid);
    }
  }

  List<int> _listFor(ProcessCategory cat) {
    switch (cat) {
      case ProcessCategory.application:
        return _orderApps;
      case ProcessCategory.background:
        return _orderBackground;
      case ProcessCategory.windows:
        return _orderWindows;
    }
  }

  void _insertSorted(int pid, String name, ProcessCategory cat) {
    final list = _listFor(cat);
    final key = name.toLowerCase();
    var i = 0;
    while (i < list.length) {
      final other = _byPid[list[i]]?.name.toLowerCase() ?? '';
      if (key.compareTo(other) < 0) break;
      i++;
    }
    list.insert(i, pid);
  }

  void _removeFromOrders(int pid) {
    _orderApps.remove(pid);
    _orderBackground.remove(pid);
    _orderWindows.remove(pid);
  }

  void _removePid(int pid) {
    _byPid.remove(pid);
    _category.remove(pid);
    _removeFromOrders(pid);
    if (_selectedPid == pid) _selectedPid = null;
  }
}
