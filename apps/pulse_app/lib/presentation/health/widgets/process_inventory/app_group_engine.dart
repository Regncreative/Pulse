import 'package:pulse_protocol/pulse_wire.dart';

import 'process_display_name.dart';
import 'process_inventory_store.dart';

enum ProcessGroupSort { nameAscending, memoryDescending, gpuDescending }

/// Presentation-only application group over flat PID inventory.
///
/// Groups by normalized executable basename (e.g. all `chrome.exe`).
/// Does not change collector / IPC identity (PID + CreateTime).
class ProcessAppGroup {
  ProcessAppGroup({
    required this.id,
    required this.displayName,
    required this.memberPids,
    required this.category,
    required this.representativePid,
    required this.iconName,
    required this.iconPath,
    required this.hasCpu,
    required this.cpuPercent,
    required this.hasMemory,
    required this.memoryBytes,
    required this.hasDisk,
    required this.diskBps,
    required this.hasNet,
    required this.netBps,
    required this.hasGpu,
    required this.gpuPercent,
    required this.gpuDedicatedBytes,
    required this.gpuSharedBytes,
    this.commitBytesSum = 0,
    this.workingSetBytesSum = 0,
    this.pagedPoolBytesSum = 0,
    this.nonpagedPoolBytesSum = 0,
  });

  /// Stable key: lowercased image basename (`chrome.exe`).
  final String id;
  final String displayName;
  final List<int> memberPids;
  final ProcessCategory category;

  /// Best PID for icon / default selection (window owner or largest memory).
  final int representativePid;
  final String iconName;
  final String iconPath;

  final bool hasCpu;
  final double cpuPercent;
  final bool hasMemory;
  /// Sum of private working sets (`WorkingSetPrivateSize`).
  final int memoryBytes;
  final bool hasDisk;
  final double diskBps;
  final bool hasNet;
  final double netBps;

  final bool hasGpu;
  /// Sum of per-PID GPU util (same aggregation style as CPU).
  final double gpuPercent;
  final int gpuDedicatedBytes;
  final int gpuSharedBytes;

  final int commitBytesSum;
  final int workingSetBytesSum;
  final int pagedPoolBytesSum;
  final int nonpagedPoolBytesSum;

  int get memberCount => memberPids.length;

  int get privateWorkingSetSum => memoryBytes;
  int get sharedWorkingSetSum {
    final shared = workingSetBytesSum - privateWorkingSetSum;
    return shared > 0 ? shared : 0;
  }
}

/// Builds Task Manager–style app groups from the live PID store.
class AppGroupEngine {
  /// Group processes that share an executable basename, then place each group
  /// into Apps / Background / Windows from member categories.
  static List<ProcessAppGroup> build(ProcessInventoryStore store) {
    final buckets = <String, List<HealthProcessEntry>>{};
    for (final e in store.allEntries()) {
      final key = _imageKey(e.name);
      if (key.isEmpty) continue;
      buckets.putIfAbsent(key, () => <HealthProcessEntry>[]).add(e);
    }

    final groups = <ProcessAppGroup>[];
    for (final entry in buckets.entries) {
      final members = entry.value;
      members.sort((a, b) {
        final am = a.hasMemoryBytes ? a.memoryBytes : 0;
        final bm = b.hasMemoryBytes ? b.memoryBytes : 0;
        final byMem = bm.compareTo(am);
        if (byMem != 0) return byMem;
        return a.pid.compareTo(b.pid);
      });

      final category = _groupCategory(store, members);
      final rep = _representative(store, members);
      final pids = members.map((m) => m.pid).toList(growable: false);

      var cpu = 0.0;
      var hasCpu = false;
      var memory = 0;
      var hasMemory = false;
      var disk = 0.0;
      var hasDisk = false;
      var net = 0.0;
      var hasNet = false;
      var gpu = 0.0;
      var hasGpu = false;
      var gpuDedicated = 0;
      var gpuShared = 0;
      var commit = 0;
      var workingSet = 0;
      var paged = 0;
      var nonpaged = 0;
      for (final m in members) {
        if (m.hasCpuPercent) {
          hasCpu = true;
          cpu += m.cpuPercent;
        }
        if (m.hasMemoryBytes) {
          hasMemory = true;
          memory += m.memoryBytes;
        }
        if (m.hasDiskBps) {
          hasDisk = true;
          disk += m.diskBps;
        }
        if (m.hasNetBps) {
          hasNet = true;
          net += m.netBps;
        }
        if (m.hasGpuPercent) {
          hasGpu = true;
          gpu += m.gpuPercent;
        }
        if (m.hasGpuDedicatedBytes) {
          hasGpu = true;
          gpuDedicated += m.gpuDedicatedBytes;
        }
        if (m.hasGpuSharedBytes) {
          hasGpu = true;
          gpuShared += m.gpuSharedBytes;
        }
        if (m.hasCommitBytes) commit += m.commitBytes;
        if (m.hasWorkingSetBytes) workingSet += m.workingSetBytes;
        if (m.hasPagedPoolBytes) paged += m.pagedPoolBytes;
        if (m.hasNonpagedPoolBytes) nonpaged += m.nonpagedPoolBytes;
      }

      groups.add(
        ProcessAppGroup(
          id: entry.key,
          displayName: _displayName(rep.name),
          memberPids: pids,
          category: category,
          representativePid: rep.pid,
          iconName: rep.name,
          iconPath: rep.path,
          hasCpu: hasCpu,
          cpuPercent: cpu,
          hasMemory: hasMemory,
          memoryBytes: memory,
          hasDisk: hasDisk,
          diskBps: disk,
          hasNet: hasNet,
          netBps: net,
          hasGpu: hasGpu,
          gpuPercent: gpu,
          gpuDedicatedBytes: gpuDedicated,
          gpuSharedBytes: gpuShared,
          commitBytesSum: commit,
          workingSetBytesSum: workingSet,
          pagedPoolBytesSum: paged,
          nonpagedPoolBytesSum: nonpaged,
        ),
      );
    }

    groups.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return groups;
  }

