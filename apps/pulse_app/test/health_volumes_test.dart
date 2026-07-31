import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/presentation/health/health_view_models.dart';
import 'package:pulse_protocol/pulse_wire.dart';

void main() {
  test('HealthSample volumes and disks roundtrip on the wire', () {
    final sample = HealthSample(
      unixMs: 1,
      diskUsedBytes: 100,
      diskTotalBytes: 200,
      volumes: [
        HealthVolume(
          id: 'C:',
          mountPoint: r'C:\',
          label: 'System',
          fileSystem: 'NTFS',
          kind: HealthDriveKind.fixed,
          usedBytes: 100,
          totalBytes: 200,
          hasCapacity: true,
          includedInSummary: true,
        ),
        HealthVolume(
          id: 'Z:',
          mountPoint: r'Z:\',
          kind: HealthDriveKind.remote,
          hasCapacity: false,
        ),
      ],
      disks: [
        HealthPhysicalDisk(
          id: '0 C:',
          name: '0 C:',
          hasReadBps: true,
          readBps: 1024,
          hasWriteBps: true,
          writeBps: 512,
        ),
      ],
    );

    final encoded = encodeEnvelope(
      Envelope(requestId: 3, body: HealthUpdate(sample: sample)),
    );
    final decoded = decodeEnvelope(encoded);
    final body = decoded.body! as HealthUpdate;
    expect(body.sample.volumes, hasLength(2));
    expect(body.sample.volumes[0].id, 'C:');
    expect(body.sample.volumes[0].kind, HealthDriveKind.fixed);
    expect(body.sample.volumes[0].hasCapacity, isTrue);
    expect(body.sample.volumes[1].kind, HealthDriveKind.remote);
    expect(body.sample.volumes[1].hasCapacity, isFalse);
    expect(body.sample.disks, hasLength(1));
    expect(body.sample.disks[0].id, '0 C:');
    expect(body.sample.disks[0].readBps, 1024);
  });

  test('storageRows lists each volume without assuming only C:', () {
    final view = HealthViewState()
      ..applySample(
        HealthSample(
          hasDiskReadBps: true,
          diskReadBps: 1024,
          hasDiskWriteBps: true,
          diskWriteBps: 2048,
          diskUsedBytes: 50,
          diskTotalBytes: 100,
          volumes: [
            HealthVolume(
              id: 'C:',
              kind: HealthDriveKind.fixed,
              usedBytes: 50,
              totalBytes: 100,
              hasCapacity: true,
              includedInSummary: true,
            ),
            HealthVolume(
              id: 'D:',
              label: 'Data',
              kind: HealthDriveKind.fixed,
              usedBytes: 10,
              totalBytes: 500,
              hasCapacity: true,
              includedInSummary: true,
            ),
            HealthVolume(
              id: 'Z:',
              kind: HealthDriveKind.remote,
              hasCapacity: false,
            ),
          ],
        ),
      );

    final labels = view.storageRows.map((r) => r.label).toList();
    expect(labels.any((l) => l.startsWith('C:')), isTrue);
    expect(labels.any((l) => l.contains('D:')), isTrue);
    expect(labels.any((l) => l.contains('Z:') && l.contains('Network')), isTrue);
    expect(labels, contains('Read Speed'));
    expect(labels, contains('Write Speed'));
    expect(labels, isNot(contains('Disk Usage')));
  });
}
