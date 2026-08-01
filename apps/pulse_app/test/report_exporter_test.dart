import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/presentation/reports/report_exporter.dart';
import 'package:pulse/presentation/reports/report_models.dart';
import 'package:pulse_protocol/pulse_wire.dart';

void main() {
  group('ReportExporter JSON', () {
    test('encodes health snapshot metrics', () {
      final health = HealthSnapshot(
        info: HealthStaticInfo(
          windowsEdition: 'Windows 11 Pro',
          windowsVersion: '24H2',
          cpuModel: 'Test CPU',
          gpuModel: 'Test GPU',
          installedRamBytes: 16 * 1024 * 1024 * 1024,
        ),
        sample: HealthSample(
          unixMs: 1700000000000,
          hasCpuPercent: true,
          cpuPercent: 42.5,
          memoryUsedBytes: 8 * 1024 * 1024 * 1024,
          memoryTotalBytes: 16 * 1024 * 1024 * 1024,
        ),
      );

      final json = ReportExporter.buildJson(
        ReportExportInput(
          template: ReportTemplate.healthSnapshot,
          format: ReportFormat.json,
          health: health,
        ),
      );

      expect(json, contains('"pulse_export": "pulse-health"'));
      expect(json, contains('"template": "healthSnapshot"'));
      expect(json, contains('Test CPU'));
      expect(json, contains('42.5'));
      expect(json, contains('cpu_percent'));
    });

    test('encodes timeline events', () {
      final events = [
        TimelineEvent(
          eventId: 'e1',
          title: 'Explorer restarted',
          summary: 'Windows restarted Explorer.',
          severity: Severity.warning,
          providerName: 'Application Error',
          timestampIso: '2026-08-01T12:00:00Z',
        ),
      ];

      final json = ReportExporter.buildJson(
        ReportExportInput(
          template: ReportTemplate.timeline,
          format: ReportFormat.json,
          events: events,
        ),
      );

      expect(json, contains('"count": 1'));
      expect(json, contains('Explorer restarted'));
      expect(json, contains('warning'));
      expect(json, contains('Application Error'));
    });

    test('encodes diagnostics fields', () {
      final snap = DiagnosticsSnapshot(
        serviceVersion: '0.1.3',
        protocolVersion: 1,
        runMode: 'service',
        windowsEdition: 'Windows 11',
        liveSubscribed: true,
        liveChannel: 'System',
      );

      final json = ReportExporter.buildJson(
        ReportExportInput(
          template: ReportTemplate.diagnostics,
          format: ReportFormat.json,
          diagnostics: snap,
        ),
      );

      expect(json, contains('"template": "diagnostics"'));
      expect(json, contains('0.1.3'));
      expect(json, contains('live_subscribed'));
      expect(json, contains('System'));
    });

    test('encodes hardware inventory', () {
      final health = HealthSnapshot(
        info: HealthStaticInfo(
          cpuModel: 'Ryzen 7',
          gpuModel: 'RTX',
          diskModel: 'NVMe',
          installedRamBytes: 32,
        ),
      );

      final json = ReportExporter.buildJson(
        ReportExportInput(
          template: ReportTemplate.hardwareInventory,
          format: ReportFormat.json,
          health: health,
        ),
      );

      expect(json, contains('"pulse_export": "pulse-hardware"'));
      expect(json, contains('Ryzen 7'));
      expect(json, contains('NVMe'));
    });
  });

  group('ReportExporter CSV', () {
    test('timeline CSV has required columns and escaped cells', () {
      final events = [
        TimelineEvent(
          title: 'Title, with comma',
          summary: 'Summary "quoted"',
          severity: Severity.error,
          providerName: 'Provider',
          timestampIso: '2026-08-01T12:00:00Z',
        ),
      ];

      final csv = ReportExporter.buildCsv(
        ReportExportInput(
          template: ReportTemplate.timeline,
          format: ReportFormat.csv,
          events: events,
        ),
      );

      expect(csv, startsWith('time,severity,provider,title,summary\n'));
      expect(csv, contains('error'));
      expect(csv, contains('Provider'));
      expect(csv, contains('"Title, with comma"'));
      expect(csv, contains('"Summary ""quoted"""'));
    });

    test('health CSV is key,value rows', () {
      final health = HealthSnapshot(
        sample: HealthSample(
          hasCpuPercent: true,
          cpuPercent: 10,
          memoryUsedBytes: 100,
          memoryTotalBytes: 200,
        ),
      );

      final csv = ReportExporter.buildCsv(
        ReportExportInput(
          template: ReportTemplate.healthSnapshot,
          format: ReportFormat.csv,
          health: health,
        ),
      );

      expect(csv, startsWith('key,value\n'));
      expect(csv, contains('cpu_percent,10.0'));
      expect(csv, contains('memory_used_bytes,100'));
    });

    test('hardware CSV is key,value rows', () {
      final csv = ReportExporter.buildCsv(
        ReportExportInput(
          template: ReportTemplate.hardwareInventory,
          format: ReportFormat.csv,
          health: HealthSnapshot(
            info: HealthStaticInfo(cpuModel: 'Test CPU', cpuCores: 8),
          ),
        ),
      );

      expect(csv, startsWith('key,value\n'));
      expect(csv, contains('cpu_model,Test CPU'));
      expect(csv, contains('cpu_cores,8'));
    });

    test('diagnostics rejects CSV', () {
      expect(
        () => ReportExporter.buildCsv(
          const ReportExportInput(
            template: ReportTemplate.diagnostics,
            format: ReportFormat.csv,
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  test('ReportTemplate.supportsCsv matches plan', () {
    expect(ReportTemplate.healthSnapshot.supportsCsv, isTrue);
    expect(ReportTemplate.timeline.supportsCsv, isTrue);
    expect(ReportTemplate.hardwareInventory.supportsCsv, isTrue);
    expect(ReportTemplate.diagnostics.supportsCsv, isFalse);
  });
}
