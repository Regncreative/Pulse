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

  test('TimelineEventDetail R2 fields roundtrip', () {
    final env = Envelope(
      requestId: 15,
      body: TimelineEventDetail(
        found: true,
        event: TimelineEvent(
          eventId: 'System|1|1000|x',
          hasProcessId: true,
          processId: 4242,
          processName: 'app.exe',
          hasKeywords: true,
          keywords: 0x11,
          userSid: 'S-1-5-18',
          activityId: '{11111111-2222-3333-4444-555555555555}',
          levelName: 'Error',
          rawXml: '<Event/>',
        ),
      ),
    );
    final decoded = decodeEnvelope(encodeEnvelope(env));
    expect(decoded.body, isA<TimelineEventDetail>());
    final d = decoded.body! as TimelineEventDetail;
    expect(d.found, isTrue);
    expect(d.event.hasProcessId, isTrue);
    expect(d.event.processId, 4242);
    expect(d.event.processName, 'app.exe');
    expect(d.event.hasKeywords, isTrue);
    expect(d.event.keywords, 0x11);
    expect(d.event.rawXml, '<Event/>');
  });

  test('uint64 keywords high-bit varint roundtrip', () {
    final high = BigInt.parse('8000000000000011', radix: 16).toInt();
    final env = Envelope(
      requestId: 16,
      body: TimelineEvent(hasKeywords: true, keywords: high),
    );
    final decoded = decodeEnvelope(encodeEnvelope(env));
    final ev = decoded.body! as TimelineEvent;
    expect(ev.hasKeywords, isTrue);
    expect(ev.keywords.toUnsigned(64), high.toUnsigned(64));
  });

  test('InventoryDomainSnapshot R3 services roundtrip', () {
    final env = Envelope(
      requestId: 38,
      body: InventoryDomainSnapshot(
        domain: InventoryDomainId.services,
        status: InventoryStatus.available,
        generation: 9,
        cacheTtlMs: 30000,
        fullResync: true,
        services: [
          InventoryServiceEntry(
            id: 'EventLog',
            displayName: 'Windows Event Log',
            state: 'running',
            startType: 'automatic',
          ),
        ],
      ),
    );
    final decoded = decodeEnvelope(encodeEnvelope(env));
    expect(decoded.body, isA<InventoryDomainSnapshot>());
    final snap = decoded.body! as InventoryDomainSnapshot;
    expect(snap.domain, InventoryDomainId.services);
    expect(snap.status, InventoryStatus.available);
    expect(snap.generation, 9);
    expect(snap.services, hasLength(1));
    expect(snap.services.first.id, 'EventLog');
  });

  test('InventoryDomainSnapshot R3 drivers roundtrip', () {
    final env = Envelope(
      requestId: 39,
      body: InventoryDomainSnapshot(
        domain: InventoryDomainId.drivers,
        status: InventoryStatus.partial,
        generation: 2,
        drivers: [
          InventoryDriverEntry(
            id: 'Wdf01000',
            displayName: 'Kernel Mode Driver Frameworks',
            state: 'running',
            startType: 'boot',
            driverType: 'kernel',
          ),
        ],
      ),
    );
    final decoded = decodeEnvelope(encodeEnvelope(env));
    final snap = decoded.body! as InventoryDomainSnapshot;
    expect(snap.domain, InventoryDomainId.drivers);
    expect(snap.drivers, hasLength(1));
    expect(snap.drivers.first.id, 'Wdf01000');
    expect(snap.drivers.first.driverType, 'kernel');
  });

  test('InventoryDomainSnapshot R3 software roundtrip', () {
    final env = Envelope(
      requestId: 40,
      body: InventoryDomainSnapshot(
        domain: InventoryDomainId.software,
        status: InventoryStatus.available,
        generation: 4,
        software: [
          InventorySoftwareEntry(
            id: '{ABCDEF12-3456-7890-ABCD-EF1234567890}',
            displayName: 'Pulse Test App',
            version: '1.0.0',
            publisher: 'Pulse',
            architecture: 'x64',
          ),
        ],
      ),
    );
    final decoded = decodeEnvelope(encodeEnvelope(env));
    final snap = decoded.body! as InventoryDomainSnapshot;
    expect(snap.software, hasLength(1));
    expect(snap.software.first.displayName, 'Pulse Test App');
    expect(snap.software.first.architecture, 'x64');
  });

  test('GetInventoryDomain request roundtrip', () {
    final env = Envelope(
      requestId: 37,
      body: GetInventoryDomain(
        domain: InventoryDomainId.services,
        forceRefresh: true,
        sinceGeneration: 3,
        limit: 100,
      ),
    );
    final decoded = decodeEnvelope(encodeEnvelope(env));
    expect(decoded.body, isA<GetInventoryDomain>());
    final req = decoded.body! as GetInventoryDomain;
    expect(req.domain, InventoryDomainId.services);
    expect(req.forceRefresh, isTrue);
    expect(req.sinceGeneration, 3);
    expect(req.limit, 100);
  });
}
