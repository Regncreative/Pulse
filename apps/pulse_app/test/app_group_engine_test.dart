import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/presentation/health/widgets/process_inventory/app_group_engine.dart';
import 'package:pulse/presentation/health/widgets/process_inventory/process_inventory_store.dart';
import 'package:pulse_protocol/pulse_wire.dart';

HealthProcessEntry _e({
  required int pid,
  required String name,
  int memory = 1024 * 1024,
  double cpu = 1,
  bool critical = false,
}) {
  return HealthProcessEntry(
    pid: pid,
    name: name,
    hasCpuPercent: true,
    cpuPercent: cpu,
    hasMemoryBytes: true,
    memoryBytes: memory,
    hasDiskBps: true,
    diskBps: 1000,
    hasIsCritical: critical,
    isCritical: critical,
  );
}

void main() {
  test('groups same executable basename and sums metrics', () {
    final store = ProcessInventoryStore();
    store.applyUpdate(
      HealthProcessInventoryUpdate(
        seq: 1,
        fullResync: true,
        upserts: [
          _e(pid: 1, name: 'chrome.exe', memory: 100 * 1024 * 1024, cpu: 2),
          _e(pid: 2, name: 'chrome.exe', memory: 50 * 1024 * 1024, cpu: 3),
          _e(pid: 3, name: 'Chrome.exe', memory: 25 * 1024 * 1024, cpu: 1),
          _e(pid: 4, name: 'notepad.exe', memory: 10 * 1024 * 1024, cpu: 0.5),
        ],
      ),
    );

    final groups = AppGroupEngine.build(store);
    final chrome = groups.firstWhere((g) => g.id == 'chrome.exe');
    expect(chrome.memberCount, 3);
    expect(chrome.displayName, 'Google Chrome');
    expect(chrome.memoryBytes, 175 * 1024 * 1024);
    expect(chrome.cpuPercent, 6);
    expect(chrome.memberPids.first, 1);

    final notepad = groups.firstWhere((g) => g.id == 'notepad.exe');
    expect(notepad.memberCount, 1);
    expect(notepad.displayName, 'notepad');
  });

  test('sorts groups by total private working set descending', () {
    final store = ProcessInventoryStore();
    store.applyUpdate(
      HealthProcessInventoryUpdate(
        seq: 1,
        fullResync: true,
        upserts: [
          _e(pid: 1, name: 'small.exe', memory: 10 * 1024 * 1024),
          _e(pid: 2, name: 'big.exe', memory: 40 * 1024 * 1024),
          _e(pid: 3, name: 'big.exe', memory: 30 * 1024 * 1024),
          _e(pid: 4, name: 'mid.exe', memory: 50 * 1024 * 1024),
        ],
      ),
    );

    final groups = AppGroupEngine.build(store);
    final sorted = AppGroupEngine.sortGroups(
      groups,
      sort: ProcessGroupSort.memoryDescending,
    );
    expect(sorted.map((g) => g.id).toList(), [
      'big.exe',
      'mid.exe',
      'small.exe',
    ]);
    expect(sorted.first.memoryBytes, 70 * 1024 * 1024);
  });

  test('group lands in Apps when any member owns a window', () {
    final store = ProcessInventoryStore();
    store.applyUpdate(
      HealthProcessInventoryUpdate(
        seq: 1,
        fullResync: true,
        upserts: [
          _e(pid: 10, name: 'Cursor.exe', memory: 200),
          _e(pid: 11, name: 'Cursor.exe', memory: 50),
          _e(pid: 12, name: 'csrss.exe', critical: true),
        ],
      ),
    );
    store.debugSetApplicationPids({10});

    final groups = AppGroupEngine.build(store);
    final cursor = groups.firstWhere((g) => g.id == 'cursor.exe');
    expect(cursor.category, ProcessCategory.application);
    expect(cursor.memberCount, 2);
    expect(cursor.displayName, 'Cursor');
    expect(cursor.representativePid, 10);

    expect(
      groups.firstWhere((g) => g.id == 'csrss.exe').category,
      ProcessCategory.windows,
    );
  });
}
