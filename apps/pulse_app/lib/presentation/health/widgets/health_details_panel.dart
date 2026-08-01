import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../../app/theme/pulse_theme.dart';
import '../../../features/timeline/widgets/detail_section.dart';
import '../../../ipc/pulse_ipc_client.dart';
import '../health_cards.dart';
import '../health_view_models.dart';
import 'health_spec_rows.dart';
import 'process_app_icon.dart';
import 'process_inventory/memory_app_detail_panel.dart';
import 'process_inventory/process_detail_panel.dart';
import 'process_inventory/process_inventory_list.dart';
import 'process_inventory/process_inventory_store.dart';
import 'process_inventory/app_group_engine.dart';

/// Right-side System Health details panel for a selected metric group.
class HealthDetailsPanel extends StatelessWidget {
  const HealthDetailsPanel({
    super.key,
    required this.kind,
    required this.view,
    required this.onClose,
    this.processInventory,
  });

  final HealthPanelKind kind;
  final HealthViewState view;
  final VoidCallback onClose;
  final ProcessInventoryStore? processInventory;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PulseTokens.sidebarSolid.withValues(alpha: 0.98),
        border: const Border(
          left: BorderSide(color: PulseTokens.strokeSubtle),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 22,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailsHeader(
            title: kind.title,
            subtitle: _subtitle(),
            onClose: onClose,
          ),
          const Divider(height: 1, color: PulseTokens.strokeSubtle),
          Expanded(
            child: _sectionsBody(),
          ),
        ],
      ),
    );
  }

  /// Single-viewport panel body — no scroll (mockup parity).
  Widget _sectionsBody() {
    return switch (kind) {
      HealthPanelKind.cpu => _CpuPanelBody(
            view: view,
            inventory: processInventory,
          ),
      HealthPanelKind.memory => _MemoryPanelBody(
            view: view,
            inventory: processInventory,
          ),
      HealthPanelKind.gpu => _GpuPanelBody(
            view: view,
            inventory: processInventory,
          ),
      HealthPanelKind.disk => _DiskPanelBody(view: view),
      HealthPanelKind.network => _NetworkPanelBody(view: view),
    };
  }

  String? _subtitle() {
    final i = view.info;
    return switch (kind) {
      HealthPanelKind.cpu => _orNull(i?.cpuModel),
      HealthPanelKind.memory => (i?.installedRamBytes ?? 0) > 0
          ? formatMemorySize(i!.installedRamBytes)
          : null,
      HealthPanelKind.gpu => _orNull(i?.gpuModel),
      HealthPanelKind.disk => (i?.primaryStorageBytes ?? 0) > 0
          ? formatBytesBinary(i!.primaryStorageBytes, fractionDigits: 0)
          : null,
      HealthPanelKind.network => _orNull(i?.activeNetworkAdapter),
    };
  }

  static String? _orNull(String? value) {
    final t = value?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

}

class _CpuPanelBody extends StatefulWidget {
  const _CpuPanelBody({required this.view, this.inventory});
  final HealthViewState view;
  final ProcessInventoryStore? inventory;

  @override
  State<_CpuPanelBody> createState() => _CpuPanelBodyState();
}

class _CpuPanelBodyState extends State<_CpuPanelBody> {
  ProcessDetails? _details;
  bool _detailsLoading = false;
  String? _detailsError;
  int? _loadedPid;

  @override
  void initState() {
    super.initState();
    widget.inventory?.addListener(_onInventory);
  }

