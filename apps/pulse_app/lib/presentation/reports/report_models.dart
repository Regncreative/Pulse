import 'package:pulse_protocol/pulse_wire.dart' show InventoryDomainId;

/// Report kinds available on the Reports page.
enum ReportTemplate {
  healthSnapshot,
  timeline,
  diagnostics,
  hardwareInventory,
  serviceInventory,
  driverInventory,
  softwareInventory,
  systemInventory,
}

/// On-disk export encodings.
enum ReportFormat {
  json,
  csv,
  html,
  pdf,
}

extension ReportTemplateX on ReportTemplate {
  String get title => switch (this) {
        ReportTemplate.healthSnapshot => 'System Health snapshot',
        ReportTemplate.timeline => 'Timeline events',
        ReportTemplate.diagnostics => 'Diagnostics',
        ReportTemplate.hardwareInventory => 'Hardware inventory',
        ReportTemplate.serviceInventory => 'Service inventory',
        ReportTemplate.driverInventory => 'Driver inventory',
        ReportTemplate.softwareInventory => 'Software inventory',
        ReportTemplate.systemInventory => 'System inventory',
      };

  String get description => switch (this) {
        ReportTemplate.healthSnapshot =>
          'Current CPU, memory, GPU, disk, and network metrics plus system identity.',
        ReportTemplate.timeline =>
          'Events currently loaded in the Timeline session.',
        ReportTemplate.diagnostics =>
          'Service identity, IPC stats, pipeline stages, and client metrics.',
        ReportTemplate.hardwareInventory =>
          'USB and PCI device catalogs from the Inventory Engine (SetupAPI).',
        ReportTemplate.serviceInventory =>
          'Windows services from the Inventory Engine (SCM SERVICE_WIN32).',
        ReportTemplate.driverInventory =>
          'Driver services from the Inventory Engine (SCM SERVICE_DRIVER subset).',
        ReportTemplate.softwareInventory =>
          'Installed software from Inventory (machine-wide Uninstall registry).',
        ReportTemplate.systemInventory =>
          'Motherboard, BIOS, CPU, memory, storage, and network adapters '
              'from the Inventory Engine (SMBIOS + SetupAPI).',
      };

  String get fileStem => switch (this) {
        ReportTemplate.healthSnapshot => 'pulse-health',
        ReportTemplate.timeline => 'pulse-timeline',
        ReportTemplate.diagnostics => 'pulse-diagnostics',
        ReportTemplate.hardwareInventory => 'pulse-hardware',
        ReportTemplate.serviceInventory => 'pulse-services',
        ReportTemplate.driverInventory => 'pulse-drivers',
        ReportTemplate.softwareInventory => 'pulse-software',
        ReportTemplate.systemInventory => 'pulse-system-inventory',
      };

  /// CSV fits tabular templates; diagnostics is structured JSON/HTML/PDF only.
  bool get supportsCsv => switch (this) {
        ReportTemplate.diagnostics => false,
        _ => true,
      };

  bool get usesInventoryEngine => switch (this) {
        ReportTemplate.hardwareInventory ||
        ReportTemplate.serviceInventory ||
        ReportTemplate.driverInventory ||
        ReportTemplate.softwareInventory ||
        ReportTemplate.systemInventory =>
          true,
        _ => false,
      };

  InventoryDomainId? get inventoryDomain => switch (this) {
        ReportTemplate.serviceInventory => InventoryDomainId.services,
        ReportTemplate.driverInventory => InventoryDomainId.drivers,
        ReportTemplate.softwareInventory => InventoryDomainId.software,
        ReportTemplate.hardwareInventory => null, // USB + PCI pair
        ReportTemplate.systemInventory =>
          null, // motherboard/bios/cpu/memory/storage/network sextet
        _ => null,
      };

  /// P2 System Inventory domains (SSOT for the [systemInventory] template).
  static const List<InventoryDomainId> systemInventoryDomains = [
    InventoryDomainId.motherboard,
    InventoryDomainId.bios,
    InventoryDomainId.cpu,
    InventoryDomainId.memoryModules,
    InventoryDomainId.storage,
    InventoryDomainId.networkAdapters,
  ];
}

extension ReportFormatX on ReportFormat {
  String get label => switch (this) {
        ReportFormat.json => 'JSON',
        ReportFormat.csv => 'CSV',
        ReportFormat.html => 'HTML',
        ReportFormat.pdf => 'PDF',
      };

  String get fileExtension => switch (this) {
        ReportFormat.json => 'json',
        ReportFormat.csv => 'csv',
        ReportFormat.html => 'html',
        ReportFormat.pdf => 'pdf',
      };
}
