import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/presentation/health/widgets/process_inventory/process_inventory_list.dart';
import 'package:pulse/presentation/health/widgets/process_inventory/process_inventory_store.dart';
import 'package:pulse_protocol/pulse_wire.dart';

HealthProcessEntry _entry({
  required int pid,
  required String name,
  double cpu = 0,
  bool windows = false,
  String path = '',
}) {
  return HealthProcessEntry(
    pid: pid,
    name: name,
    hasCpuPercent: true,
    cpuPercent: cpu,
    hasMemoryBytes: true,
    memoryBytes: 1024 * 1024,
    hasIsCritical: windows,
    isCritical: windows,
    path: path,
  );
}

void main() {
  test('merge keeps PID order when CPU ranks change', () {
    final store = ProcessInventoryStore();
    store.applyUpdate(
      HealthProcessInventoryUpdate(
        seq: 1,
        fullResync: true,
        upserts: [
          _entry(pid: 10, name: 'alpha.exe', cpu: 1),
          _entry(pid: 20, name: 'beta.exe', cpu: 50),
          _entry(pid: 30, name: 'gamma.exe', cpu: 5),
        ],
      ),
    );

    expect(store.backgroundPids.toList(), [10, 20, 30]);

    store.applyUpdate(
      HealthProcessInventoryUpdate(
        seq: 2,
        upserts: [
          _entry(pid: 10, name: 'alpha.exe', cpu: 90),
          _entry(pid: 20, name: 'beta.exe', cpu: 1),
          _entry(pid: 30, name: 'gamma.exe', cpu: 40),
        ],
      ),
    );

    expect(store.backgroundPids.toList(), [10, 20, 30]);
    expect(store.entry(10)!.cpuPercent, 90);
    expect(store.entry(20)!.cpuPercent, 1);
  });

  test('removed_pids drops rows', () {
    final store = ProcessInventoryStore();
    store.applyUpdate(
      HealthProcessInventoryUpdate(
        seq: 1,
        fullResync: true,
        upserts: [
          _entry(pid: 1, name: 'a.exe'),
          _entry(pid: 2, name: 'b.exe'),
        ],
      ),
    );
    store.applyUpdate(
      HealthProcessInventoryUpdate(
        seq: 2,
        removedPids: [1],
        upserts: [_entry(pid: 2, name: 'b.exe', cpu: 3)],
      ),
    );
    expect(store.totalCount, 1);
    expect(store.entry(1), isNull);
    expect(store.backgroundPids, [2]);
  });

  test('critical processes land in Windows section', () {
    final store = ProcessInventoryStore();
    store.applyUpdate(
      HealthProcessInventoryUpdate(
        seq: 1,
        fullResync: true,
        upserts: [
          _entry(pid: 4, name: 'csrss.exe', windows: true),
          _entry(pid: 100, name: 'notepad.exe'),
        ],
      ),
    );
    expect(store.windowsPids, [4]);
    expect(store.backgroundPids, [100]);
  });

  test('PID recycle with new create_time resets metrics', () {
    final store = ProcessInventoryStore();
    store.applyUpdate(
      HealthProcessInventoryUpdate(
        seq: 1,
        fullResync: true,
        upserts: [
          HealthProcessEntry(
            pid: 42,
            name: 'old.exe',
            hasCpuPercent: true,
            cpuPercent: 88,
            hasCreateTime: true,
            createTimeUnixMs: 1000,
          ),
        ],
      ),
    );
    store.applyUpdate(
      HealthProcessInventoryUpdate(
        seq: 2,
        upserts: [
          HealthProcessEntry(
            pid: 42,
            name: 'new.exe',
            hasCpuPercent: true,
            cpuPercent: 1,
            hasCreateTime: true,
            createTimeUnixMs: 9999,
          ),
        ],
      ),
    );
    expect(store.entry(42)!.name, 'new.exe');
    expect(store.entry(42)!.cpuPercent, 1);
    expect(store.entry(42)!.createTimeUnixMs, 9999);
  });

  testWidgets('section headers render with counts', (tester) async {
    final store = ProcessInventoryStore();
    store.applyUpdate(
      HealthProcessInventoryUpdate(
        seq: 1,
        fullResync: true,
        upserts: [
          _entry(pid: 4, name: 'csrss.exe', windows: true),
          _entry(pid: 200, name: 'tool.exe'),
          _entry(pid: 201, name: 'worker.exe'),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ProcessInventoryList(store: store),
          ),
        ),
      ),
    );

    expect(find.text('Background processes (2)'), findsOneWidget);
    expect(find.text('Windows processes (1)'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('tool (1)'), findsOneWidget);
    expect(find.text('worker (1)'), findsOneWidget);
    expect(find.text('Client Server Runtime Process (1)'), findsOneWidget);
  });
}
