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

    test('encodes hardware inventory from Inventory USB/PCI', () {
      final json = ReportExporter.buildJson(
        ReportExportInput(
          template: ReportTemplate.hardwareInventory,
          format: ReportFormat.json,
          inventoryUsb: InventoryDomainSnapshot(
            domain: InventoryDomainId.usb,
            status: InventoryStatus.available,
            generation: 1,
            usb: [
              InventoryUsbEntry(
                id: r'USB\VID_1234&PID_5678\1',
                description: 'Test USB Device',
                manufacturer: 'PulseLab',
              ),
            ],
          ),
          inventoryPci: InventoryDomainSnapshot(
            domain: InventoryDomainId.pci,
            status: InventoryStatus.available,
            generation: 2,
            pci: [
              InventoryPciEntry(
                id: r'PCI\VEN_10DE&DEV_2684\0',
                description: 'Test GPU',
                hardwareId: r'PCI\VEN_10DE&DEV_2684',
              ),
            ],
          ),
        ),
      );

      expect(json, contains('"pulse_export": "pulse-hardware"'));
      expect(json, contains('"source": "inventory_engine"'));
      expect(json, contains('Test USB Device'));
      expect(json, contains('Test GPU'));
      expect(json, isNot(contains('Ryzen')));
    });

    test('encodes system inventory from Inventory P2 domains, not Health',
        () {
      final json = ReportExporter.buildJson(
        ReportExportInput(
          template: ReportTemplate.systemInventory,
          format: ReportFormat.json,
          // Health present but must NOT be the identity source for this
          // template — System Inventory identity must come from Inventory.
          health: HealthSnapshot(
            info: HealthStaticInfo(cpuModel: 'Health CPU (must not appear)'),
          ),
          inventoryMotherboard: InventoryDomainSnapshot(
            domain: InventoryDomainId.motherboard,
            status: InventoryStatus.available,
            generation: 1,
            motherboard: [
              InventoryMotherboardEntry(
                id: 'motherboard',
                manufacturer: 'PulseLab',
                product: 'Test Board X570',
              ),
            ],
          ),
          inventoryCpu: InventoryDomainSnapshot(
            domain: InventoryDomainId.cpu,
            status: InventoryStatus.available,
            generation: 2,
            cpu: [
              InventoryCpuEntry(
                id: 'cpu',
                name: 'Test CPU 9000X',
                manufacturer: 'PulseLab',
                hasPhysicalCores: true,
                physicalCores: 8,
              ),
            ],
          ),
        ),
      );

      expect(json, contains('"pulse_export": "pulse-system-inventory"'));
      expect(json, contains('"source": "inventory_engine"'));
      expect(json, contains('Test Board X570'));
      expect(json, contains('Test CPU 9000X'));
      expect(json, isNot(contains('Health CPU')));
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

    test('hardware CSV uses Inventory USB/PCI catalogs', () {
      final csv = ReportExporter.buildCsv(
        ReportExportInput(
          template: ReportTemplate.hardwareInventory,
          format: ReportFormat.csv,
          inventoryUsb: InventoryDomainSnapshot(
            domain: InventoryDomainId.usb,
            status: InventoryStatus.available,
            usb: [
              InventoryUsbEntry(id: r'USB\VID_1\1', description: 'Hub'),
            ],
          ),
          inventoryPci: InventoryDomainSnapshot(
            domain: InventoryDomainId.pci,
            status: InventoryStatus.partial,
            statusDetail: 'truncated',
            truncated: true,
            pci: [
              InventoryPciEntry(id: r'PCI\VEN_1\0', description: 'Bridge'),
            ],
          ),
        ),
      );

      expect(csv, contains('source=inventory_engine'));
      expect(csv, contains('## usb'));
      expect(csv, contains('## pci'));
      expect(csv, contains('Hub'));
      expect(csv, contains('Bridge'));
    });

    test('service inventory CSV uses Inventory Engine rows', () {
      final csv = ReportExporter.buildCsv(
        ReportExportInput(
          template: ReportTemplate.serviceInventory,
          format: ReportFormat.csv,
          inventory: InventoryDomainSnapshot(
            domain: InventoryDomainId.services,
            status: InventoryStatus.available,
            generation: 3,
            services: [
              InventoryServiceEntry(
                id: 'EventLog',
                displayName: 'Windows Event Log',
                state: 'running',
                startType: 'automatic',
              ),
            ],
          ),
        ),
      );

      expect(csv, contains('status,status_detail,generation,truncated,count'));
      expect(csv, contains('EventLog'));
      expect(csv, contains('Windows Event Log'));
    });

    test('system inventory CSV covers all six P2 domains', () {
      final csv = ReportExporter.buildCsv(
        ReportExportInput(
          template: ReportTemplate.systemInventory,
          format: ReportFormat.csv,
          inventoryMotherboard: InventoryDomainSnapshot(
            domain: InventoryDomainId.motherboard,
            status: InventoryStatus.available,
            motherboard: [
              InventoryMotherboardEntry(id: 'motherboard', product: 'Board'),
            ],
          ),
          inventoryStorage: InventoryDomainSnapshot(
            domain: InventoryDomainId.storage,
            status: InventoryStatus.available,
            storage: [
              InventoryStorageEntry(id: r'disk\0', model: 'Test SSD'),
            ],
          ),
        ),
      );

      expect(csv, contains('source=inventory_engine'));
      expect(csv, contains('## motherboard'));
      expect(csv, contains('## bios'));
      expect(csv, contains('## cpu'));
      expect(csv, contains('## memory_modules'));
      expect(csv, contains('## storage'));
      expect(csv, contains('## network_adapters'));
      expect(csv, contains('Board'));
      expect(csv, contains('Test SSD'));
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
    expect(ReportTemplate.systemInventory.supportsCsv, isTrue);
    expect(ReportTemplate.diagnostics.supportsCsv, isFalse);
  });

  test('ReportTemplate.systemInventory uses the Inventory Engine', () {
    expect(ReportTemplate.systemInventory.usesInventoryEngine, isTrue);
    expect(ReportTemplate.systemInventory.inventoryDomain, isNull);
    expect(ReportTemplateX.systemInventoryDomains, [
      InventoryDomainId.motherboard,
      InventoryDomainId.bios,
      InventoryDomainId.cpu,
      InventoryDomainId.memoryModules,
      InventoryDomainId.storage,
      InventoryDomainId.networkAdapters,
    ]);
  });
}
