import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pulse_protocol/pulse_constants.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../application/client_frame_metrics.dart';
import '../../application/settings_controller.dart';
import '../../features/timeline/timeline_display.dart';
import '../../features/timeline/timeline_export.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../inventory/inventory_detail_model.dart';
import 'report_models.dart';

/// Bundled inputs for a single Reports export.
class ReportExportInput {
  const ReportExportInput({
    required this.template,
    required this.format,
    this.health,
    this.inventory,
    this.inventoryUsb,
    this.inventoryPci,
    this.inventoryMotherboard,
    this.inventoryBios,
    this.inventoryCpu,
    this.inventoryMemoryModules,
    this.inventoryStorage,
    this.inventoryNetworkAdapters,
    this.events = const [],
    this.diagnostics,
    this.ipcStatus,
    this.frameMetrics,
    this.snapshotError,
    this.darkHtml = true,
  });

  final ReportTemplate template;
  final ReportFormat format;
  final HealthSnapshot? health;
  /// Inventory Engine snapshot for service / driver / software templates.
  final InventoryDomainSnapshot? inventory;
  /// Hardware inventory SSOT (USB domain).
  final InventoryDomainSnapshot? inventoryUsb;
  /// Hardware inventory SSOT (PCI domain).
  final InventoryDomainSnapshot? inventoryPci;
  /// System inventory SSOT (P2 domains) — motherboard.
  final InventoryDomainSnapshot? inventoryMotherboard;
  /// System inventory SSOT (P2 domains) — BIOS.
  final InventoryDomainSnapshot? inventoryBios;
  /// System inventory SSOT (P2 domains) — CPU.
  final InventoryDomainSnapshot? inventoryCpu;
  /// System inventory SSOT (P2 domains) — memory modules.
  final InventoryDomainSnapshot? inventoryMemoryModules;
  /// System inventory SSOT (P2 domains) — storage devices.
  final InventoryDomainSnapshot? inventoryStorage;
  /// System inventory SSOT (P2 domains) — network adapters.
  final InventoryDomainSnapshot? inventoryNetworkAdapters;
  final List<TimelineEvent> events;
  final DiagnosticsSnapshot? diagnostics;
  final IpcStatus? ipcStatus;
  final ClientFrameMetrics? frameMetrics;
  final String? snapshotError;
  final bool darkHtml;
}

/// Builds report bytes/strings and writes under Documents/Pulse/Reports
/// (or [SettingsController.exportDirectory] when set).
class ReportExporter {
  ReportExporter({this.settings});

  final SettingsController? settings;

