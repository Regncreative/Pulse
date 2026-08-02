import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import 'inventory_catalog.dart';

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

enum _SortField { title, id, subtitle }

/// Professional inventory browser (ADR-011) — tree nav + virtualized catalog.
class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.title});

  final String title;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  InventoryDomainId _domain = InventoryDomainId.services;
  InventoryDomainSnapshot? _snapshot;
  String? _error;
  bool _loading = false;
  String _filter = '';
  String? _selectedId;
  _SortField _sortField = _SortField.title;
  bool _sortAscending = true;
  String? _stateFilter;
  final Set<String> _expandedGroups = {
    for (final g in kInventoryBrowserGroups) g.id,
  };

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
    final node = inventoryNodeFor(_domain);
    if (node == null || !node.implemented) {
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
      _stateFilter = null;
      _error = null;
    });
    final node = inventoryNodeFor(domain);
    if (node != null && node.implemented) {
      _load(forceRefresh: false);
    }
  }

  List<_InventoryRow> _allRows() {
    final snap = _snapshot;
    if (snap == null) return const [];
    final rows = <_InventoryRow>[];
    switch (snap.domain) {
      case InventoryDomainId.services:
        for (final e in snap.services) {
          rows.add(_InventoryRow(
            id: e.id,
            title: e.displayName.isEmpty ? e.id : e.displayName,
            subtitle: '${e.id} · ${e.state} · ${e.startType}',
            filterKey: e.state,
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
            filterKey: e.state,
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
            filterKey: e.architecture,
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
          rows.add(_pnpRow(
            id: e.id,
            description: e.description,
            manufacturer: e.manufacturer,
            className: e.className,
            hardwareId: e.hardwareId,
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
          rows.add(_pnpRow(
            id: e.id,
            description: e.description,
            manufacturer: e.manufacturer,
            className: e.className,
            hardwareId: e.locationInfo.isNotEmpty ? e.locationInfo : e.hardwareId,
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
      case InventoryDomainId.displays:
        for (final e in snap.displays) {
          rows.add(_pnpRow(
            id: e.id,
            description: e.description,
            manufacturer: e.manufacturer,
            className: e.className,
            hardwareId: e.adapterName.isNotEmpty ? e.adapterName : e.hardwareId,
            details: {
              'id': e.id,
              'description': e.description,
              'hardware_id': e.hardwareId,
              'manufacturer': e.manufacturer,
              'service': e.service,
              'class_name': e.className,
              'class_guid': e.classGuid,
              'location_info': e.locationInfo,
              'adapter_name': e.adapterName,
              'description_from_enum_display':
                  e.descriptionFromEnumDisplay ? 'true' : 'false',
              if (e.hasProblemCode) 'problem_code': '${e.problemCode}',
            },
          ));
        }
      case InventoryDomainId.audio:
        for (final e in snap.audio) {
          rows.add(_pnpRow(
            id: e.id,
            description: e.description,
            manufacturer: e.manufacturer,
            className: e.className,
            hardwareId: e.hardwareId,
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
      case InventoryDomainId.bluetooth:
        for (final e in snap.bluetooth) {
          rows.add(_pnpRow(
            id: e.id,
            description: e.description,
            manufacturer: e.manufacturer,
            className: e.className,
            hardwareId: e.hardwareId,
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
      case InventoryDomainId.printers:
        for (final e in snap.printers) {
          rows.add(_InventoryRow(
            id: e.id,
            title: e.id,
            subtitle: [
              if (e.driverName.isNotEmpty) e.driverName,
              if (e.portName.isNotEmpty) e.portName,
              if (e.isDefault) 'default',
              if (e.isShared) 'shared',
              if (e.isNetwork) 'network',
            ].join(' · '),
            filterKey: e.isDefault
                ? 'default'
                : (e.isNetwork ? 'network' : 'local'),
            details: {
              'id': e.id,
              'port_name': e.portName,
              'driver_name': e.driverName,
              'location': e.location,
              'comment': e.comment,
              'is_shared': e.isShared ? 'true' : 'false',
              'is_default': e.isDefault ? 'true' : 'false',
              'is_network': e.isNetwork ? 'true' : 'false',
              if (e.hasAttributes) 'attributes': '${e.attributes}',
            },
          ));
        }
      case InventoryDomainId.battery:
        for (final e in snap.batteries) {
          rows.add(_InventoryRow(
            id: e.id,
            title: e.description.isEmpty ? e.id : e.description,
            subtitle: [
              if (e.hasCapacityPercent) '${e.capacityPercent}%',
              if (e.powerState.isNotEmpty) e.powerState,
              if (e.chemistry.isNotEmpty) e.chemistry,
              if (e.fromSystemPowerFallback) 'system_power',
            ].join(' · '),
            filterKey: e.powerState,
            details: {
              'id': e.id,
              'description': e.description,
              'manufacturer': e.manufacturer,
              'chemistry': e.chemistry,
              if (e.hasDesignCapacity)
                'design_capacity_mwh': '${e.designCapacityMwh}',
              if (e.hasFullChargedCapacity)
                'full_charged_capacity_mwh': '${e.fullChargedCapacityMwh}',
              if (e.hasCycleCount) 'cycle_count': '${e.cycleCount}',
              if (e.hasCapacityPercent)
                'capacity_percent': '${e.capacityPercent}',
              'power_state': e.powerState,
              'from_system_power_fallback':
                  e.fromSystemPowerFallback ? 'true' : 'false',
            },
          ));
        }
      default:
        break;
    }
    return rows;
  }

  _InventoryRow _pnpRow({
    required String id,
    required String description,
    required String manufacturer,
    required String className,
    required String hardwareId,
    required Map<String, String> details,
  }) {
    return _InventoryRow(
      id: id,
      title: description.isEmpty ? id : description,
      subtitle: [
        if (manufacturer.isNotEmpty) manufacturer,
        if (className.isNotEmpty) className,
        if (hardwareId.isNotEmpty) hardwareId,
      ].join(' · '),
      filterKey: className,
      details: details,
    );
  }

  List<_InventoryRow> _visibleRows() {
    var rows = _allRows();
    final q = _filter.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows = rows
          .where((r) =>
              r.title.toLowerCase().contains(q) ||
              r.subtitle.toLowerCase().contains(q) ||
              r.id.toLowerCase().contains(q) ||
              r.details.values.any((v) => v.toLowerCase().contains(q)))
          .toList();
    }
    final sf = _stateFilter;
    if (sf != null && sf.isNotEmpty) {
      rows = rows.where((r) => r.filterKey.toLowerCase() == sf).toList();
    }
    rows.sort((a, b) {
      final cmp = switch (_sortField) {
        _SortField.title =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        _SortField.id => a.id.toLowerCase().compareTo(b.id.toLowerCase()),
        _SortField.subtitle =>
          a.subtitle.toLowerCase().compareTo(b.subtitle.toLowerCase()),
      };
      return _sortAscending ? cmp : -cmp;
    });
    return rows;
  }

  List<String> _filterOptions() {
    final keys = _allRows()
        .map((r) => r.filterKey.trim().toLowerCase())
        .where((k) => k.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return keys;
  }

  Future<void> _copySelected(_InventoryRow? row) async {
    if (row == null) return;
    final buffer = StringBuffer()
      ..writeln(row.title)
      ..writeln(row.id);
    for (final e in row.details.entries) {
      if (e.value.isEmpty) continue;
      buffer.writeln('${e.key}=${e.value}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied item to clipboard')),
    );
  }

  Future<void> _exportVisible(List<_InventoryRow> rows) async {
    final buffer = StringBuffer();
    buffer.writeln('# Pulse Inventory export');
    buffer.writeln('domain=${_domain.name}');
    final snap = _snapshot;
    if (snap != null) {
      buffer.writeln('status=${snap.status.name}');
      buffer.writeln('generation=${snap.generation}');
      buffer.writeln('status_detail=${snap.statusDetail}');
    }
    buffer.writeln('items=${rows.length}');
    buffer.writeln('---');
    for (final row in rows) {
      buffer.writeln('id=${row.id}');
      buffer.writeln('title=${row.title}');
      for (final e in row.details.entries) {
        if (e.value.isEmpty) continue;
        buffer.writeln('${e.key}=${e.value}');
      }
      buffer.writeln('---');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${rows.length} items to clipboard')),
    );
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
    final node = inventoryNodeFor(_domain);
    final rows = _visibleRows();
    final selected = rows.cast<_InventoryRow?>().firstWhere(
          (r) => r!.id == _selectedId,
          orElse: () => null,
        );

    return Column(
      children: [
        PulseAppBar(
          title: widget.title,
          connectionState: state,
          connectionLabel: connectionLabel,
          searchEnabled: !offline && (node?.implemented ?? false),
          searchHint: 'Search this domain…',
          searchQuery: _filter,
          onSearchChanged: (v) => setState(() => _filter = v),
          actions: [
            PulseButton(
              label: 'Copy',
              icon: LucideIcons.copy,
              variant: PulseButtonVariant.secondary,
              onPressed: offline || selected == null
                  ? null
                  : () => _copySelected(selected),
            ),
            PulseButton(
              label: 'Export',
              icon: LucideIcons.download,
              variant: PulseButtonVariant.secondary,
              onPressed: offline || rows.isEmpty
                  ? null
                  : () => _exportVisible(rows),
            ),
            PulseButton(
              label: 'Refresh',
              icon: LucideIcons.refreshCw,
              variant: PulseButtonVariant.secondary,
              onPressed: offline ||
                      _loading ||
                      !(node?.implemented ?? false)
                  ? null
                  : () => _load(forceRefresh: true),
            ),
          ],
        ),
        Expanded(
          child: offline
              ? const ServiceOfflineRecovery(
                  titleFallback: 'Connect to PulseService to browse inventory.',
                )
              : Padding(
                  padding: EdgeInsets.fromLTRB(
                    PulseTokens.pagePadX,
                    PulseTokens.spaceMd,
                    PulseTokens.pagePadX,
                    PulseTokens.spaceLg,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 240,
                        child: _InventoryTree(
                          selected: _domain,
                          expandedGroups: _expandedGroups,
                          onToggleGroup: (id) {
                            setState(() {
                              if (_expandedGroups.contains(id)) {
                                _expandedGroups.remove(id);
                              } else {
                                _expandedGroups.add(id);
                              }
                            });
                          },
                          onSelected: _selectDomain,
                        ),
                      ),
                      const SizedBox(width: PulseTokens.spaceMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _DomainHeader(
                              node: node,
                              snapshot: _snapshot,
                              loading: _loading,
                              filterOptions: _filterOptions(),
                              stateFilter: _stateFilter,
                              sortField: _sortField,
                              sortAscending: _sortAscending,
                              onStateFilter: (v) =>
                                  setState(() => _stateFilter = v),
                              onSortField: (v) =>
                                  setState(() => _sortField = v),
                              onToggleSortDir: () => setState(
                                  () => _sortAscending = !_sortAscending),
                            ),
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
                            Expanded(
                              child: _buildCatalog(
                                context,
                                node: node,
                                rows: rows,
                                selected: selected,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildCatalog(
    BuildContext context, {
    required InventoryDomainNode? node,
    required List<_InventoryRow> rows,
    required _InventoryRow? selected,
  }) {
    if (node == null) {
      return const PulseEmptyState(
        icon: LucideIcons.packageSearch,
        title: 'Select a domain',
        message: 'Choose a domain from the inventory browser tree.',
      );
    }
    if (!node.implemented) {
      return PulseEmptyState(
        icon: LucideIcons.clock,
        title: '${node.label} — coming in P2',
        message:
            'This System domain is reserved. Collectors ship after the P1 '
            'Inventory platform validation report.',
      );
    }
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final snap = _snapshot;
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
    if (rows.isEmpty) {
      return PulseEmptyState(
        icon: LucideIcons.search,
        title: 'No matching items',
        message: _filter.isEmpty && (_stateFilter == null)
            ? 'The collector returned an empty catalog for this domain.'
            : 'No items match the current search/filter.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
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
                  height: 240,
                  child: _InventoryDetail(
                    row: selected,
                    onCopyValue: (v) async {
                      await Clipboard.setData(ClipboardData(text: v));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied value')),
                      );
                    },
                  ),
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
                  : _InventoryDetail(
                      row: selected,
                      onCopyValue: (v) async {
                        await Clipboard.setData(ClipboardData(text: v));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied value')),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _InventoryRow {
  const _InventoryRow({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.details,
    this.filterKey = '',
  });
  final String id;
  final String title;
  final String subtitle;
  final String filterKey;
  final Map<String, String> details;
}

class _InventoryTree extends StatelessWidget {
  const _InventoryTree({
    required this.selected,
    required this.expandedGroups,
    required this.onToggleGroup,
    required this.onSelected,
  });

  final InventoryDomainId selected;
  final Set<String> expandedGroups;
  final ValueChanged<String> onToggleGroup;
  final ValueChanged<InventoryDomainId> onSelected;

  @override
  Widget build(BuildContext context) {
    return PulseCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Text(
              'Inventory',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          for (final group in kInventoryBrowserGroups) ...[
            InkWell(
              onTap: () => onToggleGroup(group.id),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      expandedGroups.contains(group.id)
                          ? LucideIcons.chevronDown
                          : LucideIcons.chevronRight,
                      size: 14,
                      color: PulseTokens.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Icon(group.icon, size: 15, color: PulseTokens.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      group.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            if (expandedGroups.contains(group.id))
              for (final node in group.domains)
                _TreeLeaf(
                  node: node,
                  selected: node.id == selected,
                  onTap: () => onSelected(node.id),
                ),
          ],
        ],
      ),
    );
  }
}

class _TreeLeaf extends StatelessWidget {
  const _TreeLeaf({
    required this.node,
    required this.selected,
    required this.onTap,
  });

  final InventoryDomainNode node;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PulseTokens.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(34, 7, 12, 7),
          child: Row(
            children: [
              Icon(
                node.icon,
                size: 14,
                color: selected ? PulseTokens.accent : PulseTokens.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: selected
                            ? PulseTokens.accent
                            : PulseTokens.textPrimary,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              ),
              if (!node.implemented)
                Text(
                  'P2',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: PulseTokens.textSecondary,
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DomainHeader extends StatelessWidget {
  const _DomainHeader({
    required this.node,
    required this.snapshot,
    required this.loading,
    required this.filterOptions,
    required this.stateFilter,
    required this.sortField,
    required this.sortAscending,
    required this.onStateFilter,
    required this.onSortField,
    required this.onToggleSortDir,
  });

  final InventoryDomainNode? node;
  final InventoryDomainSnapshot? snapshot;
  final bool loading;
  final List<String> filterOptions;
  final String? stateFilter;
  final _SortField sortField;
  final bool sortAscending;
  final ValueChanged<String?> onStateFilter;
  final ValueChanged<_SortField> onSortField;
  final VoidCallback onToggleSortDir;

  @override
  Widget build(BuildContext context) {
    final snap = snapshot;
    final count = snap == null
        ? 0
        : switch (snap.domain) {
            InventoryDomainId.services => snap.services.length,
            InventoryDomainId.drivers => snap.drivers.length,
            InventoryDomainId.software => snap.software.length,
            InventoryDomainId.usb => snap.usb.length,
            InventoryDomainId.pci => snap.pci.length,
            InventoryDomainId.displays => snap.displays.length,
            InventoryDomainId.audio => snap.audio.length,
            InventoryDomainId.bluetooth => snap.bluetooth.length,
            InventoryDomainId.printers => snap.printers.length,
            InventoryDomainId.battery => snap.batteries.length,
            _ => 0,
          };

    return PulseCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (node != null) ...[
                Icon(node!.icon, size: 18, color: PulseTokens.accent),
                const SizedBox(width: 8),
                Text(
                  node!.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 10),
              ],
              if (snap != null)
                PulseBadge(
                  label: inventoryStatusLabel(snap.status),
                  tone: inventoryStatusTone(snap.status),
                  compact: true,
                ),
              if (loading) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              const Spacer(),
              Text(
                snap == null
                    ? 'Not loaded'
                    : [
                        '$count items',
                        if (snap.generation > 0) 'gen ${snap.generation}',
                        if (snap.truncated) 'truncated',
                      ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: PulseTokens.textSecondary,
                    ),
              ),
            ],
          ),
          if (snap != null && snap.statusDetail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              snap.statusDetail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PulseTokens.textSecondary,
                  ),
            ),
          ],
          if (node?.implemented == true) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String?>(
                    initialValue: stateFilter,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Filter',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All'),
                      ),
                      for (final opt in filterOptions)
                        DropdownMenuItem<String?>(
                          value: opt,
                          child: Text(opt),
                        ),
                    ],
                    onChanged: onStateFilter,
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<_SortField>(
                    initialValue: sortField,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Sort',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _SortField.title,
                        child: Text('Title'),
                      ),
                      DropdownMenuItem(
                        value: _SortField.id,
                        child: Text('Id'),
                      ),
                      DropdownMenuItem(
                        value: _SortField.subtitle,
                        child: Text('Subtitle'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) onSortField(v);
                    },
                  ),
                ),
                IconButton(
                  tooltip: sortAscending ? 'Ascending' : 'Descending',
                  onPressed: onToggleSortDir,
                  icon: Icon(
                    sortAscending ? LucideIcons.arrowUp : LucideIcons.arrowDown,
                    size: 18,
                  ),
                ),
              ],
            ),
          ],
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
                title: Text(
                  row.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
  const _InventoryDetail({
    required this.row,
    required this.onCopyValue,
  });

  final _InventoryRow row;
  final ValueChanged<String> onCopyValue;

  @override
  Widget build(BuildContext context) {
    return PulseCard(
      child: ListView(
        children: [
          Text(row.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          SelectableText(
            row.id,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PulseTokens.textSecondary,
                  fontFamily: 'Consolas',
                ),
          ),
          const SizedBox(height: PulseTokens.spaceMd),
          for (final e in row.details.entries)
            if (e.value.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: PulseTokens.textSecondary,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy value',
                    visualDensity: VisualDensity.compact,
                    iconSize: 14,
                    onPressed: () => onCopyValue(e.value),
                    icon: const Icon(LucideIcons.copy),
                  ),
                ],
              ),
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
