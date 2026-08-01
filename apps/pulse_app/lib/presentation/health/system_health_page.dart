import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../application/connection_controller.dart';
import '../../app/theme/pulse_theme.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../components/pulse_app_bar.dart';
import '../components/pulse_empty_state.dart';
import '../components/pulse_loading.dart';
import '../components/service_lifecycle_controls.dart';
import '../utils/pulse_user_errors.dart';
import 'health_cards.dart';
import 'health_view_models.dart';
import 'widgets/health_details_panel.dart';
import 'widgets/process_inventory/process_inventory_store.dart';

class SystemHealthPage extends StatefulWidget {
  const SystemHealthPage({super.key, required this.title});

  final String title;

  @override
  State<SystemHealthPage> createState() => _SystemHealthPageState();
}

class _SystemHealthPageState extends State<SystemHealthPage> {
  PulseIpcClient? _ipc;
  StreamSubscription<HealthUpdate>? _healthSub;
  IpcConnectionState? _lastState;
  final _view = HealthViewState();
  final _processInventory = ProcessInventoryStore();
  Timer? _appWindowTimer;
  bool _loading = false;
  String? _error;
  bool _monitoring = false;
  HealthPanelKind? _selectedPanel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ipc = context.read<PulseIpcClient>();
    if (!identical(_ipc, ipc)) {
      _ipc?.removeListener(_onIpcChanged);
      _healthSub?.cancel();
      _ipc = ipc;
      _ipc!.addListener(_onIpcChanged);
      _healthSub = _ipc!.healthUpdates.listen(_onHealthSample);
      _onIpcChanged();
    }
  }

  @override
  void dispose() {
    _appWindowTimer?.cancel();
    _healthSub?.cancel();
    _ipc?.removeListener(_onIpcChanged);
    _processInventory.dispose();
    if (_monitoring) {
      unawaited(_ipc?.stopHealthMonitoring());
    }
    super.dispose();
  }

  void _onHealthSample(HealthUpdate update) {
    if (!mounted) return;
    setState(() {
      _view.applySample(update.sample);
      final inv = update.processInventory;
      if (inv != null) {
        _processInventory.applyUpdate(inv);
      }
      _loading = false;
      _error = null;
    });
  }

  void _ensureAppWindowTimer() {
    _appWindowTimer?.cancel();
    _appWindowTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_processInventory.refreshAppWindows());
    });
    unawaited(_processInventory.refreshAppWindows());
  }

  void _onIpcChanged() {
    final state = _ipc!.status.state;
    if (_lastState == state) return;
    final previous = _lastState;
    _lastState = state;
    final becameConnected = state == IpcConnectionState.connected &&
        previous != IpcConnectionState.connected;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (becameConnected) {
        unawaited(_loadHealth());
        _ensureAppWindowTimer();
      } else if (state == IpcConnectionState.disconnected ||
          state == IpcConnectionState.error) {
        _appWindowTimer?.cancel();
        setState(() {
          _view.info = null;
          _view.sample = null;
          _view.cpuHistory.clear();
          _view.memoryHistory.clear();
          _view.gpuHistory.clear();
          _view.diskHistory.clear();
          _view.downloadHistory.clear();
          _view.uploadHistory.clear();
          _view.coreHistories.clear();
          _processInventory.clear();
          _selectedPanel = null;
          _loading = false;
          _error = null;
        });
      }
    });
  }

  Future<void> _loadHealth() async {
    final ipc = _ipc;
    if (ipc == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await ipc.getHealthSnapshot();
      if (!mounted) return;
      setState(() {
        _view.applySnapshot(snapshot);
        _loading = false;
      });
      await ipc.startHealthMonitoring();
      if (!mounted) return;
      _monitoring = true;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = PulseUserErrors.fromObject(e);
      });
    }
  }

  void _selectPanel(HealthPanelKind kind) {
    setState(() => _selectedPanel = kind);
  }

  void _clearPanel() {
    setState(() => _selectedPanel = null);
  }

  @override
  Widget build(BuildContext context) {
    final connectionLabel = context.select<ConnectionController, String>(
      (c) => c.statusLabel,
    );
    final state = context.select<PulseIpcClient, IpcConnectionState>(
      (c) => c.status.state,
    );
    final offline = state == IpcConnectionState.disconnected ||
        state == IpcConnectionState.error;
    final connecting = state == IpcConnectionState.connecting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseAppBar(
          title: widget.title,
          connectionState: state,
          connectionLabel: connectionLabel,
        ),
        Expanded(
          child: offline
              ? const ServiceOfflineRecovery(
                  titleFallback: 'Ready when Windows is',
                )
              : connecting || (_loading && _view.sample == null)
                  ? const _HealthConnectingState()
                  : _error != null && _view.sample == null
                      ? PulseEmptyState(
                          useBrandIllustration: true,
                          title: 'Could not load system health',
                          message: _error!,
                          actionLabel: 'Retry',
                          onAction: _loadHealth,
                        )
                      : _SystemHealthBody(
                          view: _view,
                          selectedPanel: _selectedPanel,
                          onSelect: _selectPanel,
                          onClear: _clearPanel,
                          processInventory: _processInventory,
                        ),
        ),
      ],
    );
  }
}

