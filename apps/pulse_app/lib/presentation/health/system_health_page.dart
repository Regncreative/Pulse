import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../application/connection_controller.dart';
import '../../application/health_navigation.dart';
import '../../application/settings_controller.dart';
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
  HealthNavigation? _healthNav;
  StreamSubscription<HealthUpdate>? _healthSub;
  IpcConnectionState? _lastState;
  final _view = HealthViewState();
  final _processInventory = ProcessInventoryStore();
  Timer? _appWindowTimer;
  bool _loading = false;
  String? _error;
  bool _monitoring = false;
  HealthPanelKind? _selectedPanel;
  bool _customizeMode = false;

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

    final healthNav = context.read<HealthNavigation>();
    if (!identical(_healthNav, healthNav)) {
      _healthNav?.removeListener(_onHealthNavigation);
      _healthNav = healthNav;
      _healthNav!.addListener(_onHealthNavigation);
      _onHealthNavigation();
    }
  }

  @override
  void dispose() {
    _appWindowTimer?.cancel();
    _healthSub?.cancel();
    _ipc?.removeListener(_onIpcChanged);
    _healthNav?.removeListener(_onHealthNavigation);
    _processInventory.dispose();
    if (_monitoring) {
      unawaited(_ipc?.stopHealthMonitoring());
    }
    super.dispose();
  }

  void _onHealthNavigation() {
    if (_healthNav?.requestOverview == true) {
      _healthNav?.consumeOverview();
      if (!mounted) return;
      setState(() {
        _customizeMode = false;
        _selectedPanel = null;
      });
      return;
    }
    final pending = _healthNav?.pendingPanel;
    if (pending == null) return;
    _healthNav?.consume();
    if (!mounted) return;
    setState(() {
      _customizeMode = false;
      _selectedPanel = pending;
    });
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
    Theme.of(context);
    final connectionLabel = context.select<ConnectionController, String>(
      (c) => c.statusLabel,
    );
    final state = context.select<PulseIpcClient, IpcConnectionState>(
      (c) => c.status.state,
    );
    final offline = state == IpcConnectionState.disconnected ||
        state == IpcConnectionState.error;
    final connecting = state == IpcConnectionState.connecting;
    final showDashboard = !offline &&
        !connecting &&
        !(_loading && _view.sample == null) &&
        !(_error != null && _view.sample == null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseAppBar(
          title: widget.title,
          connectionState: state,
          connectionLabel: connectionLabel,
          actions: [
            if (showDashboard)
              IconButton(
                tooltip: _customizeMode
                    ? 'Done customizing'
                    : 'Customize dashboard',
                onPressed: () {
                  setState(() => _customizeMode = !_customizeMode);
                },
                icon: Icon(
                  _customizeMode
                      ? LucideIcons.check
                      : LucideIcons.layoutDashboard,
                  size: 18,
                  color: _customizeMode
                      ? PulseTokens.accent
                      : PulseTokens.textSecondary,
                ),
              ),
          ],
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
                          customizeMode: _customizeMode,
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

String _dashboardWidgetLabel(String id) => switch (id) {
      'status' => 'System status',
      'heroes' => 'Hero metrics',
      'system' => 'System info',
      'performance' => 'Performance',
      'bottom' => 'Hardware, storage & network',
      _ => id,
    };

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
    required this.customizeMode,
  });

  final HealthViewState view;
  final HealthPanelKind? selectedPanel;
  final ValueChanged<HealthPanelKind> onSelect;
  final VoidCallback onClear;
  final ProcessInventoryStore processInventory;
  final bool customizeMode;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final compact = settings.dashboardDensity == 'compact';
    final gap = compact ? 8.0 : 12.0;
    final padX = compact ? PulseTokens.pagePadX - 4 : PulseTokens.pagePadX;
    final padTop = compact ? PulseTokens.pagePadTop - 4 : PulseTokens.pagePadTop;
    final padBottom =
        compact ? PulseTokens.pagePadBottom - 4 : PulseTokens.pagePadBottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final showSideDetail = wide && selectedPanel != null && !customizeMode;

        final visibleIds = settings.dashboardWidgetOrder
            .where(settings.isDashboardWidgetVisible)
            .toList(growable: false);

        final dashboard = customizeMode
            ? _DashboardCustomizePanel(settings: settings)
            : Padding(
                padding: EdgeInsets.fromLTRB(padX, padTop, padX, padBottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < visibleIds.length; i++) ...[
                      if (i > 0) SizedBox(height: gap),
                      _buildDashboardSection(
                        context,
                        visibleIds[i],
                        compact: compact,
                      ),
                    ],
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
            if (selectedPanel != null && !wide && !customizeMode)
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

  Widget _buildDashboardSection(
    BuildContext context,
    String id, {
    required bool compact,
  }) {
    switch (id) {
      case 'status':
        return HealthSystemStatusCard(
          summary: view.systemStatus,
          uptime: formatUptime(view.sample?.uptimeMs ?? 0),
          healthScore: '${view.healthScore}',
          lastUpdated: view.lastUpdatedLabel,
          compact: true,
        );
      case 'heroes':
        return SizedBox(
          height: compact ? 104 : 116,
          child: Row(
            children: [
              for (var i = 0; i < view.heroMetrics.length; i++) ...[
                if (i > 0) SizedBox(width: compact ? 8 : 10),
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
        );
      case 'system':
        return _SystemInfoStrip(items: view.systemSummary);
      case 'performance':
        return Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              SizedBox(height: compact ? 6 : 8),
              Expanded(
                child: Row(
                  children: [
                    for (var i = 0;
                        i < view.performanceMetrics.length;
                        i++) ...[
                      if (i > 0) SizedBox(width: compact ? 8 : 10),
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
            ],
          ),
        );
      case 'bottom':
        return Expanded(
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
              SizedBox(width: compact ? 8 : 10),
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
              SizedBox(width: compact ? 8 : 10),
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
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _DashboardCustomizePanel extends StatelessWidget {
  const _DashboardCustomizePanel({required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final order = settings.dashboardWidgetOrder;
    final compact = settings.dashboardDensity == 'compact';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PulseTokens.pagePadX,
        PulseTokens.pagePadTop,
        PulseTokens.pagePadX,
        PulseTokens.pagePadBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customize dashboard',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Drag to reorder. Toggle visibility. Density affects spacing.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: PulseTokens.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'compact',
                    label: Text('Compact'),
                    icon: Icon(LucideIcons.rows3, size: 14),
                  ),
                  ButtonSegment(
                    value: 'comfortable',
                    label: Text('Comfortable'),
                    icon: Icon(LucideIcons.rows4, size: 14),
                  ),
                ],
                selected: {compact ? 'compact' : 'comfortable'},
                onSelectionChanged: (s) {
                  settings.setDashboardDensity(s.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(
                    Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: order.length,
              onReorderItem: settings.reorderDashboardWidget,
              proxyDecorator: (child, index, animation) {
                return Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
                  color: PulseTokens.surfaceElevated,
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final id = order[index];
                final visible = settings.isDashboardWidgetVisible(id);
                return Padding(
                  key: ValueKey(id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: PulseTokens.surface.withValues(alpha: 0.85),
                      borderRadius:
                          BorderRadius.circular(PulseTokens.radiusMd),
                      border: Border.all(
                        color: PulseTokens.stroke.withValues(alpha: 0.55),
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          LucideIcons.gripVertical,
                          size: 18,
                          color: PulseTokens.textTertiary,
                        ),
                      ),
                      title: Text(
                        _dashboardWidgetLabel(id),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: visible
                                  ? PulseTokens.textPrimary
                                  : PulseTokens.textDisabled,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      trailing: IconButton(
                        tooltip: visible ? 'Hide section' : 'Show section',
                        onPressed: () {
                          settings.toggleDashboardWidgetVisibility(id);
                        },
                        icon: Icon(
                          visible ? LucideIcons.eye : LucideIcons.eyeOff,
                          size: 18,
                          color: visible
                              ? PulseTokens.accent
                              : PulseTokens.textDisabled,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
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