  @override
  void didUpdateWidget(covariant _CpuPanelBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inventory != widget.inventory) {
      oldWidget.inventory?.removeListener(_onInventory);
      widget.inventory?.addListener(_onInventory);
    }
  }

  @override
  void dispose() {
    widget.inventory?.removeListener(_onInventory);
    super.dispose();
  }

  void _onInventory() {
    final store = widget.inventory;
    if (store == null) return;
    final pid = store.selectedPid;
    if (pid == null) {
      if (_details != null || _detailsLoading || _detailsError != null) {
        setState(() {
          _details = null;
          _detailsLoading = false;
          _detailsError = null;
          _loadedPid = null;
        });
      }
      return;
    }
    if (pid == _loadedPid && (_details != null || _detailsLoading)) return;
    unawaited(_loadDetails(pid));
  }

  Future<void> _loadDetails(int pid) async {
    setState(() {
      _loadedPid = pid;
      _detailsLoading = true;
      _detailsError = null;
      _details = null;
    });
    try {
      final ipc = context.read<PulseIpcClient>();
      final d = await ipc.getProcessDetails(pid);
      if (!mounted || widget.inventory?.selectedPid != pid) return;
      setState(() {
        _details = d;
        _detailsLoading = false;
      });
    } catch (_) {
      if (!mounted || widget.inventory?.selectedPid != pid) return;
      setState(() {
        _detailsLoading = false;
        _detailsError = 'Details unavailable';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final s = view.sample;
    final i = view.info;
    final usagePct = s != null && s.hasCpuPercent ? s.cpuPercent : null;
    final currentMhz = s != null && s.hasCpuCurrentMhz
        ? formatMhz(s.cpuCurrentMhz)
        : kUnavailableDash;
    final baseMhz = (i?.cpuBaseMhz ?? 0) > 0
        ? formatMhz(i!.cpuBaseMhz)
        : kUnavailableDash;
    final cores = (i?.cpuCores ?? 0) > 0
        ? i!.cpuCores.toString()
        : kUnavailableDash;
    final threads = (i?.cpuLogicalProcessors ?? 0) > 0
        ? i!.cpuLogicalProcessors.toString()
        : kUnavailableDash;
    final virt = i == null
        ? kUnavailableDash
        : (i.cpuVirtualizationEnabled ? 'Enabled' : 'Disabled');
    final sockets = (i?.cpuSockets ?? 0) > 0
        ? i!.cpuSockets.toString()
        : kUnavailableDash;
    final numaNodes = (i?.cpuNumaNodes ?? 0) > 0
        ? i!.cpuNumaNodes.toString()
        : kUnavailableDash;
    final l1 = i == null
        ? kUnavailableDash
        : formatBytesOrDash(i.hasCpuL1Cache, i.cpuL1CacheBytes);
    final l2 = i == null
        ? kUnavailableDash
        : formatBytesOrDash(i.hasCpuL2Cache, i.cpuL2CacheBytes);
    final l3 = i == null
        ? kUnavailableDash
        : formatBytesOrDash(i.hasCpuL3Cache, i.cpuL3CacheBytes);
    final architecture = orDash(i?.cpuArchitecture);
    final instructionSet = orDash(i?.cpuInstructionSet);
    final virtVendor = orDash(i?.cpuVirtualizationVendor);
    final smt = i == null
        ? kUnavailableDash
        : formatBoolOrDash(
            i.hasCpuSmt,
            i.cpuSmtEnabled,
            yes: 'Enabled',
            no: 'Disabled',
          );
    final store = widget.inventory;
    final selected = store?.selectedPid;
    final selectedEntry = selected == null ? null : store?.entry(selected);

    return Column(
      children: [
        Expanded(
          flex: 5,
          child: DetailSection(
            title: 'Overview',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            expandChild: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UsageGauge(
                  percent: usagePct,
                  label: usagePct != null
                      ? '${usagePct.toStringAsFixed(0)}% Usage'
                      : 'Usage',
                  compact: true,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HealthSpecSection(
                          compact: true,
                          rows: [
                            HealthSpecRow(label: 'Speed', value: currentMhz),
                            HealthSpecRow(
                              label: 'Base Speed',
                              value: baseMhz,
                            ),
                            HealthSpecRow(label: 'Cores', value: cores),
                            HealthSpecRow(
                              label: 'Logical Processors',
                              value: threads,
                            ),
                            HealthSpecRow(label: 'Sockets', value: sockets),
                            HealthSpecRow(
                              label: 'NUMA Nodes',
                              value: numaNodes,
                            ),
                            HealthSpecRow(
                              label: 'Temperature',
                              value: formatTempC(
                                s?.hasCpuTempC ?? false,
                                s?.cpuTempC ?? 0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        HealthSpecSection(
                          title: 'Architecture',
                          compact: true,
                          rows: [
                            HealthSpecRow(
                              label: 'Architecture',
                              value: architecture,
                            ),
                            HealthSpecRow(
                              label: 'Instruction Set',
                              value: instructionSet,
                            ),
                            HealthSpecRow(label: 'SMT', value: smt),
                            HealthSpecRow(
                              label: 'Virtualization',
                              value: virt,
                            ),
                            HealthSpecRow(
                              label: 'Virtualization Vendor',
                              value: virtVendor,
                            ),
                            HealthSpecRow(label: 'L1 Cache', value: l1),
                            HealthSpecRow(label: 'L2 Cache', value: l2),
                            HealthSpecRow(label: 'L3 Cache', value: l3),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 5,
          child: DetailSection(
            title: store == null
                ? 'Processes'
                : 'Processes (${store.totalCount})',
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            expandChild: true,
            child: store == null
                ? _ProcessList(
                    processes: s?.topCpu ?? const [],
                    kind: HealthPanelKind.cpu,
                    compact: true,
                  )
                : ProcessInventoryList(store: store, compact: true),
          ),
        ),
        if (selectedEntry != null) ...[
          const Divider(height: 1, color: PulseTokens.strokeSubtle),
          SizedBox(
            height: 260,
            child: ProcessDetailPanel(
              entry: selectedEntry,
              details: _details,
              loading: _detailsLoading,
              error: _detailsError,
              compact: true,
              onClose: () => store?.select(null),
            ),
          ),
        ],
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 3,
          child: DetailSection(
            title: view.coreHistories.isNotEmpty
                ? 'CPU History (Per Core)'
                : 'CPU History',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            expandChild: true,
            child: view.coreHistories.isNotEmpty
                ? _CoreHistoryGrid(
                    histories: view.coreHistories,
                    compact: true,
                  )
                : _HistorySparkline(
                    values: view.cpuHistory,
                    fillHeight: true,
                  ),
          ),
        ),
      ],
    );
  }
}

class _MemoryPanelBody extends StatefulWidget {
  const _MemoryPanelBody({required this.view, this.inventory});
  final HealthViewState view;
  final ProcessInventoryStore? inventory;

  @override
  State<_MemoryPanelBody> createState() => _MemoryPanelBodyState();
}

class _MemoryPanelBodyState extends State<_MemoryPanelBody> {
  @override
  void initState() {
    super.initState();
    widget.inventory?.addListener(_onInventory);
  }

  @override
  void didUpdateWidget(covariant _MemoryPanelBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inventory != widget.inventory) {
      oldWidget.inventory?.removeListener(_onInventory);
      widget.inventory?.addListener(_onInventory);
    }
  }

  @override
  void dispose() {
    widget.inventory?.removeListener(_onInventory);
    super.dispose();
  }

  void _onInventory() {
    if (mounted) setState(() {});
  }

  ProcessAppGroup? _selectedGroup() {
    final store = widget.inventory;
    final pid = store?.selectedPid;
    if (store == null || pid == null) return null;
    final groups = AppGroupEngine.build(store);
    for (final g in groups) {
      if (g.memberPids.contains(pid)) return g;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final s = view.sample;
    final i = view.info;
    final used = s?.memoryUsedBytes ?? 0;
    final total = s?.memoryTotalBytes ?? 0;
    final usagePct = total > 0 ? used * 100.0 / total : null;
    final usedLabel = total > 0
        ? '${formatMemorySize(used)} / ${formatMemorySize(total)}'
        : kUnavailableDash;
    final available = s != null && total > 0
        ? formatMemorySize(s.memoryAvailableBytes)
        : kUnavailableDash;
    final committed = s?.hasMemoryCommitted == true
        ? '${formatMemorySize(s!.memoryCommittedBytes)} / ${formatMemorySize(s.memoryCommitLimitBytes)}'
        : kUnavailableDash;
    final cached = s?.hasMemoryCached == true
        ? formatMemorySize(s!.memoryCachedBytes)
        : kUnavailableDash;
    final compressed = s?.hasMemoryCompressed == true
        ? formatMemorySize(s!.memoryCompressedBytes)
        : kUnavailableDash;
    final hardwareReserved = s?.hasMemoryHardwareReserved == true
        ? formatMemorySize(s!.memoryHardwareReservedBytes)
        : kUnavailableDash;
    final pagedPool = s?.hasMemoryPagedPool == true
        ? formatMemorySize(s!.memoryPagedPoolBytes)
        : kUnavailableDash;
    final nonpagedPool = s?.hasMemoryNonpagedPool == true
        ? formatMemorySize(s!.memoryNonpagedPoolBytes)
        : kUnavailableDash;
    final pageFaults = s?.hasMemoryPageFaultsPerSec == true
        ? s!.memoryPageFaultsPerSec.toStringAsFixed(0)
        : kUnavailableDash;

    final slotsUsed = i == null
        ? kUnavailableDash
        : formatCount(i.hasMemSlotsUsed, i.memSlotsUsed);
    final moduleCount = i == null
        ? kUnavailableDash
        : formatCount(i.hasMemModuleCount, i.memModuleCount);
    final channels = i == null
        ? kUnavailableDash
        : formatCount(i.hasMemChannels, i.memChannels);
    final ddrGeneration = orDash(i?.memDdrGeneration);
    final speedMhz = i == null || !i.hasMemSpeedMhz || i.memSpeedMhz <= 0
        ? kUnavailableDash
        : '${i.memSpeedMhz} MHz';
    final formFactor = orDash(i?.memFormFactor);
    final ecc = i == null
        ? kUnavailableDash
        : formatBoolOrDash(i.hasMemEcc, i.memEcc);
    final dimmVendor = orDash(i?.memDimmVendor);
    final dimmPart = orDash(i?.memDimmPartNumber);
    final dimmSerial = orDash(i?.memDimmSerial);

    final store = widget.inventory;
    final selectedGroup = _selectedGroup();

    return Column(
      children: [
        Expanded(
          flex: 4,
          child: DetailSection(
            title: 'Overview',
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            expandChild: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UsageGauge(
                  percent: usagePct,
                  label: usagePct != null
                      ? '${usagePct.toStringAsFixed(0)}% In use'
                      : 'In use',
                  compact: true,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HealthSpecSection(
                          compact: true,
                          rows: [
                            HealthSpecRow(
                              label: 'Used / Total',
                              value: usedLabel,
                            ),
                            HealthSpecRow(
                              label: 'Available',
                              value: available,
                            ),
                            HealthSpecRow(
                              label: 'Committed',
                              value: committed,
                            ),
                            HealthSpecRow(label: 'Cached', value: cached),
                            HealthSpecRow(
                              label: 'Memory Compression',
                              value: compressed,
                            ),
                            HealthSpecRow(
                              label: 'Hardware Reserved',
                              value: hardwareReserved,
                            ),
                            HealthSpecRow(
                              label: 'Paged Pool',
                              value: pagedPool,
                            ),
                            HealthSpecRow(
                              label: 'Non-paged Pool',
                              value: nonpagedPool,
                            ),
                            HealthSpecRow(
                              label: 'Page Faults/sec',
                              value: pageFaults,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        HealthSpecSection(
                          title: 'Modules',
                          compact: true,
                          rows: [
                            HealthSpecRow(
                              label: 'Slots Used',
                              value: slotsUsed,
                            ),
                            HealthSpecRow(
                              label: 'Module Count',
                              value: moduleCount,
                            ),
                            HealthSpecRow(
                              label: 'Channels',
                              value: channels,
                            ),
                            HealthSpecRow(
                              label: 'Generation',
                              value: ddrGeneration,
                            ),
                            HealthSpecRow(label: 'Speed', value: speedMhz),
                            HealthSpecRow(
                              label: 'Form Factor',
                              value: formFactor,
                            ),
                            HealthSpecRow(label: 'ECC', value: ecc),
                            HealthSpecRow(
                              label: 'DIMM Vendor',
                              value: dimmVendor,
                            ),
                            HealthSpecRow(
                              label: 'DIMM Part Number',
                              value: dimmPart,
                            ),
                            HealthSpecRow(
                              label: 'DIMM Serial',
                              value: dimmSerial,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 6,
          child: DetailSection(
            title: store == null
                ? 'Processes'
                : 'Processes (${store.totalCount})',
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            expandChild: true,
            child: store == null
                ? _ProcessList(
                    processes: s?.topMemory ?? const [],
                    kind: HealthPanelKind.memory,
                    compact: true,
                  )
                : ProcessInventoryList(
                    store: store,
                    compact: true,
                    groupSort: ProcessGroupSort.memoryDescending,
                    memoryFormat: true,
                  ),
          ),
        ),
        if (selectedGroup != null) ...[
          const Divider(height: 1, color: PulseTokens.strokeSubtle),
          SizedBox(
            height: 220,
            child: MemoryAppDetailPanel(
              group: selectedGroup,
              store: store!,
              compact: true,
              onClose: () => store.select(null),
            ),
          ),
        ],
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 2,
          child: DetailSection(
            title: 'Memory History',
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            expandChild: true,
            child: _HistorySparkline(
              values: view.memoryHistory,
              fillHeight: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _GpuPanelBody extends StatelessWidget {
  const _GpuPanelBody({required this.view, this.inventory});
  final HealthViewState view;
  final ProcessInventoryStore? inventory;

  @override
  Widget build(BuildContext context) {
    final s = view.sample;
    final i = view.info;
    final usagePct = s != null && s.hasGpuPercent ? s.gpuPercent : null;
    final store = inventory;

    final dedicatedCapacity = i?.gpuDedicatedBytes ?? 0;
    final sharedCapacity = i?.gpuSharedBytes ?? 0;
    final totalCapacity = dedicatedCapacity + sharedCapacity;
    final dedicatedUsedBytes = s?.gpuDedicatedUsedBytes ?? 0;
    final sharedUsedBytes = s?.gpuSharedUsedBytes ?? 0;
    final hasDedicatedUsed = s?.hasGpuDedicatedUsed ?? false;
    final hasSharedUsed = s?.hasGpuSharedUsed ?? false;

    final engineHistories = <(String, List<double>)>[
      if (view.gpu3dHistory.isNotEmpty) ('3D', view.gpu3dHistory),
      if (view.gpuComputeHistory.isNotEmpty) ('Compute', view.gpuComputeHistory),
      if (view.gpuCopyHistory.isNotEmpty) ('Copy', view.gpuCopyHistory),
      if (view.gpuDecodeHistory.isNotEmpty) ('Decode', view.gpuDecodeHistory),
      if (view.gpuEncodeHistory.isNotEmpty) ('Encode', view.gpuEncodeHistory),
      if (view.gpuVideoProcessingHistory.isNotEmpty)
        ('Video Proc.', view.gpuVideoProcessingHistory),
      if (view.gpuDedicatedUsedHistory.isNotEmpty)
        ('VRAM Ded.', view.gpuDedicatedUsedHistory),
      if (view.gpuSharedUsedHistory.isNotEmpty)
        ('VRAM Shared', view.gpuSharedUsedHistory),
    ];

    return Column(
      children: [
        Expanded(
          flex: 7,
          child: DetailSection(
            title: 'Overview',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            expandChild: true,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _UsageGauge(
                        percent: usagePct,
                        label: usagePct != null
                            ? '${usagePct.toStringAsFixed(0)}% Usage'
                            : 'Usage',
                        compact: true,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: HealthSpecSection(
                          compact: true,
                          rows: [
                            HealthSpecRow(
                              label: 'GPU Name',
                              value: orDash(i?.gpuModel),
                            ),
                            HealthSpecRow(
                              label: 'Vendor',
                              value: orDash(i?.gpuVendor),
                            ),
                            HealthSpecRow(
                              label: 'Driver Version',
                              value: orDash(i?.gpuDriverVersion),
                            ),
                            HealthSpecRow(
                              label: 'Driver Date',
                              value: orDash(i?.gpuDriverDate),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  HealthSpecSection(
                    title: 'Utilization',
                    compact: true,
                    rows: [
                      HealthSpecRow(
                        label: 'Overall',
                        value: formatPercentOrDash(
                          s?.hasGpuPercent ?? false,
                          s?.gpuPercent ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: '3D',
                        value: formatPercentOrNotSupported(
                          s?.hasGpuUtil3d ?? false,
                          s?.gpuUtil3d ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Compute',
                        value: formatPercentOrNotSupported(
                          s?.hasGpuUtilCompute ?? false,
                          s?.gpuUtilCompute ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Copy',
                        value: formatPercentOrNotSupported(
                          s?.hasGpuUtilCopy ?? false,
                          s?.gpuUtilCopy ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Video Decode',
                        value: formatPercentOrNotSupported(
                          s?.hasGpuUtilVideoDecode ?? false,
                          s?.gpuUtilVideoDecode ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Video Encode',
                        value: formatPercentOrNotSupported(
                          s?.hasGpuUtilVideoEncode ?? false,
                          s?.gpuUtilVideoEncode ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Video Processing',
                        value: formatPercentOrNotSupported(
                          s?.hasGpuUtilVideoProcessing ?? false,
                          s?.gpuUtilVideoProcessing ?? 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  HealthSpecSection(
                    title: 'Memory',
                    compact: true,
                    rows: [
                      HealthSpecRow(
                        label: 'Dedicated VRAM',
                        value: dedicatedCapacity > 0
                            ? formatBytesBinary(
                                dedicatedCapacity,
                                fractionDigits: 0,
                              )
                            : kUnavailableDash,
                      ),
                      HealthSpecRow(
                        label: 'Shared Memory',
                        value: sharedCapacity > 0
                            ? formatBytesBinary(
                                sharedCapacity,
                                fractionDigits: 0,
                              )
                            : kUnavailableDash,
                      ),
                      HealthSpecRow(
                        label: 'Total graphics memory',
                        value: totalCapacity > 0
                            ? formatBytesBinary(
                                totalCapacity,
                                fractionDigits: 0,
                              )
                            : kUnavailableDash,
                      ),
                      HealthSpecRow(
                        label: 'Dedicated Used',
                        value: formatBytesOrDash(
                          hasDedicatedUsed,
                          dedicatedUsedBytes,
                        ),
                        description: hasDedicatedUsed
                            ? _vramUsagePercent(
                                dedicatedUsedBytes,
                                dedicatedCapacity,
                              )
                            : null,
                      ),
                      HealthSpecRow(
                        label: 'Shared Used',
                        value: formatBytesOrDash(
                          hasSharedUsed,
                          sharedUsedBytes,
                        ),
                        description: hasSharedUsed
                            ? _vramUsagePercent(
                                sharedUsedBytes,
                                sharedCapacity,
                              )
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  HealthSpecSection(
                    title: 'Clocks & Sensors',
                    compact: true,
                    rows: [
                      HealthSpecRow(
                        label: 'Core Clock',
                        value: formatMhzOrNotSupported(
                          s?.hasGpuClockMhz ?? false,
                          s?.gpuClockMhz ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Memory Clock',
                        value: formatMhzOrNotSupported(
                          s?.hasGpuMemoryClockMhz ?? false,
                          s?.gpuMemoryClockMhz ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Fan Speed',
                        value: formatRpm(
                          s?.hasGpuFanRpm ?? false,
                          s?.gpuFanRpm ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Power',
                        value: formatPercentOrNotSupported(
                          s?.hasGpuPowerPercent ?? false,
                          s?.gpuPowerPercent ?? 0,
                        ),
                      ),
                      const HealthSpecRow(
                        label: 'Power Usage (W)',
                        value: kNotSupported,
                      ),
                      HealthSpecRow(
                        label: 'Temperature',
                        value: formatTempC(
                          s?.hasGpuTempC ?? false,
                          s?.gpuTempC ?? 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  HealthSpecSection(
                    title: 'Adapter',
                    compact: true,
                    rows: [
                      HealthSpecRow(
                        label: 'DirectX',
                        value: orDash(i?.gpuDirectxVersion),
                      ),
                      HealthSpecRow(
                        label: 'WDDM',
                        value: orDash(i?.gpuWddmVersion),
                      ),
                      HealthSpecRow(
                        label: 'Hardware Scheduling',
                        value: i == null
                            ? kUnavailableDash
                            : formatBoolOrDash(
                                i.hasGpuHardwareScheduling,
                                i.gpuHardwareScheduling,
                                yes: 'Enabled',
                                no: 'Disabled',
                              ),
                      ),
                      HealthSpecRow(
                        label: 'PCIe Speed',
                        value: orDash(i?.gpuPcieLinkSpeed),
                      ),
                      HealthSpecRow(
                        label: 'PCIe Width',
                        value: orDash(i?.gpuPcieLinkWidth),
                      ),
                      HealthSpecRow(
                        label: 'PCI Location',
                        value: orDash(i?.gpuPciLocation),
                      ),
                      HealthSpecRow(
                        label: 'Adapter LUID',
                        value: i != null && i.hasGpuLuid
                            ? _formatGpuLuid(i.gpuLuidHigh, i.gpuLuidLow)
                            : kUnavailableDash,
                      ),
                      HealthSpecRow(
                        label: 'Resizable BAR',
                        value: formatBoolOrNotSupported(
                          i?.hasGpuResizableBar ?? false,
                          i?.gpuResizableBar ?? false,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 6,
          child: DetailSection(
            title: store == null
                ? 'Processes'
                : 'Processes (${store.totalCount})',
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            expandChild: true,
            child: store == null
                ? _ProcessList(
                    processes: s?.topGpu ?? const [],
                    kind: HealthPanelKind.gpu,
                    compact: true,
                  )
                : ProcessInventoryList(
                    store: store,
                    compact: true,
                    groupSort: ProcessGroupSort.gpuDescending,
                    metrics: ProcessListMetrics.gpu,
                  ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 4,
          child: DetailSection(
            title: engineHistories.isNotEmpty
                ? 'GPU History (By Engine)'
                : 'GPU History',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            expandChild: true,
            child: engineHistories.isNotEmpty
                ? _CoreHistoryGrid(
                    histories: [
                      for (final e in engineHistories) e.$2,
                    ],
                    labels: [
                      for (final e in engineHistories) e.$1,
                    ],
                    compact: true,
                  )
                : _HistorySparkline(
                    values: view.gpuHistory,
                    fillHeight: true,
                  ),
          ),
        ),
      ],
    );
  }
}

/// GPU adapter LUID formatted as a hex pair (high:low), matching how
/// Windows tooling (e.g. dxdiag) presents `LUID` values.
String _formatGpuLuid(int high, int low) {
  String hex(int v) =>
      (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase();
  return '${hex(high)}:${hex(low)}';
}

String? _vramUsagePercent(int usedBytes, int capacityBytes) {
  if (capacityBytes <= 0) return null;
  final pct = usedBytes * 100.0 / capacityBytes;
  return '${pct.toStringAsFixed(0)}% of capacity';
}

class _DiskPanelBody extends StatelessWidget {
  const _DiskPanelBody({required this.view});
  final HealthViewState view;

  @override
  Widget build(BuildContext context) {
    final s = view.sample;
    final i = view.info;
    final volumes = s?.volumes ?? const <HealthVolume>[];
    final disks = s?.disks ?? const <HealthPhysicalDisk>[];
    final total = s?.diskTotalBytes ?? i?.primaryStorageBytes ?? 0;
    final used = s?.diskUsedBytes ?? 0;
    final free = total > used ? total - used : 0;
    final usagePct = total > 0 ? used * 100.0 / total : null;
    final capacity = total > 0
        ? formatBytesBinary(total, fractionDigits: 0)
        : kUnavailableDash;
    final freeLabel =
        total > 0 ? formatBytesBinary(free) : kUnavailableDash;
    final read = s?.hasDiskReadBps == true
        ? formatDiskRate(s!.diskReadBps)
        : kNotSupported;
    final write = s?.hasDiskWriteBps == true
        ? formatDiskRate(s!.diskWriteBps)
        : kNotSupported;

    final volumeSpec = <(String, String)>[
      for (final v in volumes)
        if (v.hasCapacity && v.totalBytes > 0)
          (
            _diskPanelVolumeTitle(v),
            '${formatBytesBinary(v.usedBytes)} / ${formatBytesBinary(v.totalBytes, fractionDigits: 0)}',
          )
        else
          (_diskPanelVolumeTitle(v), _diskPanelVolumeUnavailable(v)),
    ];
    final diskSpec = <(String, String)>[
      for (final d in disks)
        (
          d.name.trim().isEmpty ? d.id : d.name,
          [
            if (d.hasReadBps) 'R ${formatDiskRate(d.readBps)}',
            if (d.hasWriteBps) 'W ${formatDiskRate(d.writeBps)}',
          ].join(' · ').ifEmpty(kUnavailableDash),
        ),
    ];

    final driveInfoRows = [
      HealthSpecRow(label: 'Interface', value: orDash(i?.diskInterface)),
      HealthSpecRow(label: 'Bus', value: orDash(i?.diskBus)),
      HealthSpecRow(label: 'Model', value: orDash(i?.diskModel)),
      HealthSpecRow(label: 'Serial Number', value: orDash(i?.diskSerial)),
      HealthSpecRow(label: 'Firmware', value: orDash(i?.diskFirmware)),
      HealthSpecRow(
        label: 'Partition Style',
        value: orDash(i?.diskPartitionStyle),
      ),
      HealthSpecRow(
        label: 'Sector Size',
        value: i == null
            ? kUnavailableDash
            : (i.hasDiskSectorSize
                ? formatBytesBinary(i.diskSectorSize, fractionDigits: 0)
                : kUnavailableDash),
      ),
      HealthSpecRow(
        label: 'Rotation',
        value: i == null
            ? kUnavailableDash
            : formatRotationRate(i.hasDiskRotationRate, i.diskRotationRate),
      ),
      HealthSpecRow(
        label: 'TRIM',
        value: i == null
            ? kUnavailableDash
            : formatSupportOrDash(i.hasDiskTrim, i.diskTrimSupported),
      ),
    ];

    return Column(
      children: [
        Expanded(
          flex: 4,
          child: DetailSection(
            title: 'Overview',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                _UsageGauge(
                  percent: usagePct,
                  label: usagePct != null
                      ? '${usagePct.toStringAsFixed(0)}% Used'
                      : 'Usage',
                  compact: true,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _SpecList(
                    compact: true,
                    rows: [
                      ('Primary', capacity),
                      ('Free', freeLabel),
                      ('Read (total)', read),
                      ('Write (total)', write),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 4,
          child: DetailSection(
            title: 'Drive',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            expandChild: true,
            child: SingleChildScrollView(
              child: HealthSpecSection(compact: true, rows: driveInfoRows),
            ),
          ),
        ),
        if (volumeSpec.isNotEmpty) ...[
          const Divider(height: 1, color: PulseTokens.strokeSubtle),
          Expanded(
            flex: 3,
            child: DetailSection(
              title: 'Volumes',
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              expandChild: true,
              child: _SpecList(compact: true, rows: volumeSpec),
            ),
          ),
        ],
        if (diskSpec.isNotEmpty) ...[
          const Divider(height: 1, color: PulseTokens.strokeSubtle),
          Expanded(
            flex: 3,
            child: DetailSection(
              title: 'Physical disks',
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              expandChild: true,
              child: _SpecList(compact: true, rows: diskSpec),
            ),
          ),
        ],
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 4,
          child: DetailSection(
            title: 'Top Processes',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            expandChild: true,
            child: _ProcessList(
              processes: s?.topDisk ?? const [],
              kind: HealthPanelKind.disk,
              compact: true,
            ),
          ),
        ),
      ],
    );
  }
}

String _diskPanelVolumeTitle(HealthVolume v) {
  final id = v.id.trim().isEmpty ? v.mountPoint.trim() : v.id.trim();
  final label = v.label.trim();
  return label.isEmpty ? id : '$id · $label';
}

String _diskPanelVolumeUnavailable(HealthVolume v) {
  return switch (v.kind) {
    HealthDriveKind.remote => 'Network',
    HealthDriveKind.removable || HealthDriveKind.cdrom => 'No media',
    _ => kUnavailableDash,
  };
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}

class _NetworkPanelBody extends StatelessWidget {
  const _NetworkPanelBody({required this.view});
  final HealthViewState view;

  @override
  Widget build(BuildContext context) {
    final s = view.sample;
    final i = view.info;
    final adapter = i?.activeNetworkAdapter.trim() ?? '';
    final downloadValue = s?.hasNetDownloadBps == true
        ? formatThroughputBps(s!.netDownloadBps)
        : kUnavailableDash;
    final uploadValue = s?.hasNetUploadBps == true
        ? formatThroughputBps(s!.netUploadBps)
        : kUnavailableDash;

    final hasWifi = (s?.netSsid.trim().isNotEmpty ?? false) ||
        (s?.netWifiChannel.trim().isNotEmpty ?? false) ||
        (s?.hasNetSignalPercent ?? false);

    return Column(
      children: [
        Expanded(
          flex: 5,
          child: DetailSection(
            title: 'Live',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            expandChild: true,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NetworkHeroValues(
                    download: downloadValue,
                    upload: uploadValue,
                  ),
                  const SizedBox(height: 14),
                  HealthSpecSection(
                    compact: true,
                    rows: [
                      HealthSpecRow(
                        label: 'Peak Download',
                        value: s?.hasNetPeakDownloadBps == true
                            ? formatThroughputBps(s!.netPeakDownloadBps)
                            : kUnavailableDash,
                      ),
                      HealthSpecRow(
                        label: 'Peak Upload',
                        value: s?.hasNetPeakUploadBps == true
                            ? formatThroughputBps(s!.netPeakUploadBps)
                            : kUnavailableDash,
                      ),
                      HealthSpecRow(
                        label: 'Average Download',
                        value: s?.hasNetAvgDownloadBps == true
                            ? formatThroughputBps(s!.netAvgDownloadBps)
                            : kUnavailableDash,
                      ),
                      HealthSpecRow(
                        label: 'Average Upload',
                        value: s?.hasNetAvgUploadBps == true
                            ? formatThroughputBps(s!.netAvgUploadBps)
                            : kUnavailableDash,
                      ),
                      HealthSpecRow(
                        label: 'Utilization',
                        value: formatPercentOrDash(
                          s?.hasNetUtilizationPercent ?? false,
                          s?.netUtilizationPercent ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Connection Time',
                        value: formatConnectionDuration(
                          s?.hasNetConnectionMs ?? false,
                          s?.netConnectionMs ?? 0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 8,
          child: DetailSection(
            title: 'Overview',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            expandChild: true,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HealthSpecSection(
                    title: 'Adapter',
                    compact: true,
                    rows: [
                      HealthSpecRow(
                        label: 'Adapter',
                        value: adapter.isEmpty ? kUnavailableDash : adapter,
                      ),
                      HealthSpecRow(
                        label: 'Manufacturer',
                        value: orDash(i?.netManufacturer),
                      ),
                      HealthSpecRow(
                        label: 'Description',
                        value: orDash(i?.netDescription),
                      ),
                      HealthSpecRow(
                        label: 'MAC Address',
                        value: orDash(i?.netMacAddress),
                      ),
                      HealthSpecRow(
                        label: 'Driver Version',
                        value: orDash(i?.netDriverVersion),
                      ),
                      HealthSpecRow(
                        label: 'Driver Date',
                        value: orDash(i?.netDriverDate),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  HealthSpecSection(
                    title: 'Connection',
                    compact: true,
                    rows: [
                      HealthSpecRow(
                        label: 'Link Speed',
                        value: i == null
                            ? kUnavailableDash
                            : formatLinkSpeedBps(
                                i.hasNetLinkSpeedBps,
                                i.netLinkSpeedBps,
                              ),
                      ),
                      HealthSpecRow(
                        label: 'Connection Type',
                        value: orDash(i?.netConnectionType),
                      ),
                      HealthSpecRow(
                        label: 'Duplex',
                        value: orDash(i?.netDuplex),
                      ),
                      HealthSpecRow(
                        label: 'MTU',
                        value: i == null
                            ? kUnavailableDash
                            : formatCount(i.hasNetMtu, i.netMtu),
                      ),
                      HealthSpecRow(
                        label: 'Interface Index',
                        value: i == null
                            ? kUnavailableDash
                            : formatCount(i.hasNetIfIndex, i.netIfIndex),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  HealthSpecSection(
                    title: 'Addressing',
                    compact: true,
                    rows: [
                      HealthSpecRow(
                        label: 'IPv4',
                        value: orDash(s?.ipv4),
                      ),
                      HealthSpecRow(
                        label: 'IPv6',
                        value: orDash(s?.ipv6),
                      ),
                      HealthSpecRow(
                        label: 'Gateway',
                        value: orDash(s?.gateway),
                      ),
                      HealthSpecRow(
                        label: 'DNS',
                        value: orDash(s?.dns),
                      ),
                      HealthSpecRow(
                        label: 'DHCP',
                        value: i == null
                            ? kUnavailableDash
                            : formatBoolOrDash(
                                i.hasNetDhcp,
                                i.netDhcpEnabled,
                                yes: 'Enabled',
                                no: 'Disabled',
                              ),
                      ),
                      HealthSpecRow(
                        label: 'DHCP Server',
                        value: orDash(i?.netDhcpServer),
                      ),
                      HealthSpecRow(
                        label: 'Lease Obtained',
                        value: i == null
                            ? kUnavailableDash
                            : formatUnixMsDateTime(
                                i.hasNetLeaseObtained,
                                i.netLeaseObtainedUnixMs,
                              ),
                      ),
                      HealthSpecRow(
                        label: 'Lease Expires',
                        value: i == null
                            ? kUnavailableDash
                            : formatUnixMsDateTime(
                                i.hasNetLeaseExpires,
                                i.netLeaseExpiresUnixMs,
                              ),
                      ),
                    ],
                  ),
                  if (hasWifi) ...[
                    const SizedBox(height: 14),
                    HealthSpecSection(
                      title: 'Wireless',
                      compact: true,
                      rows: [
                        HealthSpecRow(
                          label: 'SSID',
                          value: orDash(s?.netSsid),
                        ),
                        HealthSpecRow(
                          label: 'Signal',
                          value: s?.hasNetSignalPercent == true
                              ? '${s!.netSignalPercent.toStringAsFixed(0)}%'
                              : kUnavailableDash,
                        ),
                        HealthSpecRow(
                          label: 'Channel',
                          value: orDash(s?.netWifiChannel),
                        ),
                        HealthSpecRow(
                          label: 'Frequency',
                          value: orDash(s?.netWifiFrequency),
                        ),
                        HealthSpecRow(
                          label: 'Security',
                          value: orDash(s?.netWifiSecurity),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  HealthSpecSection(
                    title: 'Traffic',
                    compact: true,
                    rows: [
                      HealthSpecRow(
                        label: 'Bytes Sent',
                        value: formatBytesOrDash(
                          s?.hasNetBytesSent ?? false,
                          s?.netBytesSent ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Bytes Received',
                        value: formatBytesOrDash(
                          s?.hasNetBytesReceived ?? false,
                          s?.netBytesReceived ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Packets Sent',
                        value: formatCount(
                          s?.hasNetPacketsSent ?? false,
                          s?.netPacketsSent ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Packets Received',
                        value: formatCount(
                          s?.hasNetPacketsReceived ?? false,
                          s?.netPacketsReceived ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Errors',
                        value: formatCount(
                          s?.hasNetErrors ?? false,
                          s?.netErrors ?? 0,
                        ),
                      ),
                      HealthSpecRow(
                        label: 'Drops',
                        value: formatCount(
                          s?.hasNetDrops ?? false,
                          s?.netDrops ?? 0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 3,
          child: DetailSection(
            title: 'Processes',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            expandChild: true,
            child: const _NetworkProcessesPlaceholder(),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 3,
          child: DetailSection(
            title: 'Activity',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            expandChild: true,
            child: Row(
              children: [
                Expanded(
                  child: _MiniCoreSparkline(
                    label: 'Download',
                    values: view.downloadHistory,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniCoreSparkline(
                    label: 'Upload',
                    values: view.uploadHistory,
                    compact: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Per-process network attribution requires the ETW milestone; the topology
/// exists in the wire format but no collector populates it yet.
class _NetworkProcessesPlaceholder extends StatelessWidget {
  const _NetworkProcessesPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Per-process network not available yet.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: PulseTokens.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Requires ETW milestone',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: PulseTokens.textDisabled,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsHeader extends StatelessWidget {
  const _DetailsHeader({
    required this.title,
    required this.onClose,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: PulseTokens.textTertiary,
                          height: 1.35,
                        ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(LucideIcons.x, size: 17),
          ),
        ],
      ),
    );
  }
}

class _UsageGauge extends StatelessWidget {
  const _UsageGauge({
    required this.percent,
    required this.label,
    this.compact = false,
  });

  final double? percent;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pct = percent?.clamp(0.0, 100.0);
    final size = compact ? 96.0 : 148.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _UsageDonutPainter(
              percent: pct ?? 0,
              hasValue: pct != null,
              accent: PulseTokens.accent,
              track: PulseTokens.strokeSubtle,
              strokeWidth: compact ? 8 : 11,
            ),
            child: Center(
              child: Text(
                pct != null ? '${pct.toStringAsFixed(0)}%' : kUnavailableDash,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: compact ? 20 : 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.6,
                      color: PulseTokens.textPrimary,
                    ),
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 6 : 12),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: PulseTokens.textSecondary,
                fontWeight: FontWeight.w500,
                fontSize: compact ? 11.5 : null,
              ),
        ),
      ],
    );
  }
}

class _UsageDonutPainter extends CustomPainter {
  _UsageDonutPainter({
    required this.percent,
    required this.hasValue,
    required this.accent,
    required this.track,
    this.strokeWidth = 11.0,
  });

  final double percent;
  final bool hasValue;
  final Color accent;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    if (!hasValue || percent <= 0) return;

    final sweep = (percent / 100.0).clamp(0.0, 1.0) * math.pi * 2;
    final fillPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Start at top (-pi/2).
    canvas.drawArc(rect, -math.pi / 2, sweep, false, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _UsageDonutPainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.hasValue != hasValue ||
        oldDelegate.accent != accent ||
        oldDelegate.track != track ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _NetworkHeroValues extends StatelessWidget {
  const _NetworkHeroValues({
    required this.download,
    required this.upload,
  });

  final String download;
  final String upload;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ThroughputHero(
            label: 'Download',
            value: download,
            icon: LucideIcons.download,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ThroughputHero(
            label: 'Upload',
            value: upload,
            icon: LucideIcons.upload,
          ),
        ),
      ],
    );
  }
}

class _ThroughputHero extends StatelessWidget {
  const _ThroughputHero({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: PulseTokens.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        border: Border.all(color: PulseTokens.strokeSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: PulseTokens.accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: PulseTokens.textTertiary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: PulseTokens.textPrimary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
          ),
        ],
      ),
    );
  }
}

class _SpecList extends StatelessWidget {
  const _SpecList({required this.rows, this.compact = false});

  final List<(String, String)> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment:
          compact ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 5 : 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  rows[i].$1,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: PulseTokens.textTertiary,
                        fontSize: compact ? 11.5 : null,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  rows[i].$2,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: rows[i].$2 == kNotSupported ||
                                rows[i].$2 == kUnavailableDash
                            ? PulseTokens.textDisabled
                            : PulseTokens.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: compact ? 11.5 : null,
                      ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ProcessList extends StatelessWidget {
  const _ProcessList({
    required this.processes,
    required this.kind,
    this.compact = false,
  });

  final List<HealthProcessEntry> processes;
  final HealthPanelKind kind;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (processes.isEmpty) {
      return Text(
        kUnavailableDash,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: PulseTokens.textDisabled,
            ),
      );
    }

    final primaryLabel = processMetricColumnLabel(kind);
    final secondaryLabel = processSecondaryColumnLabel(kind);
    final shown = processes.take(5).toList();

    final rows = Column(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 4 : 8),
          if (compact)
            Expanded(
              child: _ProcessRow(
                entry: shown[i],
                kind: kind,
                compact: compact,
              ),
            )
          else
            _ProcessRow(entry: shown[i], kind: kind),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProcessColumnHeader(
          primaryLabel: primaryLabel,
          secondaryLabel: secondaryLabel,
        ),
        SizedBox(height: compact ? 4 : 8),
        if (compact) Expanded(child: rows) else rows,
      ],
    );
  }
}

class _ProcessColumnHeader extends StatelessWidget {
  const _ProcessColumnHeader({
    required this.primaryLabel,
    this.secondaryLabel,
  });

  final String primaryLabel;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: PulseTokens.textDisabled,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        );
    return Row(
      children: [
        Expanded(
          child: Text('Process', style: style),
        ),
        SizedBox(
          width: 72,
          child: Text(
            primaryLabel,
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
        if (secondaryLabel != null)
          SizedBox(
            width: 72,
            child: Text(
              secondaryLabel!,
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
      ],
    );
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({
    required this.entry,
    required this.kind,
    this.compact = false,
  });

  final HealthProcessEntry entry;
  final HealthPanelKind kind;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final name = entry.name.trim().isEmpty ? kUnavailableDash : entry.name;
    final metric = formatProcessPrimaryMetric(entry, kind);
    final secondary = formatProcessSecondaryMetric(entry, kind);
    final showSecondary = processSecondaryColumnLabel(kind) != null;
    final iconSize = compact ? 22.0 : 28.0;

    return Row(
      children: [
        ProcessAppIcon(
          path: entry.path,
          name: name,
          pid: entry.pid,
          size: iconSize,
        ),
        SizedBox(width: compact ? 8 : 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PulseTokens.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: compact ? 12 : null,
                ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: compact ? 56 : 72,
          child: Text(
            metric,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PulseTokens.textSecondary,
                  fontSize: compact ? 12 : null,
                ),
          ),
        ),
        if (showSecondary)
          SizedBox(
            width: compact ? 56 : 72,
            child: Text(
              secondary ?? kUnavailableDash,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: PulseTokens.textTertiary,
                    fontSize: compact ? 12 : null,
                  ),
            ),
          ),
      ],
    );
  }
}

class _CoreHistoryGrid extends StatelessWidget {
  const _CoreHistoryGrid({
    required this.histories,
    this.labels,
    this.compact = false,
  });

  final List<List<double>> histories;

  /// Custom tile labels (e.g. GPU engine names); defaults to "Core N".
  final List<String>? labels;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = histories.length;
        if (count == 0) {
          return const SizedBox.shrink();
        }

        final gap = compact ? 6.0 : 10.0;
        final minTileHeight = compact ? 36.0 : 52.0;
        final maxColumns = compact ? 6 : 4;

        // Grow columns until tiles fit the available height (any core count).
        var columns = count <= 4 ? 2 : 3;
        columns = columns.clamp(1, maxColumns);
        for (var c = columns; c <= maxColumns; c++) {
          final rows = (count / c).ceil();
          final tileH =
              (constraints.maxHeight - gap * (rows - 1).clamp(0, 99)) / rows;
          if (tileH >= minTileHeight || c == maxColumns) {
            columns = c;
            if (tileH >= minTileHeight) break;
          }
        }

        final rows = (count / columns).ceil().clamp(1, 999);
        final availableH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : minTileHeight * rows;
        final rawTileH =
            (availableH - gap * (rows - 1).clamp(0, 999)) / rows;
        final needsScroll = rawTileH < minTileHeight;
        final tileHeight = needsScroll
            ? minTileHeight
            : rawTileH.clamp(minTileHeight, availableH);
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        final grid = Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < count; i++)
              SizedBox(
                width: tileWidth,
                height: tileHeight,
                child: _MiniCoreSparkline(
                  label: labels != null && i < labels!.length
                      ? labels![i]
                      : 'Core ${i + 1}',
                  values: histories[i],
                  compact: compact,
                ),
              ),
          ],
        );

        if (!needsScroll) return grid;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: grid,
        );
      },
    );
  }
}

class _MiniCoreSparkline extends StatelessWidget {
  const _MiniCoreSparkline({
    required this.label,
    required this.values,
    this.compact = false,
  });

  final String label;
  final List<double> values;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 10,
        compact ? 4 : 8,
        compact ? 8 : 10,
        compact ? 4 : 8,
      ),
      decoration: BoxDecoration(
        color: PulseTokens.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
        border: Border.all(color: PulseTokens.strokeSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: PulseTokens.textTertiary,
                  fontSize: compact ? 10 : null,
                  height: 1.1,
                ),
          ),
          SizedBox(height: compact ? 2 : 6),
          Expanded(
            child: values.length < 2
                ? Center(
                    child: Text(
                      kUnavailableDash,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: PulseTokens.textDisabled,
                          ),
                    ),
                  )
                : CustomPaint(
                    painter: HealthSparklinePainter(
                      values: values,
                      color: PulseTokens.accent,
                    ),
                    child: const SizedBox.expand(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistorySparkline extends StatelessWidget {
  const _HistorySparkline({
    required this.values,
    this.fillHeight = false,
  });

  final List<double> values;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return Text(
        kUnavailableDash,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: PulseTokens.textDisabled,
            ),
      );
    }

    if (fillHeight) {
      return CustomPaint(
        painter: HealthSparklinePainter(
          values: values,
          color: PulseTokens.accent,
        ),
        child: const SizedBox.expand(),
      );
    }

    return SizedBox(
      height: 88,
      width: double.infinity,
      child: CustomPaint(
        painter: HealthSparklinePainter(
          values: values,
          color: PulseTokens.accent,
        ),
      ),
    );
  }
}

/// Animated host that expands the health details panel beside the list.
class HealthDetailsHost extends StatelessWidget {
  const HealthDetailsHost({
    super.key,
    required this.expanded,
    required this.width,
    required this.kind,
    required this.view,
    required this.onClose,
    this.processInventory,
  });

  final bool expanded;
  final double width;
  final HealthPanelKind? kind;
  final HealthViewState view;
  final VoidCallback onClose;
  final ProcessInventoryStore? processInventory;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        duration: PulseTokens.motionSlow,
        curve: PulseTokens.motionEmphasized,
        alignment: Alignment.centerRight,
        widthFactor: expanded ? 1 : 0,
        child: SizedBox(
          width: width,
          child: kind == null
              ? const SizedBox.shrink()
              : AnimatedSwitcher(
                  duration: PulseTokens.motionNormal,
                  switchInCurve: PulseTokens.motionCurve,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.04, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(kind),
                    child: HealthDetailsPanel(
                      kind: kind!,
                      view: view,
                      onClose: onClose,
                      processInventory: processInventory,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