HealthPanelKind? _panelKindForMetricId(String id) {
  return switch (id) {
    'cpu' || 'perf-cpu' => HealthPanelKind.cpu,
    'memory' || 'perf-memory' => HealthPanelKind.memory,
    'gpu' || 'perf-gpu' => HealthPanelKind.gpu,
    'perf-disk' => HealthPanelKind.disk,
    'download' || 'upload' => HealthPanelKind.network,
    _ => null,
  };
}

class _HealthConnectingState extends StatelessWidget {
  const _HealthConnectingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PulseTokens.spaceXl,
            vertical: PulseTokens.space2xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PulseInlineSpinner(size: 28),
              const SizedBox(height: PulseTokens.spaceLg),
              Text(
                'Connecting…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: 22,
                      letterSpacing: -0.3,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Waiting for PulseService before live metrics appear.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: PulseTokens.textSecondary,
                      height: 1.6,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-viewport dashboard — no page scroll (mockup parity).
class _SystemHealthBody extends StatelessWidget {
  const _SystemHealthBody({
    required this.view,
    required this.selectedPanel,
    required this.onSelect,
    required this.onClear,
    required this.processInventory,
  });

  final HealthViewState view;
  final HealthPanelKind? selectedPanel;
  final ValueChanged<HealthPanelKind> onSelect;
  final VoidCallback onClear;
  final ProcessInventoryStore processInventory;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final showSideDetail = wide && selectedPanel != null;

        final dashboard = Padding(
          padding: const EdgeInsets.fromLTRB(
            PulseTokens.pagePadX,
            PulseTokens.pagePadTop,
            PulseTokens.pagePadX,
            PulseTokens.pagePadBottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HealthSystemStatusCard(
                summary: view.systemStatus,
                uptime: formatUptime(view.sample?.uptimeMs ?? 0),
                healthScore: '${view.healthScore}',
                lastUpdated: view.lastUpdatedLabel,
                compact: true,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 112,
                child: Row(
                  children: [
                    for (var i = 0; i < view.heroMetrics.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: HealthHeroCard(
                          metric: view.heroMetrics[i],
                          compact: true,
                          selected: selectedPanel != null &&
                              _panelKindForMetricId(view.heroMetrics[i].id) ==
                                  selectedPanel,
                          onTap: () {
                            final kind =
                                _panelKindForMetricId(view.heroMetrics[i].id);
                            if (kind != null) onSelect(kind);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _SystemInfoStrip(items: view.systemSummary),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'PERFORMANCE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 0.8,
                          color: PulseTokens.textDisabled,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(Last 60 seconds)',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: PulseTokens.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    for (var i = 0;
                        i < view.performanceMetrics.length;
                        i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: HealthSparklineTile(
                          metric: view.performanceMetrics[i],
                          fillHeight: true,
                          selected: selectedPanel != null &&
                              _panelKindForMetricId(
                                      view.performanceMetrics[i].id) ==
                                  selectedPanel,
                          onTap: () {
                            final kind = _panelKindForMetricId(
                                view.performanceMetrics[i].id);
                            if (kind != null) onSelect(kind);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 4,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: HealthGroupedCard(
                        title: 'Hardware',
                        icon: LucideIcons.thermometer,
                        rows: view.hardwareRows,
                        compact: true,
                        scrollBody: true,
                        selected: selectedPanel == HealthPanelKind.hardware,
                        onTap: () => onSelect(HealthPanelKind.hardware),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: HealthGroupedCard(
                        title: 'Storage',
                        icon: LucideIcons.hardDrive,
                        rows: view.storageRows,
                        compact: true,
                        scrollBody: true,
                        selected: selectedPanel == HealthPanelKind.disk,
                        onTap: () => onSelect(HealthPanelKind.disk),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: HealthGroupedCard(
                        title: 'Network',
                        icon: LucideIcons.wifi,
                        rows: view.networkRows,
                        compact: true,
                        selected: selectedPanel == HealthPanelKind.network,
                        onTap: () => onSelect(HealthPanelKind.network),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        return Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: dashboard),
                HealthDetailsHost(
                  expanded: showSideDetail,
                  width: 420,
                  kind: selectedPanel,
                  view: view,
                  onClose: onClear,
                  processInventory: processInventory,
                ),
              ],
            ),
            if (selectedPanel != null && !wide)
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onClear,
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.38),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: constraints.maxWidth.clamp(300, 400),
                      child: HealthDetailsPanel(
                        kind: selectedPanel!,
                        view: view,
                        onClose: onClear,
                        processInventory: processInventory,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Mockup-style single horizontal system identity strip.
class _SystemInfoStrip extends StatelessWidget {
  const _SystemInfoStrip({required this.items});

  final List<HealthInfoItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: PulseTokens.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        border: Border.all(color: PulseTokens.stroke.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) ...[
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: PulseTokens.strokeSubtle,
              ),
            ],
            Expanded(
              child: Row(
                children: [
                  Icon(
                    items[i].icon,
                    size: 12,
                    color: PulseTokens.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${items[i].label}  ',
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: PulseTokens.textDisabled,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 10.5,
                                    ),
                          ),
                          TextSpan(
                            text: items[i].value,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: PulseTokens.textSecondary,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 11.5,
                                    ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
