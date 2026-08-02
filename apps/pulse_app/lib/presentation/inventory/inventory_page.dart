import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../application/connection_controller.dart';
import '../../app/theme/pulse_theme.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../components/pulse_app_bar.dart';
import '../components/pulse_badge.dart';
import '../components/pulse_button.dart';
import '../components/pulse_card.dart';
import '../components/pulse_empty_state.dart';
import '../components/service_lifecycle_controls.dart';
import '../utils/pulse_user_errors.dart';

/// Read-only system description catalogs (ADR-011). Lazy per domain.
class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.title});

  final String title;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  static const _domains = <_DomainTab>[
    _DomainTab(InventoryDomainId.services, 'Services', LucideIcons.cog),
    _DomainTab(InventoryDomainId.drivers, 'Drivers', LucideIcons.cpu),
    _DomainTab(InventoryDomainId.software, 'Software', LucideIcons.package),
    _DomainTab(InventoryDomainId.usb, 'USB', LucideIcons.usb),
    _DomainTab(InventoryDomainId.pci, 'PCI', LucideIcons.circuitBoard),
  ];

  InventoryDomainId _domain = InventoryDomainId.services;
  InventoryDomainSnapshot? _snapshot;
  String? _error;
  bool _loading = false;
  String _filter = '';
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<PulseIpcClient>().status.state;
      if (state == IpcConnectionState.connected) {
        _load(forceRefresh: false);
      }
    });
  }

  Future<void> _load({required bool forceRefresh}) async {
    final ipc = context.read<PulseIpcClient>();
    if (ipc.status.state != IpcConnectionState.connected) {
      setState(() {
        _snapshot = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await ipc.getInventoryDomain(
        domain: _domain,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _selectedId = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _snapshot = null;
        _error = PulseUserErrors.fromObject(e);
        _loading = false;
      });
    }
  }

  void _selectDomain(InventoryDomainId domain) {
    if (_domain == domain) return;
    setState(() {
      _domain = domain;
      _snapshot = null;
      _selectedId = null;
      _filter = '';
      _error = null;
    });
    _load(forceRefresh: false);
  }

  List<_InventoryRow> _rows() {
    final snap = _snapshot;
    if (snap == null) return const [];
    final q = _filter.trim().toLowerCase();
    final rows = <_InventoryRow>[];
    switch (snap.domain) {
      case InventoryDomainId.services:
        for (final e in snap.services) {
          rows.add(_InventoryRow(
            id: e.id,
            title: e.displayName.isEmpty ? e.id : e.displayName,
            subtitle: '${e.id} · ${e.state} · ${e.startType}',
            details: {
              'id': e.id,
              'display_name': e.displayName,
              'state': e.state,
              'start_type': e.startType,
              'account': e.account,
              'binary_path': e.binaryPath,
              'description': e.description,
            },
          ));
        }
      case InventoryDomainId.drivers:
        for (final e in snap.drivers) {
          rows.add(_InventoryRow(
            id: e.id,
            title: e.displayName.isEmpty ? e.id : e.displayName,
            subtitle: '${e.id} · ${e.state} · ${e.driverType}',
            details: {
              'id': e.id,
              'display_name': e.displayName,
              'state': e.state,
              'start_type': e.startType,
              'driver_type': e.driverType,
              'binary_path': e.binaryPath,
              'description': e.description,
            },
          ));
        }
      case InventoryDomainId.software:
        for (final e in snap.software) {
          rows.add(_InventoryRow(
            id: e.id,
            title: e.displayName,
            subtitle: [
              if (e.version.isNotEmpty) e.version,
              if (e.publisher.isNotEmpty) e.publisher,
              if (e.architecture.isNotEmpty) e.architecture,
            ].join(' · '),
            details: {
              'id': e.id,
              'display_name': e.displayName,
              'version': e.version,
              'publisher': e.publisher,
              'install_date': e.installDate,
              'install_location': e.installLocation,
              if (e.hasEstimatedSize)
                'estimated_size_bytes': '${e.estimatedSizeBytes}',
              'system_component': e.systemComponent ? 'true' : 'false',
              'architecture': e.architecture,
            },
          ));
        }
      case InventoryDomainId.usb:
        for (final e in snap.usb) {
          rows.add(_InventoryRow(
            id: e.id,
            title: e.description.isEmpty ? e.id : e.description,
            subtitle: [
              if (e.manufacturer.isNotEmpty) e.manufacturer,
              if (e.className.isNotEmpty) e.className,
              if (e.hardwareId.isNotEmpty) e.hardwareId,
            ].join(' · '),
            details: {
              'id': e.id,
              'description': e.description,
              'hardware_id': e.hardwareId,
              'manufacturer': e.manufacturer,
              'service': e.service,
              'class_name': e.className,
              'class_guid': e.classGuid,
              if (e.hasProblemCode) 'problem_code': '${e.problemCode}',
            },
          ));
        }
      case InventoryDomainId.pci:
        for (final e in snap.pci) {
          rows.add(_InventoryRow(
            id: e.id,
            title: e.description.isEmpty ? e.id : e.description,
            subtitle: [
              if (e.manufacturer.isNotEmpty) e.manufacturer,
              if (e.className.isNotEmpty) e.className,
              if (e.locationInfo.isNotEmpty) e.locationInfo,
            ].join(' · '),
            details: {
              'id': e.id,
              'description': e.description,
              'hardware_id': e.hardwareId,
              'manufacturer': e.manufacturer,
              'service': e.service,
              'class_name': e.className,
              'class_guid': e.classGuid,
              'location_info': e.locationInfo,
              if (e.hasProblemCode) 'problem_code': '${e.problemCode}',
            },
          ));
        }
      default:
        break;
    }
    if (q.isEmpty) return rows;
    return rows
        .where((r) =>
            r.title.toLowerCase().contains(q) ||
            r.subtitle.toLowerCase().contains(q) ||
            r.id.toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final connectionLabel = context.select<ConnectionController, String>(
      (c) => c.statusLabel,
    );
    final state = context.select<PulseIpcClient, IpcConnectionState>(
      (c) => c.status.state,
    );
    final offline = state != IpcConnectionState.connected;

    return Column(
      children: [
        PulseAppBar(
          title: widget.title,
          connectionState: state,
          connectionLabel: connectionLabel,
          searchEnabled: !offline,
          searchHint: 'Filter inventory…',
          searchQuery: _filter,
          onSearchChanged: (v) => setState(() => _filter = v),
          actions: [
            PulseButton(
              label: 'Refresh',
              icon: LucideIcons.refreshCw,
              variant: PulseButtonVariant.secondary,
              onPressed: offline || _loading
                  ? null
                  : () => _load(forceRefresh: true),
            ),
          ],
        ),
        Expanded(
          child: offline
              ? const ServiceOfflineRecovery(
                  titleFallback: 'Connect to PulseService to load inventory.',
                )
              : Padding(
                  padding: EdgeInsets.fromLTRB(
                    PulseTokens.pagePadX,
                    PulseTokens.spaceMd,
                    PulseTokens.pagePadX,
                    PulseTokens.spaceLg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DomainSelector(
                        domains: _domains,
                        selected: _domain,
                        onSelected: _selectDomain,
                      ),
                      const SizedBox(height: PulseTokens.spaceMd),
                      if (_snapshot != null)
                        _StatusBanner(snapshot: _snapshot!),
                      if (_error != null) ...[
                        const SizedBox(height: PulseTokens.spaceSm),
                        PulseCard(
                          child: Text(
                            _error!,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: PulseTokens.error),
                          ),
                        ),
                      ],
                      const SizedBox(height: PulseTokens.spaceMd),
                      Expanded(child: _buildBody(context)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final snap = _snapshot;
    if (snap == null && _error == null) {
      return PulseEmptyState(
        icon: LucideIcons.packageSearch,
        title: 'No inventory loaded',
        message: 'Choose a domain and refresh to load a catalog.',
        actionLabel: 'Load',
        onAction: () => _load(forceRefresh: false),
      );
    }
    if (snap != null &&
        snap.status != InventoryStatus.available &&
        snap.status != InventoryStatus.partial) {
      return PulseEmptyState(
        icon: _statusIcon(snap.status),
        title: inventoryStatusLabel(snap.status),
        message: snap.statusDetail.isEmpty
            ? 'This inventory domain could not be collected.'
            : snap.statusDetail,
        actionLabel: 'Retry',
        onAction: () => _load(forceRefresh: true),
      );
    }

    final rows = _rows();
    if (rows.isEmpty) {
      return PulseEmptyState(
        icon: LucideIcons.search,
        title: 'No matching items',
        message: _filter.isEmpty
            ? 'The collector returned an empty catalog for this domain.'
            : 'No items match “$_filter”.',
      );
    }

    final selected = rows.cast<_InventoryRow?>().firstWhere(
          (r) => r!.id == _selectedId,
          orElse: () => null,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final list = _InventoryList(
          rows: rows,
          selectedId: _selectedId,
          loading: _loading,
          onSelected: (id) => setState(() => _selectedId = id),
        );
        if (!wide) {
          return Column(
            children: [
              Expanded(child: list),
              if (selected != null) ...[
                const SizedBox(height: PulseTokens.spaceMd),
                SizedBox(
                  height: 220,
                  child: _InventoryDetail(row: selected),
                ),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: list),
            const SizedBox(width: PulseTokens.spaceMd),
            SizedBox(
              width: 360,
              child: selected == null
                  ? PulseCard(
                      child: Text(
                        'Select an item to inspect structured fields.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: PulseTokens.textSecondary,
                            ),
                      ),
                    )
                  : _InventoryDetail(row: selected),
            ),
          ],
        );
      },
    );
  }
}

class _DomainTab {
  const _DomainTab(this.id, this.label, this.icon);
  final InventoryDomainId id;
  final String label;
  final IconData icon;
}

class _InventoryRow {
  const _InventoryRow({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.details,
  });
  final String id;
  final String title;
  final String subtitle;
  final Map<String, String> details;
}

class _DomainSelector extends StatelessWidget {
  const _DomainSelector({
    required this.domains,
    required this.selected,
    required this.onSelected,
  });

  final List<_DomainTab> domains;
  final InventoryDomainId selected;
  final ValueChanged<InventoryDomainId> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final d in domains)
          _DomainChip(
            label: d.label,
            icon: d.icon,
            selected: d.id == selected,
            onTap: () => onSelected(d.id),
          ),
      ],
    );
  }
}

class _DomainChip extends StatelessWidget {
  const _DomainChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PulseTokens.accentSoft : PulseTokens.surface,
      borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
            border: Border.all(
              color: selected ? PulseTokens.accent : PulseTokens.strokeSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? PulseTokens.accent : PulseTokens.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected
                          ? PulseTokens.accent
                          : PulseTokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.snapshot});
  final InventoryDomainSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final tone = inventoryStatusTone(snapshot.status);
    final count = switch (snapshot.domain) {
      InventoryDomainId.services => snapshot.services.length,
      InventoryDomainId.drivers => snapshot.drivers.length,
      InventoryDomainId.software => snapshot.software.length,
      InventoryDomainId.usb => snapshot.usb.length,
      InventoryDomainId.pci => snapshot.pci.length,
      _ => 0,
    };
    return PulseCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          PulseBadge(
            label: inventoryStatusLabel(snapshot.status),
            tone: tone,
            compact: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              [
                '$count items',
                if (snapshot.generation > 0) 'gen ${snapshot.generation}',
                if (snapshot.truncated) 'truncated',
                if (snapshot.statusDetail.isNotEmpty) snapshot.statusDetail,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PulseTokens.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryList extends StatelessWidget {
  const _InventoryList({
    required this.rows,
    required this.selectedId,
    required this.onSelected,
    required this.loading,
  });

  final List<_InventoryRow> rows;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return PulseCard(
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: PulseTokens.strokeSubtle,
            ),
            itemBuilder: (context, index) {
              final row = rows[index];
              final selected = row.id == selectedId;
              return ListTile(
                selected: selected,
                selectedTileColor: PulseTokens.accentSoft,
                title: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  row.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PulseTokens.textSecondary,
                      ),
                ),
                onTap: () => onSelected(row.id),
              );
            },
          ),
          if (loading)
            const Positioned(
              top: 8,
              right: 8,
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _InventoryDetail extends StatelessWidget {
  const _InventoryDetail({required this.row});
  final _InventoryRow row;

  @override
  Widget build(BuildContext context) {
    return PulseCard(
      child: ListView(
        children: [
          Text(
            row.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            row.id,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PulseTokens.textSecondary,
                  fontFamily: 'Consolas',
                ),
          ),
          const SizedBox(height: PulseTokens.spaceMd),
          for (final e in row.details.entries)
            if (e.value.isNotEmpty) ...[
              Text(
                e.key,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: PulseTokens.textSecondary,
                    ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                e.value,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: PulseTokens.spaceSm),
            ],
        ],
      ),
    );
  }
}

String inventoryStatusLabel(InventoryStatus status) => switch (status) {
      InventoryStatus.available => 'Available',
      InventoryStatus.unsupported => 'Unsupported',
      InventoryStatus.accessDenied => 'Access denied',
      InventoryStatus.partial => 'Partial',
      InventoryStatus.error => 'Error',
      InventoryStatus.unspecified => 'Unknown',
    };

PulseBadgeTone inventoryStatusTone(InventoryStatus status) => switch (status) {
      InventoryStatus.available => PulseBadgeTone.success,
      InventoryStatus.partial => PulseBadgeTone.warning,
      InventoryStatus.unsupported => PulseBadgeTone.neutral,
      InventoryStatus.accessDenied => PulseBadgeTone.error,
      InventoryStatus.error => PulseBadgeTone.error,
      InventoryStatus.unspecified => PulseBadgeTone.neutral,
    };

IconData _statusIcon(InventoryStatus status) => switch (status) {
      InventoryStatus.accessDenied => LucideIcons.lock,
      InventoryStatus.unsupported => LucideIcons.circleMinus,
      InventoryStatus.error => LucideIcons.triangleAlert,
      _ => LucideIcons.packageSearch,
    };
