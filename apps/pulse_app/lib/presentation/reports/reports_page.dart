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
import '../components/pulse_section_header.dart';
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
        _template == ReportTemplate.hardwareInventory ||
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

  @override
  Widget build(BuildContext context) {
    final connectionLabel = context.select<ConnectionController, String>(
      (c) => c.statusLabel,
    );
    final state = context.select<PulseIpcClient, IpcConnectionState>(
      (c) => c.status.state,
    );
    final eventCount = context.select<TimelineSessionController, int>(
      (t) => t.events.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseAppBar(
          title: widget.title,
          connectionState: state,
          connectionLabel: connectionLabel,
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              PulseTokens.pagePadX,
              20,
              PulseTokens.pagePadX,
              PulseTokens.pagePadBottom,
            ),
            children: [
              PulseSectionHeader(
                title: 'Export report',
                subtitle:
                    'Save System Health, Timeline, Diagnostics, Inventory '
                    '(services / drivers / software), or hardware summary as '
                    'JSON, CSV, HTML, or PDF.',
              ),
              if (state != IpcConnectionState.connected) ...[
                const SizedBox(height: PulseTokens.spaceMd),
                PulseCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        LucideIcons.unplug,
                        size: 18,
                        color: PulseTokens.textTertiary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'PulseService is offline. Health, Diagnostics, and '
                          'Inventory exports may be incomplete; Timeline uses '
                          'events already loaded in this session.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: PulseTokens.textSecondary,
                                height: 1.45,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: PulseTokens.spaceLg),
              Text(
                'Template',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: PulseTokens.textSecondary,
                    ),
              ),
              const SizedBox(height: PulseTokens.spaceSm),
              for (final template in ReportTemplate.values) ...[
                PulseCard(
                  selected: _template == template,
                  onTap: () {
                    setState(() {
                      _template = template;
                      if (_format == ReportFormat.csv &&
                          !template.supportsCsv) {
                        _format = ReportFormat.json;
                      }
                    });
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _templateIcon(template),
                        size: 18,
                        color: _template == template
                            ? PulseTokens.accent
                            : PulseTokens.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              template.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              template == ReportTemplate.timeline
                                  ? '${template.description} ($eventCount loaded)'
                                  : template.description,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: PulseTokens.textSecondary,
                                    height: 1.4,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PulseTokens.spaceSm),
              ],
              const SizedBox(height: PulseTokens.spaceMd),
              Text(
                'Format',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: PulseTokens.textSecondary,
                    ),
              ),
              const SizedBox(height: PulseTokens.spaceSm),
              LayoutBuilder(
                builder: (context, constraints) {
                  final button = SegmentedButton<ReportFormat>(
                    segments: [
                      for (final format in ReportFormat.values)
                        ButtonSegment(
                          value: format,
                          label: Text(format.label),
                          enabled: format != ReportFormat.csv ||
                              _template.supportsCsv,
                        ),
                    ],
                    selected: {_format},
                    onSelectionChanged: (selected) {
                      setState(() => _format = selected.first);
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                  if (constraints.maxWidth >= 420) {
                    return button;
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: IntrinsicWidth(child: button),
                  );
                },
              ),
              const SizedBox(height: PulseTokens.spaceLg),
              Align(
                alignment: Alignment.centerLeft,
                child: PulseButton(
                  label: 'Export',
                  icon: LucideIcons.download,
                  loading: _exporting,
                  onPressed: _exporting ? null : _export,
                ),
              ),
              if (_lastExportPath != null) ...[
                const SizedBox(height: PulseTokens.spaceMd),
                Text(
                  'Last export',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: PulseTokens.textSecondary,
                      ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  _lastExportPath!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PulseTokens.textPrimary,
                        height: 1.4,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
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
    };
  }
}