  /// Resolves the export directory: custom path, else Documents/Pulse/Reports.
  Future<Directory> resolveReportsDirectory() async {
    final custom = settings?.exportDirectory.trim() ?? '';
    if (custom.isNotEmpty) {
      final dir = Directory(custom);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}Pulse'
      '${Platform.pathSeparator}Reports',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Builds content and writes a file. Returns the absolute path.
  Future<String> export(ReportExportInput input) async {
    if (input.format == ReportFormat.csv && !input.template.supportsCsv) {
      throw ArgumentError(
        'CSV is not supported for ${input.template.title} reports.',
      );
    }

    final dir = await resolveReportsDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final name =
        '${input.template.fileStem}-$stamp.${input.format.fileExtension}';
    final path = '${dir.path}${Platform.pathSeparator}$name';

    switch (input.format) {
      case ReportFormat.json:
        await File(path).writeAsString(buildJson(input), flush: true);
      case ReportFormat.csv:
        await File(path).writeAsString(buildCsv(input), flush: true);
      case ReportFormat.html:
        await File(path).writeAsString(buildHtml(input), flush: true);
      case ReportFormat.pdf:
        await File(path).writeAsBytes(await buildPdf(input), flush: true);
    }
    return path;
  }

  // ─── Pure builders (unit-tested for JSON / CSV) ─────────────────────────

  static String buildJson(ReportExportInput input) {
    final payload = _payloadMap(input);
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static String buildCsv(ReportExportInput input) {
    switch (input.template) {
      case ReportTemplate.timeline:
        return _timelineCsv(input.events);
      case ReportTemplate.healthSnapshot:
        return _keyValueCsv(healthMetricsRows(input.health));
      case ReportTemplate.hardwareInventory:
        return hardwareInventoryCsv(input.inventoryUsb, input.inventoryPci);
      case ReportTemplate.systemInventory:
        return systemInventoryCsv(input);
      case ReportTemplate.serviceInventory:
      case ReportTemplate.driverInventory:
      case ReportTemplate.softwareInventory:
        return inventoryDomainCsv(input.inventory);
      case ReportTemplate.diagnostics:
        throw ArgumentError('CSV is not supported for diagnostics reports.');
    }
  }

  static String buildHtml(ReportExportInput input) {
    final dark = input.darkHtml;
    final bg = dark ? '#0f1115' : '#f5f6f8';
    final surface = dark ? '#1a1d24' : '#ffffff';
    final text = dark ? '#e8eaed' : '#1a1d24';
    final muted = dark ? '#9aa0a6' : '#5f6368';
    final accent = '#4c8bf5';
    final border = dark ? '#2a2f3a' : '#dadce0';
    final exportedAt = DateTime.now().toIso8601String();
    final identity = _systemIdentity(input);
    final sections = _htmlSections(input);

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>Pulse — ${input.template.title}</title>
<style>
  body { font-family: Segoe UI, system-ui, sans-serif; background: $bg; color: $text;
         margin: 0; padding: 32px 40px; line-height: 1.45; }
  h1 { font-size: 28px; font-weight: 600; letter-spacing: -0.4px; margin: 0 0 4px; }
  .brand { color: $accent; font-weight: 700; font-size: 14px; letter-spacing: 0.08em;
           text-transform: uppercase; margin-bottom: 12px; }
  .meta { color: $muted; font-size: 13px; margin-bottom: 28px; }
  section { background: $surface; border: 1px solid $border; border-radius: 10px;
            padding: 18px 20px; margin-bottom: 16px; }
  h2 { font-size: 15px; margin: 0 0 12px; font-weight: 600; }
  h3 { font-size: 13px; margin: 14px 0 6px; font-weight: 600; color: $muted; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid $border;
           vertical-align: top; }
  th { color: $muted; font-weight: 500; width: 32%; }
  td { word-break: break-word; }
</style>
</head>
<body>
  <div class="brand">Pulse</div>
  <h1>${_escapeHtml(input.template.title)}</h1>
  <div class="meta">Exported $exportedAt · Pulse $kAppVersion</div>
  <section>
    <h2>System identity</h2>
    ${_kvTableHtml(identity)}
  </section>
  $sections
</body>
</html>
''';
  }

  static Future<Uint8List> buildPdf(ReportExportInput input) async {
    final doc = pw.Document();
    final exportedAt = DateTime.now().toIso8601String();
    final identity = _systemIdentity(input);
    final tables = _pdfTables(input);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Pulse',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#4c8bf5'),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              input.template.title,
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Exported $exportedAt · Pulse $kAppVersion',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.Text(
            'System identity',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _pdfKeyValueTable(identity),
          pw.SizedBox(height: 16),
          ...tables,
        ],
      ),
    );
    return doc.save();
  }

  // ─── Row helpers (public for tests) ─────────────────────────────────────

  static List<(String, String)> healthMetricsRows(HealthSnapshot? health) {
    final sample = health?.sample;
    final info = health?.info;
    if (sample == null && info == null) {
      return const [('status', 'No health snapshot available')];
    }
    final rows = <(String, String)>[];
    if (info != null) {
      rows.addAll([
        ('windows_edition', info.windowsEdition),
        ('windows_version', info.windowsVersion),
        ('cpu_model', info.cpuModel),
        ('gpu_model', info.gpuModel),
        ('installed_ram_bytes', '${info.installedRamBytes}'),
        ('primary_storage_bytes', '${info.primaryStorageBytes}'),
        ('active_network_adapter', info.activeNetworkAdapter),
      ]);
    }
    if (sample != null) {
      rows.addAll([
        ('sample_unix_ms', '${sample.unixMs}'),
        if (sample.hasCpuPercent)
          ('cpu_percent', sample.cpuPercent.toStringAsFixed(1)),
        ('memory_used_bytes', '${sample.memoryUsedBytes}'),
        ('memory_total_bytes', '${sample.memoryTotalBytes}'),
        if (sample.hasGpuPercent)
          ('gpu_percent', sample.gpuPercent.toStringAsFixed(1)),
        if (sample.hasNetDownloadBps)
          ('net_download_bps', sample.netDownloadBps.toStringAsFixed(0)),
        if (sample.hasNetUploadBps)
          ('net_upload_bps', sample.netUploadBps.toStringAsFixed(0)),
        if (sample.hasDiskReadBps)
          ('disk_read_bps', sample.diskReadBps.toStringAsFixed(0)),
        if (sample.hasDiskWriteBps)
          ('disk_write_bps', sample.diskWriteBps.toStringAsFixed(0)),
        ('disk_used_bytes', '${sample.diskUsedBytes}'),
        ('disk_total_bytes', '${sample.diskTotalBytes}'),
        ('uptime_ms', '${sample.uptimeMs}'),
        if (sample.ipv4.isNotEmpty) ('ipv4', sample.ipv4),
        if (sample.gateway.isNotEmpty) ('gateway', sample.gateway),
      ]);
    }
    return rows;
  }

  /// Deprecated Health-static hardware flatten. Superseded by Inventory
  /// USB/PCI (Hardware report) and Inventory P2 domains (System report).
  /// Retained only for callers that have not migrated; not used by any
  /// current report SSOT.
  static List<(String, String)> healthStaticHardwareRows(HealthStaticInfo? info) {
    if (info == null) {
      return const [('status', 'No hardware inventory available')];
    }
    return [
      ('windows_edition', info.windowsEdition),
      ('windows_version', info.windowsVersion),
      ('cpu_model', info.cpuModel),
      ('cpu_architecture', info.cpuArchitecture),
      ('cpu_cores', '${info.cpuCores}'),
      ('cpu_logical_processors', '${info.cpuLogicalProcessors}'),
      ('cpu_base_mhz', '${info.cpuBaseMhz}'),
      ('cpu_sockets', '${info.cpuSockets}'),
      ('cpu_virtualization_enabled', '${info.cpuVirtualizationEnabled}'),
      ('gpu_model', info.gpuModel),
      ('gpu_vendor', info.gpuVendor),
      ('gpu_driver_version', info.gpuDriverVersion),
      ('gpu_dedicated_bytes', '${info.gpuDedicatedBytes}'),
      ('gpu_shared_bytes', '${info.gpuSharedBytes}'),
      ('installed_ram_bytes', '${info.installedRamBytes}'),
      ('mem_ddr_generation', info.memDdrGeneration),
      if (info.hasMemSpeedMhz) ('mem_speed_mhz', '${info.memSpeedMhz}'),
      ('disk_model', info.diskModel),
      ('disk_interface', info.diskInterface),
      ('disk_bus', info.diskBus),
      ('primary_storage_bytes', '${info.primaryStorageBytes}'),
      ('active_network_adapter', info.activeNetworkAdapter),
      ('net_manufacturer', info.netManufacturer),
      ('net_mac_address', info.netMacAddress),
      ('net_driver_version', info.netDriverVersion),
      if (info.hasNetLinkSpeedBps)
        ('net_link_speed_bps', '${info.netLinkSpeedBps}'),
    ];
  }

  /// Hardware report CSV — Inventory USB + PCI catalogs (ADR-011 SSOT).
  static String hardwareInventoryCsv(
    InventoryDomainSnapshot? usb,
    InventoryDomainSnapshot? pci,
  ) {
    final buf = StringBuffer()
      ..writeln('# pulse-hardware')
      ..writeln('# source=inventory_engine')
      ..writeln()
      ..writeln('## usb')
      ..write(inventoryDomainCsv(usb))
      ..writeln()
      ..writeln('## pci')
      ..write(inventoryDomainCsv(pci));
    return buf.toString();
  }

  /// Tabular CSV for Inventory Engine catalogs (ADR-011 SSOT).
  static String inventoryDomainCsv(InventoryDomainSnapshot? snap) {
    if (snap == null) {
      return 'status,status_detail\nerror,No inventory snapshot\n';
    }
    final meta = StringBuffer()
      ..writeln('status,status_detail,generation,truncated,count')
      ..writeln(
        '${_csvCell(snap.status.name)},${_csvCell(snap.statusDetail)},'
        '${snap.generation},${snap.truncated},'
        '${_inventoryItemCount(snap)}',
      )
      ..writeln();

    switch (snap.domain) {
      case InventoryDomainId.services:
        meta.writeln(
          'id,display_name,state,start_type,account,binary_path,description',
        );
        for (final e in snap.services) {
          meta.writeln(
            '${_csvCell(e.id)},${_csvCell(e.displayName)},${_csvCell(e.state)},'
            '${_csvCell(e.startType)},${_csvCell(e.account)},'
            '${_csvCell(e.binaryPath)},${_csvCell(e.description)}',
          );
        }
      case InventoryDomainId.drivers:
        meta.writeln(
          'id,display_name,state,start_type,driver_type,binary_path,description',
        );
        for (final e in snap.drivers) {
          meta.writeln(
            '${_csvCell(e.id)},${_csvCell(e.displayName)},${_csvCell(e.state)},'
            '${_csvCell(e.startType)},${_csvCell(e.driverType)},'
            '${_csvCell(e.binaryPath)},${_csvCell(e.description)}',
          );
        }
      case InventoryDomainId.software:
        meta.writeln(
          'id,display_name,version,publisher,install_date,architecture,'
          'system_component,estimated_size_bytes',
        );
        for (final e in snap.software) {
          meta.writeln(
            '${_csvCell(e.id)},${_csvCell(e.displayName)},${_csvCell(e.version)},'
            '${_csvCell(e.publisher)},${_csvCell(e.installDate)},'
            '${_csvCell(e.architecture)},${e.systemComponent},'
            '${e.hasEstimatedSize ? e.estimatedSizeBytes : ''}',
          );
        }
      case InventoryDomainId.usb:
        meta.writeln(
          'id,description,hardware_id,manufacturer,service,class_name,'
          'class_guid,problem_code',
        );
        for (final e in snap.usb) {
          meta.writeln(
            '${_csvCell(e.id)},${_csvCell(e.description)},'
            '${_csvCell(e.hardwareId)},${_csvCell(e.manufacturer)},'
            '${_csvCell(e.service)},${_csvCell(e.className)},'
            '${_csvCell(e.classGuid)},'
            '${e.hasProblemCode ? e.problemCode : ''}',
          );
        }
      case InventoryDomainId.pci:
        meta.writeln(
          'id,description,hardware_id,manufacturer,service,class_name,'
          'class_guid,location_info,problem_code',
        );
        for (final e in snap.pci) {
          meta.writeln(
            '${_csvCell(e.id)},${_csvCell(e.description)},'
            '${_csvCell(e.hardwareId)},${_csvCell(e.manufacturer)},'
            '${_csvCell(e.service)},${_csvCell(e.className)},'
            '${_csvCell(e.classGuid)},${_csvCell(e.locationInfo)},'
            '${e.hasProblemCode ? e.problemCode : ''}',
          );
        }
      case InventoryDomainId.motherboard:
        meta.writeln(
          'id,manufacturer,product,version,serial_number,asset_tag,'
          'location_in_chassis,board_type',
        );
        for (final e in snap.motherboard) {
          meta.writeln(
            '${_csvCell(e.id)},${_csvCell(e.manufacturer)},'
            '${_csvCell(e.product)},${_csvCell(e.version)},'
            '${_csvCell(e.serialNumber)},${_csvCell(e.assetTag)},'
            '${_csvCell(e.locationInChassis)},${_csvCell(e.boardType)}',
          );
        }
      case InventoryDomainId.bios:
        meta.writeln(
          'id,vendor,version,release_date,major_release,minor_release,'
          'rom_size_bytes,uefi_capable',
        );
        for (final e in snap.bios) {
          meta.writeln(
            '${_csvCell(e.id)},${_csvCell(e.vendor)},${_csvCell(e.version)},'
            '${_csvCell(e.releaseDate)},'
            '${e.hasMajorRelease ? e.majorRelease : ''},'
            '${e.hasMinorRelease ? e.minorRelease : ''},'
            '${e.hasRomSizeBytes ? e.romSizeBytes : ''},'
            '${e.hasUefiCapable ? e.uefiCapable : ''}',
          );
        }
      case InventoryDomainId.cpu:
        meta.writeln(
          'id,name,manufacturer,architecture,sockets,physical_cores,'
          'logical_processors,base_clock_mhz,numa_nodes,l1_cache_bytes,'
          'l2_cache_bytes,l3_cache_bytes,instruction_set,smt_enabled,'
          'virtualization_vendor',
        );
        for (final e in snap.cpu) {
          meta.writeln(
            '${_csvCell(e.id)},${_csvCell(e.name)},${_csvCell(e.manufacturer)},'
            '${_csvCell(e.architecture)},'
            '${e.hasSockets ? e.sockets : ''},'
            '${e.hasPhysicalCores ? e.physicalCores : ''},'
            '${e.hasLogicalProcessors ? e.logicalProcessors : ''},'
            '${e.hasBaseClockMhz ? e.baseClockMhz : ''},'
            '${e.hasNumaNodes ? e.numaNodes : ''},'
            '${e.hasL1CacheBytes ? e.l1CacheBytes : ''},'
            '${e.hasL2CacheBytes ? e.l2CacheBytes : ''},'
            '${e.hasL3CacheBytes ? e.l3CacheBytes : ''},'
            '${_csvCell(e.instructionSet)},'
            '${e.hasSmtEnabled ? e.smtEnabled : ''},'
            '${_csvCell(e.virtualizationVendor)}',
          );
        }
      case InventoryDomainId.memoryModules:
        meta.writeln(
          'id,bank_locator,manufacturer,part_number,serial_number,'
          'size_bytes,speed_mts,configured_speed_mts,form_factor,'
          'memory_type,is_ecc,total_width_bits,data_width_bits,'
          'configured_voltage_mv,populated',
        );
        for (final e in snap.memoryModules) {
          meta.writeln(
            '${_csvCell(e.id)},${_csvCell(e.bankLocator)},'
            '${_csvCell(e.manufacturer)},${_csvCell(e.partNumber)},'
            '${_csvCell(e.serialNumber)},'
            '${e.hasSizeBytes ? e.sizeBytes : ''},'
            '${e.hasSpeedMts ? e.speedMts : ''},'
            '${e.hasConfiguredSpeedMts ? e.configuredSpeedMts : ''},'
            '${_csvCell(e.formFactor)},${_csvCell(e.memoryType)},'
            '${e.hasIsEcc ? e.isEcc : ''},'
            '${e.hasTotalWidthBits ? e.totalWidthBits : ''},'
            '${e.hasDataWidthBits ? e.dataWidthBits : ''},'
            '${e.hasConfiguredVoltageMv ? e.configuredVoltageMv : ''},'
            '${e.populated}',
          );
        }
      case InventoryDomainId.storage:
        meta.writeln(
          'id,device_path,physical_drive_number,model,vendor,'
          'serial_number,firmware_revision,bus_type,media_type,'
          'size_bytes,sector_size_bytes,partition_style,is_removable,'
          'trim_supported,manufacturer,description',
        );
        for (final e in snap.storage) {
          meta.writeln(
            '${_csvCell(e.id)},${_csvCell(e.devicePath)},'
            '${e.hasPhysicalDriveNumber ? e.physicalDriveNumber : ''},'
            '${_csvCell(e.model)},${_csvCell(e.vendor)},'
            '${_csvCell(e.serialNumber)},${_csvCell(e.firmwareRevision)},'
            '${_csvCell(e.busType)},${_csvCell(e.mediaType)},'
            '${e.hasSizeBytes ? e.sizeBytes : ''},'
            '${e.hasSectorSizeBytes ? e.sectorSizeBytes : ''},'
            '${_csvCell(e.partitionStyle)},'
            '${e.hasIsRemovable ? e.isRemovable : ''},'
            '${e.hasTrimSupported ? e.trimSupported : ''},'
            '${_csvCell(e.manufacturer)},${_csvCell(e.description)}',
          );
        }
      case InventoryDomainId.networkAdapters:
        meta.writeln(
          'id,friendly_name,description,mac_address,connection_type,'
          'if_index,mtu,operational_status,dhcp_enabled,link_speed_bps,'
          'is_loopback,ipv4_addresses,ipv6_addresses,gateway_addresses,'
          'dns_addresses,driver_provider,driver_version,driver_date',
        );
        for (final e in snap.networkAdapters) {
          meta.writeln(
            '${_csvCell(e.id)},${_csvCell(e.friendlyName)},'
            '${_csvCell(e.description)},${_csvCell(e.macAddress)},'
            '${_csvCell(e.connectionType)},'
            '${e.hasIfIndex ? e.ifIndex : ''},'
            '${e.hasMtu ? e.mtu : ''},'
            '${_csvCell(e.operationalStatus)},'
            '${e.hasDhcpEnabled ? e.dhcpEnabled : ''},'
            '${e.hasLinkSpeedBps ? e.linkSpeedBps : ''},'
            '${e.isLoopback},'
            '${_csvCell(e.ipv4Addresses.join('|'))},'
            '${_csvCell(e.ipv6Addresses.join('|'))},'
            '${_csvCell(e.gatewayAddresses.join('|'))},'
            '${_csvCell(e.dnsAddresses.join('|'))},'
            '${_csvCell(e.driverProvider)},${_csvCell(e.driverVersion)},'
            '${_csvCell(e.driverDate)}',
          );
        }
      default:
        meta.writeln('note');
        meta.writeln(
          _csvCell('Unsupported inventory domain for this template'),
        );
    }
    return meta.toString();
  }

  static int _inventoryItemCount(InventoryDomainSnapshot snap) =>
      switch (snap.domain) {
        InventoryDomainId.services => snap.services.length,
        InventoryDomainId.drivers => snap.drivers.length,
        InventoryDomainId.software => snap.software.length,
        InventoryDomainId.usb => snap.usb.length,
        InventoryDomainId.pci => snap.pci.length,
        InventoryDomainId.motherboard => snap.motherboard.length,
        InventoryDomainId.bios => snap.bios.length,
        InventoryDomainId.cpu => snap.cpu.length,
        InventoryDomainId.memoryModules => snap.memoryModules.length,
        InventoryDomainId.storage => snap.storage.length,
        InventoryDomainId.networkAdapters => snap.networkAdapters.length,
        _ => 0,
      };

  /// System Inventory report CSV — P2 domains (ADR-011 SSOT). Not
  /// [healthStaticHardwareRows]; System identity now belongs to Inventory.
  static String systemInventoryCsv(ReportExportInput input) {
    final buf = StringBuffer()
      ..writeln('# pulse-system-inventory')
      ..writeln('# source=inventory_engine');
    for (final section in _systemInventorySections(input)) {
      buf
        ..writeln()
        ..writeln('## ${section.$1}')
        ..write(inventoryDomainCsv(section.$2));
    }
    return buf.toString();
  }

  static List<(String, InventoryDomainSnapshot?)> _systemInventorySections(
    ReportExportInput input,
  ) => [
        ('motherboard', input.inventoryMotherboard),
        ('bios', input.inventoryBios),
        ('cpu', input.inventoryCpu),
        ('memory_modules', input.inventoryMemoryModules),
        ('storage', input.inventoryStorage),
        ('network_adapters', input.inventoryNetworkAdapters),
      ];

  static Map<String, dynamic> inventoryDomainJson(
    InventoryDomainSnapshot? snap,
  ) {
    if (snap == null) {
      return {
        'status': 'error',
        'status_detail': 'No inventory snapshot',
      };
    }
    return {
      'domain': snap.domain.name,
      'status': snap.status.name,
      'status_detail': snap.statusDetail,
      'truncated': snap.truncated,
      'generation': snap.generation,
      'generated_at_unix_ms': snap.generatedAtUnixMs,
      'full_resync': snap.fullResync,
      'cache_ttl_ms': snap.cacheTtlMs,
      'count': _inventoryItemCount(snap),
      'services': [
        for (final e in snap.services)
          {
            'id': e.id,
            'display_name': e.displayName,
            'state': e.state,
            'start_type': e.startType,
            'account': e.account,
            'binary_path': e.binaryPath,
            'description': e.description,
          },
      ],
      'drivers': [
        for (final e in snap.drivers)
          {
            'id': e.id,
            'display_name': e.displayName,
            'state': e.state,
            'start_type': e.startType,
            'driver_type': e.driverType,
            'binary_path': e.binaryPath,
            'description': e.description,
          },
      ],
      'software': [
        for (final e in snap.software)
          {
            'id': e.id,
            'display_name': e.displayName,
            'version': e.version,
            'publisher': e.publisher,
            'install_date': e.installDate,
            'install_location': e.installLocation,
            if (e.hasEstimatedSize)
              'estimated_size_bytes': e.estimatedSizeBytes,
            'system_component': e.systemComponent,
            'architecture': e.architecture,
          },
      ],
      'usb': [
        for (final e in snap.usb)
          {
            'id': e.id,
            'description': e.description,
            'hardware_id': e.hardwareId,
            'manufacturer': e.manufacturer,
            'service': e.service,
            'class_name': e.className,
            'class_guid': e.classGuid,
            if (e.hasProblemCode) 'problem_code': e.problemCode,
          },
      ],
      'pci': [
        for (final e in snap.pci)
          {
            'id': e.id,
            'description': e.description,
            'hardware_id': e.hardwareId,
            'manufacturer': e.manufacturer,
            'service': e.service,
            'class_name': e.className,
            'class_guid': e.classGuid,
            'location_info': e.locationInfo,
            if (e.hasProblemCode) 'problem_code': e.problemCode,
          },
      ],
      'motherboard': [
        for (final e in snap.motherboard)
          {
            'id': e.id,
            'manufacturer': e.manufacturer,
            'product': e.product,
            'version': e.version,
            'serial_number': e.serialNumber,
            'asset_tag': e.assetTag,
            'location_in_chassis': e.locationInChassis,
            'board_type': e.boardType,
          },
      ],
      'bios': [
        for (final e in snap.bios)
          {
            'id': e.id,
            'vendor': e.vendor,
            'version': e.version,
            'release_date': e.releaseDate,
            if (e.hasMajorRelease) 'major_release': e.majorRelease,
            if (e.hasMinorRelease) 'minor_release': e.minorRelease,
            if (e.hasRomSizeBytes) 'rom_size_bytes': e.romSizeBytes,
            if (e.hasUefiCapable) 'uefi_capable': e.uefiCapable,
          },
      ],
      'cpu': [
        for (final e in snap.cpu)
          {
            'id': e.id,
            'name': e.name,
            'manufacturer': e.manufacturer,
            'architecture': e.architecture,
            if (e.hasSockets) 'sockets': e.sockets,
            if (e.hasPhysicalCores) 'physical_cores': e.physicalCores,
            if (e.hasLogicalProcessors)
              'logical_processors': e.logicalProcessors,
            if (e.hasBaseClockMhz) 'base_clock_mhz': e.baseClockMhz,
            if (e.hasNumaNodes) 'numa_nodes': e.numaNodes,
            if (e.hasL1CacheBytes) 'l1_cache_bytes': e.l1CacheBytes,
            if (e.hasL2CacheBytes) 'l2_cache_bytes': e.l2CacheBytes,
            if (e.hasL3CacheBytes) 'l3_cache_bytes': e.l3CacheBytes,
            'instruction_set': e.instructionSet,
            if (e.hasSmtEnabled) 'smt_enabled': e.smtEnabled,
            'virtualization_vendor': e.virtualizationVendor,
          },
      ],
      'memory_modules': [
        for (final e in snap.memoryModules)
          {
            'id': e.id,
            'bank_locator': e.bankLocator,
            'manufacturer': e.manufacturer,
            'part_number': e.partNumber,
            'serial_number': e.serialNumber,
            if (e.hasSizeBytes) 'size_bytes': e.sizeBytes,
            if (e.hasSpeedMts) 'speed_mts': e.speedMts,
            if (e.hasConfiguredSpeedMts)
              'configured_speed_mts': e.configuredSpeedMts,
            'form_factor': e.formFactor,
            'memory_type': e.memoryType,
            if (e.hasIsEcc) 'is_ecc': e.isEcc,
            if (e.hasTotalWidthBits) 'total_width_bits': e.totalWidthBits,
            if (e.hasDataWidthBits) 'data_width_bits': e.dataWidthBits,
            if (e.hasConfiguredVoltageMv)
              'configured_voltage_mv': e.configuredVoltageMv,
            'populated': e.populated,
          },
      ],
      'storage': [
        for (final e in snap.storage)
          {
            'id': e.id,
            'device_path': e.devicePath,
            if (e.hasPhysicalDriveNumber)
              'physical_drive_number': e.physicalDriveNumber,
            'model': e.model,
            'vendor': e.vendor,
            'serial_number': e.serialNumber,
            'firmware_revision': e.firmwareRevision,
            'bus_type': e.busType,
            'media_type': e.mediaType,
            if (e.hasSizeBytes) 'size_bytes': e.sizeBytes,
            if (e.hasSectorSizeBytes) 'sector_size_bytes': e.sectorSizeBytes,
            'partition_style': e.partitionStyle,
            if (e.hasIsRemovable) 'is_removable': e.isRemovable,
            if (e.hasTrimSupported) 'trim_supported': e.trimSupported,
            'manufacturer': e.manufacturer,
            'description': e.description,
          },
      ],
      'network_adapters': [
        for (final e in snap.networkAdapters)
          {
            'id': e.id,
            'friendly_name': e.friendlyName,
            'description': e.description,
            'mac_address': e.macAddress,
            'connection_type': e.connectionType,
            if (e.hasIfIndex) 'if_index': e.ifIndex,
            if (e.hasMtu) 'mtu': e.mtu,
            'operational_status': e.operationalStatus,
            if (e.hasDhcpEnabled) 'dhcp_enabled': e.dhcpEnabled,
            if (e.hasLinkSpeedBps) 'link_speed_bps': e.linkSpeedBps,
            'is_loopback': e.isLoopback,
            'ipv4_addresses': e.ipv4Addresses,
            'ipv6_addresses': e.ipv6Addresses,
            'gateway_addresses': e.gatewayAddresses,
            'dns_addresses': e.dnsAddresses,
            'driver_provider': e.driverProvider,
            'driver_version': e.driverVersion,
            'driver_date': e.driverDate,
          },
      ],
    };
  }

  /// System Inventory report JSON — six P2 domain snapshots keyed by domain.
  static Map<String, dynamic> systemInventoryJson(ReportExportInput input) {
    return {
      for (final section in _systemInventorySections(input))
        section.$1: inventoryDomainJson(section.$2),
    };
  }

  static List<(String, String)> inventorySummaryRows(
    InventoryDomainSnapshot? snap,
  ) {
    if (snap == null) {
      return const [('status', 'No inventory snapshot')];
    }
    return [
      ('domain', snap.domain.name),
      ('status', snap.status.name),
      ('status_detail', snap.statusDetail),
      ('truncated', '${snap.truncated}'),
      ('generation', '${snap.generation}'),
      ('count', '${_inventoryItemCount(snap)}'),
    ];
  }

  static List<(String, String)> diagnosticsRows({
    DiagnosticsSnapshot? snap,
    IpcStatus? status,
    ClientFrameMetrics? frames,
    String? snapshotError,
  }) {
    final rows = <(String, String)>[
      ('pulse_version', kAppVersion),
      if (snapshotError != null && snapshotError.isNotEmpty)
        ('snapshot_error', snapshotError),
    ];
    if (status != null) {
      rows.addAll([
        ('ipc_state', status.state.name),
        ('service_version_client', status.serviceVersion),
        ('reconnect_count', '${status.reconnectCount}'),
        ('messages_sent', '${status.messagesSent}'),
        ('messages_failed', '${status.messagesFailed}'),
        (
          'last_ping_ms',
          status.lastPingLatencyMs?.toString() ?? '—',
        ),
      ]);
    }
    if (frames != null) {
      rows.addAll([
        ('client_fps', frames.fps?.toStringAsFixed(1) ?? '—'),
        (
          'client_frame_ms',
          frames.avgTotalFrameMs?.toStringAsFixed(2) ?? '—',
        ),
        ('client_rss_bytes', frames.rssBytes?.toString() ?? '—'),
      ]);
    }
    if (snap != null) {
      rows.addAll([
        ('service_version', snap.serviceVersion),
        ('protocol_version', '${snap.protocolVersion}'),
        ('build_version', snap.buildVersion),
        ('git_commit', snap.gitCommit),
        ('run_mode', snap.runMode),
        ('service_pid', '${snap.servicePid}'),
        ('service_uptime_ms', '${snap.serviceUptimeMs}'),
        ('windows_edition', snap.windowsEdition),
        ('windows_version', snap.windowsVersion),
        ('executable_path', snap.executablePath),
        ('install_path', snap.installPath),
        ('scm_state', snap.scmState),
        ('scm_startup_type', snap.scmStartupType),
        ('live_subscribed', '${snap.liveSubscribed}'),
        ('live_channel', snap.liveChannel),
        ('live_events_pushed', '${snap.liveEventsPushed}'),
        ('live_events_dropped', '${snap.liveEventsDropped}'),
        ('live_queue', '${snap.liveQueueDepth}/${snap.liveQueueCapacity}'),
        if (snap.hasCpuPercent)
          ('service_cpu_percent', snap.cpuPercent.toStringAsFixed(1)),
        ('working_set_bytes', '${snap.workingSetBytes}'),
        ('thread_count', '${snap.threadCount}'),
        ('handle_count', '${snap.handleCount}'),
        ('health_monitoring_active', '${snap.healthMonitoringActive}'),
        ('health_sample_rate_hz', snap.healthSampleRateHz.toStringAsFixed(1)),
        ('network_etw_running', '${snap.networkEtwRunning}'),
        if (snap.networkEtwLastError.isNotEmpty)
          ('network_etw_last_error', snap.networkEtwLastError),
        ('stage_event_log', '${snap.stageEventLog}'),
        ('stage_collector', '${snap.stageCollector}'),
        ('stage_intelligence', '${snap.stageIntelligence}'),
        ('stage_ipc', '${snap.stageIpc}'),
      ]);
    }
    return rows;
  }

  // ─── Internal payload / render helpers ──────────────────────────────────

  static Map<String, dynamic> _payloadMap(ReportExportInput input) {
    final base = <String, dynamic>{
      'pulse_export': input.template.fileStem,
      'template': input.template.name,
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'pulse_version': kAppVersion,
      'system_identity': {
        for (final row in _systemIdentity(input)) row.$1: row.$2,
      },
    };

    switch (input.template) {
      case ReportTemplate.healthSnapshot:
        base['metrics'] = {
          for (final row in healthMetricsRows(input.health)) row.$1: row.$2,
        };
        if (input.health != null) {
          base['info'] = _infoJson(input.health!.info);
          base['sample'] = _sampleJson(input.health!.sample);
        }
      case ReportTemplate.timeline:
        base['count'] = input.events.length;
        base['events'] = [
          for (final e in input.events) TimelineExport.eventToJson(e),
        ];
      case ReportTemplate.diagnostics:
        base['fields'] = {
          for (final row in diagnosticsRows(
            snap: input.diagnostics,
            status: input.ipcStatus,
            frames: input.frameMetrics,
            snapshotError: input.snapshotError,
          ))
            row.$1: row.$2,
        };
      case ReportTemplate.hardwareInventory:
        base['source'] = 'inventory_engine';
        base['usb'] = inventoryDomainJson(input.inventoryUsb);
        base['pci'] = inventoryDomainJson(input.inventoryPci);
      case ReportTemplate.systemInventory:
        base['source'] = 'inventory_engine';
        base['system'] = systemInventoryJson(input);
      case ReportTemplate.serviceInventory:
      case ReportTemplate.driverInventory:
      case ReportTemplate.softwareInventory:
        base['inventory'] = inventoryDomainJson(input.inventory);
    }
    return base;
  }

  static Map<String, dynamic> _infoJson(HealthStaticInfo i) => {
        'windows_edition': i.windowsEdition,
        'windows_version': i.windowsVersion,
        'cpu_model': i.cpuModel,
        'cpu_architecture': i.cpuArchitecture,
        'cpu_cores': i.cpuCores,
        'cpu_logical_processors': i.cpuLogicalProcessors,
        'cpu_base_mhz': i.cpuBaseMhz,
        'gpu_model': i.gpuModel,
        'gpu_vendor': i.gpuVendor,
        'gpu_driver_version': i.gpuDriverVersion,
        'gpu_dedicated_bytes': i.gpuDedicatedBytes,
        'installed_ram_bytes': i.installedRamBytes,
        'primary_storage_bytes': i.primaryStorageBytes,
        'disk_model': i.diskModel,
        'active_network_adapter': i.activeNetworkAdapter,
        'net_mac_address': i.netMacAddress,
      };

  static Map<String, dynamic> _sampleJson(HealthSample s) => {
        'unix_ms': s.unixMs,
        if (s.hasCpuPercent) 'cpu_percent': s.cpuPercent,
        'memory_used_bytes': s.memoryUsedBytes,
        'memory_total_bytes': s.memoryTotalBytes,
        if (s.hasGpuPercent) 'gpu_percent': s.gpuPercent,
        if (s.hasNetDownloadBps) 'net_download_bps': s.netDownloadBps,
        if (s.hasNetUploadBps) 'net_upload_bps': s.netUploadBps,
        if (s.hasDiskReadBps) 'disk_read_bps': s.diskReadBps,
        if (s.hasDiskWriteBps) 'disk_write_bps': s.diskWriteBps,
        'disk_used_bytes': s.diskUsedBytes,
        'disk_total_bytes': s.diskTotalBytes,
        'uptime_ms': s.uptimeMs,
        'ipv4': s.ipv4,
        'gateway': s.gateway,
        'dns': s.dns,
      };

  /// System identity cover block. [ReportTemplate.systemInventory] sources
  /// identity from Inventory (motherboard/CPU) — never [HealthStaticInfo],
  /// since Inventory is now the SSOT for that identity data.
  static List<(String, String)> _systemIdentity(ReportExportInput input) {
    if (input.template == ReportTemplate.systemInventory) {
      return _systemInventoryIdentity(input);
    }
    final info = input.health?.info;
    final snap = input.diagnostics;
    final windows = () {
      if (info != null &&
          (info.windowsEdition.isNotEmpty || info.windowsVersion.isNotEmpty)) {
        return '${info.windowsEdition} ${info.windowsVersion}'.trim();
      }
      if (snap != null &&
          (snap.windowsEdition.isNotEmpty || snap.windowsVersion.isNotEmpty)) {
        return '${snap.windowsEdition} ${snap.windowsVersion}'.trim();
      }
      return '—';
    }();
    final computer = input.events
        .map((e) => e.computerName)
        .firstWhere((c) => c.isNotEmpty, orElse: () => '');
    return [
      ('windows', windows),
      if (computer.isNotEmpty) ('computer', computer),
      if (info != null && info.cpuModel.isNotEmpty) ('cpu', info.cpuModel),
      if (info != null && info.gpuModel.isNotEmpty) ('gpu', info.gpuModel),
    ];
  }

  static List<(String, String)> _systemInventoryIdentity(
    ReportExportInput input,
  ) {
    final board = input.inventoryMotherboard?.motherboard;
    final bios = input.inventoryBios?.bios;
    final cpu = input.inventoryCpu?.cpu;
    final rows = <(String, String)>[
      if (board != null && board.isNotEmpty && board.first.product.isNotEmpty)
        ('motherboard', board.first.product),
      if (bios != null && bios.isNotEmpty && bios.first.vendor.isNotEmpty)
        ('bios_vendor', bios.first.vendor),
      if (cpu != null && cpu.isNotEmpty && cpu.first.name.isNotEmpty)
        ('cpu', cpu.first.name),
    ];
    if (rows.isEmpty) rows.add(('status', 'No system inventory snapshot'));
    return rows;
  }

  static String _timelineCsv(List<TimelineEvent> events) {
    final buf = StringBuffer('time,severity,provider,title,summary\n');
    for (final e in events) {
      final time = e.timestampIso.isNotEmpty
          ? e.timestampIso
          : (e.timestampUnixMs > 0
              ? DateTime.fromMillisecondsSinceEpoch(
                  e.timestampUnixMs,
                  isUtc: true,
                ).toLocal().toIso8601String()
              : '');
      buf.writeln(
        [
          _csvCell(time),
          _csvCell(_severityName(e.severity)),
          _csvCell(e.providerName),
          _csvCell(e.displayTitle),
          _csvCell(e.displaySummary),
        ].join(','),
      );
    }
    return buf.toString();
  }

  static String _keyValueCsv(List<(String, String)> rows) {
    final buf = StringBuffer('key,value\n');
    for (final row in rows) {
      buf.writeln('${_csvCell(row.$1)},${_csvCell(row.$2)}');
    }
    return buf.toString();
  }

  static String _csvCell(String value) {
    final needsQuote = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuote) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  static String _severityName(int severity) {
    return switch (severity) {
      Severity.critical => 'critical',
      Severity.error => 'error',
      Severity.warning => 'warning',
      Severity.info => 'info',
      Severity.verbose => 'verbose',
      _ => 'unknown',
    };
  }

  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _kvTableHtml(List<(String, String)> rows) {
    final buf = StringBuffer('<table>');
    for (final row in rows) {
      buf.writeln(
        '<tr><th>${_escapeHtml(row.$1)}</th>'
        '<td>${_escapeHtml(row.$2)}</td></tr>',
      );
    }
    buf.write('</table>');
    return buf.toString();
  }

  static String _htmlSections(ReportExportInput input) {
    switch (input.template) {
      case ReportTemplate.timeline:
        final buf = StringBuffer()
          ..writeln('<section><h2>Events (${input.events.length})</h2>')
          ..writeln('<table><tr>'
              '<th style="width:18%">Time</th>'
              '<th style="width:10%">Severity</th>'
              '<th style="width:18%">Provider</th>'
              '<th style="width:22%">Title</th>'
              '<th>Summary</th></tr>');
        for (final e in input.events) {
          final time = e.timestampIso.isNotEmpty
              ? e.timestampIso
              : e.absoluteTimeLabel;
          buf.writeln(
            '<tr>'
            '<td>${_escapeHtml(time)}</td>'
            '<td>${_escapeHtml(_severityName(e.severity))}</td>'
            '<td>${_escapeHtml(e.providerName)}</td>'
            '<td>${_escapeHtml(e.displayTitle)}</td>'
            '<td>${_escapeHtml(e.displaySummary)}</td>'
            '</tr>',
          );
        }
        buf.writeln('</table></section>');
        return buf.toString();
      case ReportTemplate.healthSnapshot:
        return '<section><h2>Health metrics</h2>'
            '${_kvTableHtml(healthMetricsRows(input.health))}</section>';
      case ReportTemplate.hardwareInventory:
        final usb = input.inventoryUsb;
        final pci = input.inventoryPci;
        final usbCount = usb == null ? 0 : _inventoryItemCount(usb);
        final pciCount = pci == null ? 0 : _inventoryItemCount(pci);
        return '<section><h2>USB inventory ($usbCount)</h2>'
            '${_kvTableHtml(inventorySummaryRows(usb))}</section>'
            '<section><h2>PCI inventory ($pciCount)</h2>'
            '${_kvTableHtml(inventorySummaryRows(pci))}</section>';
      case ReportTemplate.systemInventory:
        return _systemInventoryHtml(input);
      case ReportTemplate.serviceInventory:
      case ReportTemplate.driverInventory:
      case ReportTemplate.softwareInventory:
        final snap = input.inventory;
        final summary = inventorySummaryRows(snap);
        final count = snap == null ? 0 : _inventoryItemCount(snap);
        final buf = StringBuffer()
          ..writeln('<section><h2>Inventory summary</h2>')
          ..writeln(_kvTableHtml(summary))
          ..writeln('</section>')
          ..writeln('<section><h2>Items ($count)</h2>');
        if (snap == null) {
          buf.writeln('<p>No inventory snapshot.</p></section>');
          return buf.toString();
        }
        buf.writeln('<table><tr>');
        switch (snap.domain) {
          case InventoryDomainId.services:
            buf.writeln(
              '<th>Id</th><th>Display name</th><th>State</th>'
              '<th>Start type</th><th>Account</th></tr>',
            );
            for (final e in snap.services) {
              buf.writeln(
                '<tr><td>${_escapeHtml(e.id)}</td>'
                '<td>${_escapeHtml(e.displayName)}</td>'
                '<td>${_escapeHtml(e.state)}</td>'
                '<td>${_escapeHtml(e.startType)}</td>'
                '<td>${_escapeHtml(e.account)}</td></tr>',
              );
            }
          case InventoryDomainId.drivers:
            buf.writeln(
              '<th>Id</th><th>Display name</th><th>State</th>'
              '<th>Type</th><th>Start type</th></tr>',
            );
            for (final e in snap.drivers) {
              buf.writeln(
                '<tr><td>${_escapeHtml(e.id)}</td>'
                '<td>${_escapeHtml(e.displayName)}</td>'
                '<td>${_escapeHtml(e.state)}</td>'
                '<td>${_escapeHtml(e.driverType)}</td>'
                '<td>${_escapeHtml(e.startType)}</td></tr>',
              );
            }
          case InventoryDomainId.software:
            buf.writeln(
              '<th>Id</th><th>Name</th><th>Version</th>'
              '<th>Publisher</th><th>Arch</th></tr>',
            );
            for (final e in snap.software) {
              buf.writeln(
                '<tr><td>${_escapeHtml(e.id)}</td>'
                '<td>${_escapeHtml(e.displayName)}</td>'
                '<td>${_escapeHtml(e.version)}</td>'
                '<td>${_escapeHtml(e.publisher)}</td>'
                '<td>${_escapeHtml(e.architecture)}</td></tr>',
              );
            }
          default:
            buf.writeln('<th>Note</th></tr>');
            buf.writeln('<tr><td>Unsupported domain</td></tr>');
        }
        buf.writeln('</table></section>');
        return buf.toString();
      case ReportTemplate.diagnostics:
        return '<section><h2>Diagnostics</h2>${_kvTableHtml(diagnosticsRows(
          snap: input.diagnostics,
          status: input.ipcStatus,
          frames: input.frameMetrics,
          snapshotError: input.snapshotError,
        ))}</section>';
    }
  }

  /// System Inventory HTML — one sub-section per P2 entry, reusing the same
  /// [InventoryDetailSection] builders as the Inventory detail panel so the
  /// report and the UI never disagree on fields.
  static String _systemInventoryHtml(ReportExportInput input) {
    final buf = StringBuffer()..writeln('<section><h2>System inventory</h2>');
    for (final e in input.inventoryMotherboard?.motherboard ?? const []) {
      buf.writeln(
        '<h3>Motherboard — ${_escapeHtml(e.product.isEmpty ? e.id : e.product)}</h3>'
        '${_sectionsHtml(motherboardDetailSections(e))}',
      );
    }
    for (final e in input.inventoryBios?.bios ?? const []) {
      buf.writeln(
        '<h3>BIOS — ${_escapeHtml(e.vendor.isEmpty ? e.id : e.vendor)}</h3>'
        '${_sectionsHtml(biosDetailSections(e))}',
      );
    }
    for (final e in input.inventoryCpu?.cpu ?? const []) {
      buf.writeln(
        '<h3>CPU — ${_escapeHtml(e.name.isEmpty ? e.id : e.name)}</h3>'
        '${_sectionsHtml(cpuDetailSections(e))}',
      );
    }
    for (final e in input.inventoryMemoryModules?.memoryModules ?? const []) {
      buf.writeln(
        '<h3>Memory — ${_escapeHtml(e.bankLocator.isEmpty ? e.id : e.bankLocator)}</h3>'
        '${_sectionsHtml(memoryModuleDetailSections(e))}',
      );
    }
    for (final e in input.inventoryStorage?.storage ?? const []) {
      buf.writeln(
        '<h3>Storage — ${_escapeHtml(e.model.isEmpty ? e.id : e.model)}</h3>'
        '${_sectionsHtml(storageDetailSections(e))}',
      );
    }
    for (final e
        in input.inventoryNetworkAdapters?.networkAdapters ?? const []) {
      buf.writeln(
        '<h3>Network adapter — '
        '${_escapeHtml(e.friendlyName.isEmpty ? e.id : e.friendlyName)}</h3>'
        '${_sectionsHtml(networkAdapterDetailSections(e))}',
      );
    }
    buf.writeln('</section>');
    return buf.toString();
  }

  static String _sectionsHtml(List<InventoryDetailSection> sections) {
    if (sections.isEmpty) return '<p>No structured fields returned.</p>';
    final buf = StringBuffer();
    for (final section in sections) {
      buf.writeln(
        '<div style="font-weight:600;font-size:12px;margin:8px 0 4px;">'
        '${_escapeHtml(section.title)}</div>',
      );
      buf.writeln('<table>');
      for (final field in section.fields) {
        buf.writeln(
          '<tr><th>${_escapeHtml(field.$1)}</th>'
          '<td>${_escapeHtml(field.$2)}</td></tr>',
        );
      }
      buf.writeln('</table>');
    }
    return buf.toString();
  }

  static List<pw.Widget> _pdfTables(ReportExportInput input) {
    switch (input.template) {
      case ReportTemplate.timeline:
        return [
          pw.Text(
            'Events (${input.events.length})',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const ['Time', 'Severity', 'Provider', 'Title', 'Summary'],
            data: [
              for (final e in input.events)
                [
                  e.timestampIso.isNotEmpty
                      ? e.timestampIso
                      : e.absoluteTimeLabel,
                  _severityName(e.severity),
                  e.providerName,
                  e.displayTitle,
                  e.displaySummary,
                ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
        ];
      case ReportTemplate.healthSnapshot:
        return [
          pw.Text(
            'Health metrics',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _pdfKeyValueTable(healthMetricsRows(input.health)),
        ];
      case ReportTemplate.hardwareInventory:
        return [
          pw.Text(
            'USB inventory',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _pdfKeyValueTable(inventorySummaryRows(input.inventoryUsb)),
          pw.SizedBox(height: 12),
          pw.Text(
            'PCI inventory',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _pdfKeyValueTable(inventorySummaryRows(input.inventoryPci)),
        ];
      case ReportTemplate.systemInventory:
        return _systemInventoryPdfWidgets(input);
      case ReportTemplate.serviceInventory:
      case ReportTemplate.driverInventory:
      case ReportTemplate.softwareInventory:
        return [
          pw.Text(
            'Inventory summary',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _pdfKeyValueTable(inventorySummaryRows(input.inventory)),
        ];
      case ReportTemplate.diagnostics:
        return [
          pw.Text(
            'Diagnostics',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _pdfKeyValueTable(
            diagnosticsRows(
              snap: input.diagnostics,
              status: input.ipcStatus,
              frames: input.frameMetrics,
              snapshotError: input.snapshotError,
            ),
          ),
        ];
    }
  }

  /// System Inventory PDF widgets — mirrors [_systemInventoryHtml], reusing
  /// the shared [InventoryDetailSection] builders per P2 entry.
  static List<pw.Widget> _systemInventoryPdfWidgets(ReportExportInput input) {
    final widgets = <pw.Widget>[];
    void addEntry(String heading, List<InventoryDetailSection> sections) {
      widgets.addAll([
        pw.Text(
          heading,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        ..._sectionsPdfWidgets(sections),
        pw.SizedBox(height: 10),
      ]);
    }

    for (final e in input.inventoryMotherboard?.motherboard ?? const []) {
      addEntry(
        'Motherboard — ${e.product.isEmpty ? e.id : e.product}',
        motherboardDetailSections(e),
      );
    }
    for (final e in input.inventoryBios?.bios ?? const []) {
      addEntry(
        'BIOS — ${e.vendor.isEmpty ? e.id : e.vendor}',
        biosDetailSections(e),
      );
    }
    for (final e in input.inventoryCpu?.cpu ?? const []) {
      addEntry('CPU — ${e.name.isEmpty ? e.id : e.name}', cpuDetailSections(e));
    }
    for (final e in input.inventoryMemoryModules?.memoryModules ?? const []) {
      addEntry(
        'Memory — ${e.bankLocator.isEmpty ? e.id : e.bankLocator}',
        memoryModuleDetailSections(e),
      );
    }
    for (final e in input.inventoryStorage?.storage ?? const []) {
      addEntry(
        'Storage — ${e.model.isEmpty ? e.id : e.model}',
        storageDetailSections(e),
      );
    }
    for (final e
        in input.inventoryNetworkAdapters?.networkAdapters ?? const []) {
      addEntry(
        'Network adapter — ${e.friendlyName.isEmpty ? e.id : e.friendlyName}',
        networkAdapterDetailSections(e),
      );
    }
    if (widgets.isEmpty) {
      widgets.add(pw.Text('No system inventory snapshot available.'));
    }
    return widgets;
  }

  static List<pw.Widget> _sectionsPdfWidgets(
    List<InventoryDetailSection> sections,
  ) {
    final widgets = <pw.Widget>[];
    for (final section in sections) {
      widgets.addAll([
        pw.Text(
          section.title,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 2),
        _pdfKeyValueTable(section.fields),
        pw.SizedBox(height: 4),
      ]);
    }
    return widgets;
  }

  static pw.Widget _pdfKeyValueTable(List<(String, String)> rows) {
    return pw.TableHelper.fromTextArray(
      headers: const ['Key', 'Value'],
      data: [
        for (final row in rows) [row.$1, row.$2],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.centerLeft,
      columnWidths: {
        0: const pw.FlexColumnWidth(1.2),
        1: const pw.FlexColumnWidth(2.5),
      },
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
    );
  }
}
