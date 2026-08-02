import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../application/client_frame_metrics.dart';
import '../../application/connection_controller.dart';
import '../../application/diagnostics_controller.dart';
import '../../application/settings_controller.dart';
import '../../application/timeline_session_controller.dart';
import '../../app/theme/pulse_theme.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../components/pulse_app_bar.dart';
import '../components/pulse_button.dart';
import '../components/pulse_card.dart';
import '../components/pulse_segmented_control.dart';
import '../utils/pulse_snack.dart';
import '../utils/pulse_user_errors.dart';
import 'report_exporter.dart';
import 'report_models.dart';

/// Exports existing Pulse data as branded JSON / CSV / HTML / PDF reports.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.title});

  final String title;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  ReportTemplate _template = ReportTemplate.healthSnapshot;
  ReportFormat _format = ReportFormat.json;
  bool _exporting = false;
  String? _lastExportPath;

  Future<void> _export() async {
    if (_exporting) return;
    if (_format == ReportFormat.csv && !_template.supportsCsv) {
      PulseSnack.info(context, 'CSV is not available for this template.');
      return;
    }

    setState(() => _exporting = true);
    try {
      final ipc = context.read<PulseIpcClient>();
      final settings = context.read<SettingsController>();
      final timeline = context.read<TimelineSessionController>();
      final diag = context.read<DiagnosticsController>();
      final frames = context.read<ClientFrameMetrics>();
      final dark = Theme.of(context).brightness == Brightness.dark;

      final health = await _fetchHealthIfNeeded(ipc);
      final inventory = await _fetchInventoryIfNeeded(ipc);
      final hardwarePair = await _fetchHardwareInventoryIfNeeded(ipc);
      final systemDomains = await _fetchSystemInventoryIfNeeded(ipc);
      if (_template == ReportTemplate.diagnostics && diag.snapshot == null) {
        try {
          await diag.refresh();
        } catch (_) {}
      }

      final input = ReportExportInput(
        template: _template,
        format: _format,
        health: health,
        inventory: inventory,
        inventoryUsb: hardwarePair.$1,
        inventoryPci: hardwarePair.$2,
        inventoryMotherboard: systemDomains.$1,
        inventoryBios: systemDomains.$2,
        inventoryCpu: systemDomains.$3,
        inventoryMemoryModules: systemDomains.$4,
        inventoryStorage: systemDomains.$5,
        inventoryNetworkAdapters: systemDomains.$6,
        events: List.of(timeline.events),
        diagnostics: diag.snapshot,
        ipcStatus: ipc.status,
        frameMetrics: frames,
        snapshotError: diag.snapshotError,
        darkHtml: dark,
      );

      final exporter = ReportExporter(settings: settings);
      final path = await exporter.export(input);
      if (!mounted) return;
      setState(() => _lastExportPath = path);
      PulseSnack.success(context, 'Exported to $path');
    } catch (e) {
      if (!mounted) return;
      PulseSnack.error(context, PulseUserErrors.fromObject(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<HealthSnapshot?> _fetchHealthIfNeeded(PulseIpcClient ipc) async {
    final needsHealth = _template == ReportTemplate.healthSnapshot ||
        _template == ReportTemplate.diagnostics;
    if (!needsHealth) return null;
    if (ipc.status.state != IpcConnectionState.connected) return null;
    try {
      return await ipc.getHealthSnapshot();
    } catch (_) {
      return null;
    }
  }

  Future<InventoryDomainSnapshot?> _fetchInventoryIfNeeded(
    PulseIpcClient ipc,
  ) async {
    final domain = _template.inventoryDomain;
    if (domain == null) return null;
    if (ipc.status.state != IpcConnectionState.connected) return null;
    try {
      return await ipc.getInventoryDomain(domain: domain);
    } catch (_) {
      return null;
    }
  }

  Future<(InventoryDomainSnapshot?, InventoryDomainSnapshot?)>
      _fetchHardwareInventoryIfNeeded(PulseIpcClient ipc) async {
    if (_template != ReportTemplate.hardwareInventory) {
      return (null, null);
    }
    if (ipc.status.state != IpcConnectionState.connected) {
      return (null, null);
    }
    InventoryDomainSnapshot? usb;
    InventoryDomainSnapshot? pci;
    try {
      usb = await ipc.getInventoryDomain(domain: InventoryDomainId.usb);
    } catch (_) {}
    try {
      pci = await ipc.getInventoryDomain(domain: InventoryDomainId.pci);
    } catch (_) {}
    return (usb, pci);
  }

  Future<
      (
        InventoryDomainSnapshot?,
        InventoryDomainSnapshot?,
        InventoryDomainSnapshot?,
        InventoryDomainSnapshot?,
        InventoryDomainSnapshot?,
        InventoryDomainSnapshot?
      )> _fetchSystemInventoryIfNeeded(PulseIpcClient ipc) async {
    if (_template != ReportTemplate.systemInventory) {
      return (null, null, null, null, null, null);
    }
    if (ipc.status.state != IpcConnectionState.connected) {
      return (null, null, null, null, null, null);
    }
    Future<InventoryDomainSnapshot?> fetch(InventoryDomainId domain) async {
      try {
        return await ipc.getInventoryDomain(domain: domain);
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([
      fetch(InventoryDomainId.motherboard),
      fetch(InventoryDomainId.bios),
      fetch(InventoryDomainId.cpu),
      fetch(InventoryDomainId.memoryModules),
      fetch(InventoryDomainId.storage),
      fetch(InventoryDomainId.networkAdapters),
    ]);
    return (
      results[0],
      results[1],
      results[2],
      results[3],
      results[4],
      results[5],
    );
  }

  String _destinationLabel(SettingsController settings) {
    final custom = settings.exportDirectory.trim();
    if (custom.isNotEmpty) return custom;
    return 'Documents / Pulse / exports (default)';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final connectionLabel = context.select<ConnectionController, String>(
      (c) => c.statusLabel,
    );
    final state = context.select<PulseIpcClient, IpcConnectionState>(
      (c) => c.status.state,
    );
    final eventCount = context.select<TimelineSessionController, int>(
      (t) => t.events.length,
    );
    final settings = context.watch<SettingsController>();
    final destination = _destinationLabel(settings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseAppBar(
          title: widget.title,
          connectionState: state,
          connectionLabel: connectionLabel,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              final templates = _TemplateGrid(
                selected: _template,
                eventCount: eventCount,
                onSelected: (template) {
                  setState(() {
                    _template = template;
                    if (_format == ReportFormat.csv && !template.supportsCsv) {
                      _format = ReportFormat.json;
                    }
                  });
                },
              );
              final formatPicker = _FormatPicker(
                template: _template,
                format: _format,
                onChanged: (format) => setState(() => _format = format),
              );
              Widget summary({required bool fillHeight}) => _ExportSummaryBar(
                    template: _template,
                    format: _format,
                    destination: destination,
                    lastExportPath: _lastExportPath,
                    exporting: _exporting,
                    offline: state != IpcConnectionState.connected,
                    fillHeight: fillHeight,
                    onExport: _exporting ? null : _export,
                  );

              if (!wide) {
                return Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          PulseTokens.pagePadX,
                          16,
                          PulseTokens.pagePadX,
                          16,
                        ),
                        children: [
                          Text(
                            'Choose a template',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: PulseTokens.textSecondary),
                          ),
                          const SizedBox(height: PulseTokens.spaceSm),
                          templates,
                          const SizedBox(height: PulseTokens.spaceLg),
                          Text(
                            'Format',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: PulseTokens.textSecondary),
                          ),
                          const SizedBox(height: PulseTokens.spaceSm),
                          formatPicker,
                        ],
                      ),
                    ),
                    summary(fillHeight: false),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        PulseTokens.pagePadX,
                        16,
                        12,
                        PulseTokens.pagePadBottom,
                      ),
                      children: [
                        Text(
                          'Choose a template',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: PulseTokens.textSecondary),
                        ),
                        const SizedBox(height: PulseTokens.spaceSm),
                        templates,
                        const SizedBox(height: PulseTokens.spaceLg),
                        Text(
                          'Format',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: PulseTokens.textSecondary),
                        ),
                        const SizedBox(height: PulseTokens.spaceSm),
                        formatPicker,
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: summary(fillHeight: true),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TemplateGrid extends StatelessWidget {
  const _TemplateGrid({
    required this.selected,
    required this.eventCount,
    required this.onSelected,
  });

  final ReportTemplate selected;
  final int eventCount;
  final ValueChanged<ReportTemplate> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        final gap = PulseTokens.spaceSm;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final template in ReportTemplate.values)
              SizedBox(
                width: width,
                height: 128,
                child: PulseCard(
                  selected: selected == template,
                  onTap: () => onSelected(template),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: selected == template
                              ? PulseTokens.accentSoft
                              : PulseTokens.surfaceHover,
                          borderRadius:
                              BorderRadius.circular(PulseTokens.radiusSm),
                        ),
                        child: Icon(
                          _templateIcon(template),
                          size: 18,
                          color: selected == template
                              ? PulseTokens.accent
                              : PulseTokens.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        template.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        template == ReportTemplate.timeline
                            ? '${template.description} ($eventCount loaded)'
                            : template.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: PulseTokens.textSecondary,
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FormatPicker extends StatelessWidget {
  const _FormatPicker({
    required this.template,
    required this.format,
    required this.onChanged,
  });

  final ReportTemplate template;
  final ReportFormat format;
  final ValueChanged<ReportFormat> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return PulseSegmentedControl<ReportFormat>(
      selected: format,
      onChanged: onChanged,
      segments: [
        for (final value in ReportFormat.values)
          PulseSegment(
            value: value,
            label: value.label,
            enabled: value != ReportFormat.csv || template.supportsCsv,
          ),
      ],
    );
  }
}

class _ExportSummaryBar extends StatelessWidget {
  const _ExportSummaryBar({
    required this.template,
    required this.format,
    required this.destination,
    required this.lastExportPath,
    required this.exporting,
    required this.offline,
    required this.fillHeight,
    required this.onExport,
  });

  final ReportTemplate template;
  final ReportFormat format;
  final String destination;
  final String? lastExportPath;
  final bool exporting;
  final bool offline;
  final bool fillHeight;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final body = <Widget>[
      Text(
        'Export summary',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
      const SizedBox(height: PulseTokens.spaceMd),
      _SummaryRow(label: 'Template', value: template.title),
      _SummaryRow(label: 'Format', value: format.label),
      _SummaryRow(label: 'Destination', value: destination),
      if (offline) ...[
        const SizedBox(height: PulseTokens.spaceSm),
        Text(
          'PulseService is offline. Some templates may be incomplete; '
          'Timeline uses events already loaded in this session.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PulseTokens.textSecondary,
                height: 1.4,
              ),
        ),
      ],
      if (fillHeight) const Spacer() else const SizedBox(height: 16),
      PulseButton(
        label: 'Export Report',
        icon: LucideIcons.download,
        expanded: true,
        loading: exporting,
        onPressed: onExport,
      ),
      if (lastExportPath != null) ...[
        const SizedBox(height: PulseTokens.spaceMd),
        Text(
          'Last export',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: PulseTokens.textTertiary,
              ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          lastExportPath!,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PulseTokens.textPrimary,
                height: 1.35,
              ),
        ),
      ],
    ];

    return Material(
      color: PulseTokens.surface.withValues(alpha: 0.96),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: fillHeight
                ? BorderSide(color: PulseTokens.strokeSubtle)
                : BorderSide.none,
            top: BorderSide(color: PulseTokens.strokeSubtle),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: PulseTokens.textTertiary,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

IconData _templateIcon(ReportTemplate template) {
  return switch (template) {
    ReportTemplate.healthSnapshot => LucideIcons.activity,
    ReportTemplate.timeline => LucideIcons.list,
    ReportTemplate.diagnostics => LucideIcons.stethoscope,
    ReportTemplate.hardwareInventory => LucideIcons.cpu,
    ReportTemplate.serviceInventory => LucideIcons.cog,
    ReportTemplate.driverInventory => LucideIcons.circuitBoard,
    ReportTemplate.softwareInventory => LucideIcons.package,
    ReportTemplate.systemInventory => LucideIcons.server,
  };
}
