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
import 'report_models.dart';

/// Bundled inputs for a single Reports export.
class ReportExportInput {
  const ReportExportInput({
    required this.template,
    required this.format,
    this.health,
    this.inventory,
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
        return _keyValueCsv(hardwareInventoryRows(input.health?.info));
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

  static List<(String, String)> hardwareInventoryRows(HealthStaticInfo? info) {
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
        _ => 0,
      };

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
        base['hardware'] = {
          for (final row in hardwareInventoryRows(input.health?.info))
            row.$1: row.$2,
        };
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

  static List<(String, String)> _systemIdentity(ReportExportInput input) {
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
        return '<section><h2>Hardware</h2>'
            '${_kvTableHtml(hardwareInventoryRows(input.health?.info))}</section>';
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
            'Hardware',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _pdfKeyValueTable(hardwareInventoryRows(input.health?.info)),
        ];
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