  /// Sort within each section.
  static List<ProcessAppGroup> sortGroups(
    List<ProcessAppGroup> groups, {
    required ProcessGroupSort sort,
  }) {
    final copy = List<ProcessAppGroup>.from(groups);
    switch (sort) {
      case ProcessGroupSort.nameAscending:
        copy.sort(
          (a, b) =>
              a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
        );
      case ProcessGroupSort.memoryDescending:
        copy.sort((a, b) {
          final byMem = b.memoryBytes.compareTo(a.memoryBytes);
          if (byMem != 0) return byMem;
          return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
        });
      case ProcessGroupSort.gpuDescending:
        copy.sort((a, b) {
          final byGpu = b.gpuPercent.compareTo(a.gpuPercent);
          if (byGpu != 0) return byGpu;
          final byDed = b.gpuDedicatedBytes.compareTo(a.gpuDedicatedBytes);
          if (byDed != 0) return byDed;
          return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
        });
    }
    return copy;
  }

  static List<ProcessAppGroup> inCategory(
    List<ProcessAppGroup> all,
    ProcessCategory category, {
    ProcessGroupSort sort = ProcessGroupSort.nameAscending,
  }) =>
      sortGroups(
        all.where((g) => g.category == category).toList(),
        sort: sort,
      );

  static String _imageKey(String name) {
    final base = _baseName(name).toLowerCase();
    return base;
  }

  static String _baseName(String pathOrName) {
    final t = pathOrName.trim();
    if (t.isEmpty) return '';
    final slash = t.replaceAll('/', '\\').lastIndexOf('\\');
    return slash < 0 ? t : t.substring(slash + 1);
  }

  static String _displayName(String imageName) {
    final labels = ProcessDisplayNames.splitLabels(imageName: imageName);
    var primary = labels.primary.trim();
    if (primary.isEmpty || primary == '—') {
      primary = _baseName(imageName);
    }
    // TM Apps style: "Google Chrome", "Cursor" — strip trailing .exe when
    // the label is still the raw image name.
    final lower = primary.toLowerCase();
    if (lower.endsWith('.exe')) {
      primary = primary.substring(0, primary.length - 4);
    }
    return primary.isEmpty ? imageName : primary;
  }

  static ProcessCategory _groupCategory(
    ProcessInventoryStore store,
    List<HealthProcessEntry> members,
  ) {
    var hasApp = false;
    var hasBackground = false;
    var hasWindows = false;
    for (final m in members) {
      final c = store.categoryOf(m.pid) ?? ProcessCategory.background;
      switch (c) {
        case ProcessCategory.application:
          hasApp = true;
        case ProcessCategory.background:
          hasBackground = true;
        case ProcessCategory.windows:
          hasWindows = true;
      }
    }
    // Prefer Apps when any member owns a visible window (TM Apps tree).
    if (hasApp) return ProcessCategory.application;
    if (hasBackground) return ProcessCategory.background;
    if (hasWindows) return ProcessCategory.windows;
    return ProcessCategory.background;
  }

  static HealthProcessEntry _representative(
    ProcessInventoryStore store,
    List<HealthProcessEntry> members,
  ) {
    for (final m in members) {
      if (store.categoryOf(m.pid) == ProcessCategory.application) {
        return m;
      }
    }
    return members.first;
  }
}
