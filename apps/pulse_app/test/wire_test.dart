import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_protocol/pulse_wire.dart';

void main() {
  test('Ping envelope roundtrip', () {
    final env = Envelope(
      requestId: 7,
      body: Ping(nonce: 3, unixMs: 100),
    );
    final bytes = encodeEnvelope(env);
    final decoded = decodeEnvelope(bytes);
    expect(decoded.requestId, 7);
    expect(decoded.body, isA<Ping>());
    expect((decoded.body! as Ping).nonce, 3);
  });

  test('frame roundtrip', () {
    final payload = encodeEnvelope(Envelope(requestId: 1, body: Ping(nonce: 1)));
    final frame = encodeFrame(payload);
    final decoded = tryDecodeFrame(frame)!;
    expect(decoded.payload, payload);
  });

  test('HealthProcessInventoryUpdate roundtrip', () {
    final inv = HealthProcessInventoryUpdate(
      seq: 9,
      fullResync: true,
      upserts: [
        HealthProcessEntry(
          pid: 1234,
          name: 'Pulse.exe',
          hasCpuPercent: true,
          cpuPercent: 3.5,
          hasMemoryBytes: true,
          memoryBytes: 50 * 1024 * 1024,
          hasCreateTime: true,
          createTimeUnixMs: 1_700_000_000_000,
          hasIsCritical: true,
          isCritical: false,
        ),
      ],
      removedPids: [99],
    );
    final env = Envelope(
      requestId: 0,
      body: HealthUpdate(
        sample: HealthSample(unixMs: 1),
        processInventory: inv,
      ),
    );
    final decoded = decodeEnvelope(encodeEnvelope(env));
    expect(decoded.body, isA<HealthUpdate>());
    final hu = decoded.body! as HealthUpdate;
    final out = hu.processInventory!;
    expect(out.seq, 9);
    expect(out.fullResync, isTrue);
    expect(out.removedPids, [99]);
    expect(out.upserts, hasLength(1));
    expect(out.upserts.first.pid, 1234);
    expect(out.upserts.first.name, 'Pulse.exe');
    expect(out.upserts.first.createTimeUnixMs, 1_700_000_000_000);
    expect(out.upserts.first.hasIsCritical, isTrue);
  });

  test('ProcessDetails envelope roundtrip', () {
    final env = Envelope(
      requestId: 42,
      body: ProcessDetails(
        pid: 7,
        name: 'notepad.exe',
        path: r'C:\Windows\System32\notepad.exe',
        company: 'Microsoft Corporation',
        commandLine: 'notepad.exe file.txt',
        hasPath: true,
        hasCompany: true,
        hasCommandLine: true,
        hasCreateTime: true,
        createTimeUnixMs: 1000,
        threadCount: 2,
        handleCount: 80,
        parentPid: 4,
        hasParentPid: true,
        parentName: 'System',
        hasParentName: true,
        user: r'NT AUTHORITY\SYSTEM',
        hasUser: true,
        integrityLevel: 'System',
        hasIntegrityLevel: true,
        elevated: true,
        hasElevated: true,
        architecture: 'x64',
        hasArchitecture: true,
        productName: 'Notepad',
        hasProductName: true,
      ),
    );
    final decoded = decodeEnvelope(encodeEnvelope(env));
    expect(decoded.body, isA<ProcessDetails>());
    final d = decoded.body! as ProcessDetails;
    expect(d.pid, 7);
    expect(d.company, 'Microsoft Corporation');
    expect(d.hasCommandLine, isTrue);
    expect(d.threadCount, 2);
    expect(d.parentPid, 4);
    expect(d.user, r'NT AUTHORITY\SYSTEM');
    expect(d.architecture, 'x64');
    expect(d.productName, 'Notepad');
    expect(d.elevated, isTrue);
  });

  test('GetProcessDetails request roundtrip', () {
    final env = Envelope(
      requestId: 5,
      body: GetProcessDetails(pid: 4242),
    );
    final decoded = decodeEnvelope(encodeEnvelope(env));
    expect(decoded.body, isA<GetProcessDetails>());
    expect((decoded.body! as GetProcessDetails).pid, 4242);
  });
}
