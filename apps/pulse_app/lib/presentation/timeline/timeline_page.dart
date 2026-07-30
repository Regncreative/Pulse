import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../app/dev_flags.dart';
import '../../app/theme/pulse_theme.dart';
import '../../application/connection_controller.dart';
import '../../application/timeline_session_controller.dart';
import '../../features/timeline/timeline_display.dart';
import '../../features/timeline/timeline_export.dart';
import '../../features/timeline/widgets/timeline_details_panel.dart';
import '../../features/timeline/widgets/timeline_event_tile.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../components/pulse_app_bar.dart';
import '../components/pulse_badge.dart';
import '../components/pulse_empty_state.dart';
import '../components/pulse_loading.dart';
import '../components/safe_hover.dart';
import '../utils/pulse_snack.dart';
import '../utils/pulse_user_errors.dart';

enum _SeverityFilter { all, errors, warnings, info }

enum _SourceFilter { all, system }

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key, required this.title});

  final String title;

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  /// Stable IPC event id — selection survives filter changes when still visible.
  String? _selectedEventId;
  _SeverityFilter _severity = _SeverityFilter.all;
  _SourceFilter _source = _SourceFilter.all;
  String _searchQuery = '';
  final _listScrollController = ScrollController();

  TimelineSessionController? _session;
  String? _lastTopEventId;
  int _lastEventCount = 0;

  bool get _filtersActive =>
      _severity != _SeverityFilter.all ||
      _source != _SourceFilter.all ||
      _searchQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _listScrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<TimelineSessionController>().setPageVisible(true));
    });
  }

  @override
  void deactivate() {
    unawaited(context.read<TimelineSessionController>().setPageVisible(false));
    super.deactivate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<TimelineSessionController>();
    if (!identical(_session, session)) {
      _session = session;
      final events = session.events;
      _lastEventCount = events.length;
      _lastTopEventId = events.isNotEmpty ? events.first.eventId : null;
    }
  }

  @override
  void dispose() {
    _listScrollController.removeListener(_onScroll);
    _listScrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_listScrollController.hasClients) return;
    final atTop = _listScrollController.position.pixels <= 48;
    context.read<TimelineSessionController>().setStickToTop(atTop);
  }

  void _handleEventsChanged(TimelineSessionController session) {
    final events = session.events;
    final newTopId = events.isNotEmpty ? events.first.eventId : null;
    final isSingleLivePrepend = _lastTopEventId != null &&
        newTopId != null &&
        newTopId != _lastTopEventId &&
        events.length == _lastEventCount + 1 &&
        events.length > 1 &&
        events[1].eventId == _lastTopEventId;

    if (isSingleLivePrepend) {
      final stick = session.stickToTop;
      final beforePixels =
          _listScrollController.hasClients ? _listScrollController.offset : 0.0;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || !_listScrollController.hasClients) return;
        if (stick) {
          await _listScrollController.animateTo(
            0,
            duration: PulseTokens.motionFast,
            curve: PulseTokens.motionCurve,
          );
        } else {
          const estimatedRow = 92.0;
          final target = beforePixels + estimatedRow;
          await _listScrollController.animateTo(
            target,
            duration: PulseTokens.motionFast,
            curve: PulseTokens.motionCurve,
          );
        }
      });
    }

    _lastEventCount = events.length;
    _lastTopEventId = newTopId;
  }

  Future<void> _jumpToNewest() async {
    context.read<TimelineSessionController>().setStickToTop(true);
    if (_listScrollController.hasClients) {
      await _listScrollController.animateTo(
        0,
        duration: PulseTokens.motionSlow,
        curve: PulseTokens.motionEmphasized,
      );
    }
  }

  void _pruneSelection(List<TimelineEvent> events) {
    if (_selectedEventId == null) return;
    final stillVisible = events.any(
      (e) => e.eventId == _selectedEventId && _matches(e),
    );
    if (!stillVisible) {
      _selectedEventId = null;
    }
  }

  void _onSeverity(_SeverityFilter f) {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _severity = f;
      _pruneSelection(events);
    });
  }

  void _onSource(_SourceFilter f) {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _source = f;
      _pruneSelection(events);
    });
  }

  void _onSearch(String q) {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _searchQuery = q;
      _pruneSelection(events);
    });
  }

  void _clearFilters() {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _severity = _SeverityFilter.all;
      _source = _SourceFilter.all;
      _searchQuery = '';
      _pruneSelection(events);
    });
  }

  void _selectEvent(TimelineEvent event) {
    setState(() => _selectedEventId = event.eventId);
  }

  void _clearSelection() {
    setState(() => _selectedEventId = null);
  }

  List<TimelineEvent> _visible(List<TimelineEvent> events) {
    return [for (final e in events) if (_matches(e)) e];
  }

  TimelineEvent? _selectedEvent(List<TimelineEvent> events) {
    final id = _selectedEventId;
    if (id == null) return null;
    for (final e in events) {
      if (e.eventId == id) return e;
    }
    return null;
  }

  bool _matches(TimelineEvent e) {
    final sev = e.severity;
    final severityOk = switch (_severity) {
      _SeverityFilter.all => true,
      _SeverityFilter.errors =>
        sev == Severity.error || sev == Severity.critical,
      _SeverityFilter.warnings => sev == Severity.warning,
      _SeverityFilter.info =>
        sev == Severity.info || sev == Severity.verbose || sev == Severity.unknown,
    };
    if (!severityOk) return false;

    final sourceOk = switch (_source) {
      _SourceFilter.all => true,
      _SourceFilter.system => e.displayChannel.toLowerCase() == 'system',
    };
    if (!sourceOk) return false;

    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final haystack = [
      e.displayTitle,
      e.displaySummary,
      e.message,
      e.technicalSummary,
      e.providerName,
      e.displayChannel,
      e.category,
      e.winEventId.toString(),
      e.recordId.toString(),
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }

  String _emptyMessage({required bool hasEvents, required bool mock}) {
    if (!hasEvents) {
      return mock
          ? 'No sample events are loaded. Rebuild with PULSE_MOCK_TIMELINE or connect PulseService.'
          : 'Pulse is connected and listening for Windows System Event Log activity.\n\n'
              'New events appear here as Windows works. Use Refresh if you expect a historical snapshot.';
    }
    if (_filtersActive) {
      return 'No events match the current search and filters.\n\n'
          'Clear filters or try a different severity / source.';
    }
    return 'Nothing to show in this view.';
  }

  Future<void> _exportJson(List<TimelineEvent> visible) async {
    final selected = _selectedEvent(visible);
    final toExport = selected != null ? [selected] : visible;
    if (toExport.isEmpty) {
      PulseSnack.info(context, 'Nothing to export — adjust filters or wait for events.');
      return;
    }
    try {
      final note = selected != null
          ? 'selected_event'
          : (_filtersActive ? 'filtered_visible' : 'visible_all');
      final json = TimelineExport.encodeEvents(toExport, note: note);
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}${Platform.pathSeparator}Pulse'
          '${Platform.pathSeparator}exports');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File(
        '${dir.path}${Platform.pathSeparator}timeline_$stamp.json',
      );
      await file.writeAsString(json);
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      PulseSnack.success(
        context,
        selected != null
            ? 'Exported selected event (also copied).'
            : 'Exported ${toExport.length} events (also copied).',
      );
    } catch (e) {
      if (!mounted) return;
      PulseSnack.error(context, PulseUserErrors.fromObject(e));
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
    final offline = state == IpcConnectionState.disconnected ||
        state == IpcConnectionState.error;
    final connecting = state == IpcConnectionState.connecting;

    final session = context.watch<TimelineSessionController>();
    _handleEventsChanged(session);

    final events = session.events;
    final liveActive = session.liveActive;
    final loadingSnapshot = session.loadingSnapshot;
    final loadError = session.loadError;
    final pendingNewCount = session.pendingNewCount;
    final busy = connecting || loadingSnapshot;

    final visible = _visible(events);
    final selectedEvent = _selectedEvent(events);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseAppBar(
          title: widget.title,
          connectionState: state,
          connectionLabel: connectionLabel,
          searchEnabled: !offline && !busy && loadError == null,
          searchHint: offline
              ? 'Connect PulseService to search events'
              : 'Search title, summary, provider, or event ID…',
          searchQuery: _searchQuery,
          onSearchChanged: _onSearch,
          actions: [
            if (kUseMockTimeline)
              const PulseBadge(
                label: 'Mock',
                tone: PulseBadgeTone.accent,
                icon: LucideIcons.sparkles,
                compact: true,
              )
            else if (!offline && liveActive)
              const PulseBadge(
                label: 'Live',
                tone: PulseBadgeTone.success,
                icon: LucideIcons.radio,
                compact: true,
              )
            else if (!offline && events.isNotEmpty)
              const PulseBadge(
                label: 'Snapshot',
                tone: PulseBadgeTone.info,
                icon: LucideIcons.history,
                compact: true,
              ),
          ],
        ),
        Expanded(
          child: offline
              ? const PulseEmptyState(
                  useBrandIllustration: true,
                  title: 'Ready when Windows is',
                  message:
                      'Pulse watches what Windows is doing and turns it into a clear, readable timeline.\n\n'
                      'Start PulseService to connect — events will appear here as soon as monitoring begins.',
                )
              : busy
                  ? const _TimelineSkeletonView()
                  : loadError != null
                      ? PulseEmptyState(
                          useBrandIllustration: true,
                          title: 'Could not load timeline',
                          message:
                              'Pulse connected, but the historical snapshot failed.\n\n'
                              '${PulseUserErrors.fromMessage(loadError)}',
                          actionLabel: 'Retry',
                          onAction: session.reloadSnapshot,
                        )
                      : _TimelineBody(
                          selectedEventId: _selectedEventId,
                          selectedEvent: selectedEvent,
                          severity: _severity,
                          source: _source,
                          filtersActive: _filtersActive,
                          visible: visible,
                          hasStoredEvents: events.isNotEmpty,
                          emptyMessage: _emptyMessage(
                            hasEvents: events.isNotEmpty,
                            mock: kUseMockTimeline,
                          ),
                          showMockBanner: kUseMockTimeline,
                          pendingNewCount: pendingNewCount,
                          scrollController: _listScrollController,
                          onSeverity: _onSeverity,
                          onSource: _onSource,
                          onClearFilters: _clearFilters,
                          onSelect: _selectEvent,
                          onClear: _clearSelection,
                          onRefresh: session.reloadSnapshot,
                          onJumpToNewest: _jumpToNewest,
                          onExport: () => _exportJson(visible),
                        ),
        ),
      ],
    );
  }
}

class _TimelineSkeletonView extends StatelessWidget {
  const _TimelineSkeletonView();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PulseTokens.pagePadX,
            PulseTokens.pagePadTop,
            PulseTokens.pagePadX,
            8,
          ),
          child: Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                PulseLoadingBlock(
                  width: 64 + (i * 8),
                  height: 30,
                  borderRadius: BorderRadius.circular(PulseTokens.radiusPill),
                ),
              ],
            ],
          ),
        ),
        const Expanded(child: TimelineSkeleton(rows: 5)),
      ],
    );
  }
}

class _TimelineBody extends StatelessWidget {
  const _TimelineBody({
    required this.selectedEventId,
    required this.selectedEvent,
    required this.severity,
    required this.source,
    required this.filtersActive,
    required this.visible,
    required this.hasStoredEvents,
    required this.emptyMessage,
    required this.showMockBanner,
    required this.pendingNewCount,
    required this.scrollController,
    required this.onSeverity,
    required this.onSource,
    required this.onClearFilters,
    required this.onSelect,
    required this.onClear,
    required this.onRefresh,
    required this.onJumpToNewest,
    required this.onExport,
  });

  final String? selectedEventId;
  final TimelineEvent? selectedEvent;
  final _SeverityFilter severity;
  final _SourceFilter source;
  final bool filtersActive;
  final List<TimelineEvent> visible;
  final bool hasStoredEvents;
  final String emptyMessage;
  final bool showMockBanner;
  final int pendingNewCount;
  final ScrollController scrollController;
  final ValueChanged<_SeverityFilter> onSeverity;
  final ValueChanged<_SourceFilter> onSource;
  final VoidCallback onClearFilters;
  final ValueChanged<TimelineEvent> onSelect;
  final VoidCallback onClear;
  final VoidCallback onRefresh;
  final VoidCallback onJumpToNewest;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final showSideDetail = wide && selectedEvent != null;

        final list = Scrollbar(
          controller: scrollController,
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  PulseTokens.pagePadX,
                  PulseTokens.pagePadTop,
                  PulseTokens.pagePadX,
                  8,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _FilterSection(
                              label: 'Severity',
                              child: _SeverityRow(
                                selected: severity,
                                onSelected: onSeverity,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: selectedEvent != null
                                ? 'Export selected event as JSON'
                                : 'Export visible events as JSON',
                            onPressed: onExport,
                            icon: const Icon(LucideIcons.download, size: 16),
                          ),
                          IconButton(
                            tooltip: 'Refresh snapshot',
                            onPressed: onRefresh,
                            icon: const Icon(LucideIcons.refreshCw, size: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _FilterSection(
                              label: 'Source',
                              child: _SourceRow(
                                selected: source,
                                onSelected: onSource,
                              ),
                            ),
                          ),
                          if (filtersActive)
                            TextButton.icon(
                              onPressed: onClearFilters,
                              icon: const Icon(LucideIcons.filterX, size: 14),
                              label: const Text('Clear filters'),
                              style: TextButton.styleFrom(
                                foregroundColor: PulseTokens.textSecondary,
                                textStyle: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (showMockBanner)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    PulseTokens.pagePadX,
                    10,
                    PulseTokens.pagePadX,
                    8,
                  ),
                  sliver: SliverToBoxAdapter(child: _PreviewBanner()),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  PulseTokens.pagePadX,
                  12,
                  PulseTokens.pagePadX,
                  PulseTokens.pagePadBottom,
                ),
                sliver: SliverToBoxAdapter(
                  child: AnimatedSwitcher(
                    duration: PulseTokens.motionSlow,
                    switchInCurve: PulseTokens.motionCurve,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.02),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(
                        '${severity.name}-${source.name}-${visible.length}-$filtersActive',
                      ),
                      child: visible.isEmpty
                          ? Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 48),
                              child: PulseEmptyState(
                                useBrandIllustration: true,
                                title: hasStoredEvents
                                    ? 'Nothing matches'
                                    : 'Waiting for Windows',
                                message: emptyMessage,
                                actionLabel:
                                    filtersActive ? 'Clear filters' : null,
                                onAction:
                                    filtersActive ? onClearFilters : null,
                              ),
                            )
                          : Column(
                              children: [
                                for (var i = 0; i < visible.length; i++)
                                  TimelineEventTile(
                                    key: ValueKey(
                                      visible[i].eventId.isNotEmpty
                                          ? visible[i].eventId
                                          : 'row-$i',
                                    ),
                                    event: visible[i],
                                    isFirst: i == 0,
                                    isLast: i == visible.length - 1,
                                    emphasize: i == 0 &&
                                        severity == _SeverityFilter.all &&
                                        source == _SourceFilter.all,
                                    animationIndex: i.clamp(0, 12),
                                    selected: selectedEventId != null &&
                                        visible[i].eventId == selectedEventId,
                                    onTap: () => onSelect(visible[i]),
                                  ),
                              ],
                            ),
                    ),
                  ),
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
                Expanded(flex: 3, child: list),
                TimelineDetailsHost(
                  expanded: showSideDetail,
                  width: 400,
                  event: selectedEvent,
                  onClose: onClear,
                ),
              ],
            ),
            if (pendingNewCount > 0)
              Positioned(
                top: 96,
                left: 0,
                right: showSideDetail ? 400 : 0,
                child: Center(
                  child: _NewEventsButton(
                    count: pendingNewCount,
                    onPressed: onJumpToNewest,
                  ),
                ),
              ),
            if (selectedEvent != null && !wide)
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
                      width: constraints.maxWidth.clamp(300, 420),
                      child: TimelineDetailsPanel(
                        event: selectedEvent!,
                        onClose: onClear,
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

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: PulseTokens.textTertiary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _NewEventsButton extends StatelessWidget {
  const _NewEventsButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 new event' : '$count new events';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            color: PulseTokens.accent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: PulseTokens.elevationLift,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.arrowUp,
                  size: 14,
                  color: PulseTokens.onAccent,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: PulseTokens.onAccent,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: PulseTokens.accentSoft.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        border: Border.all(
          color: PulseTokens.accent.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 15, color: PulseTokens.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mock timeline enabled (PULSE_MOCK_TIMELINE). Real System Event Log snapshots are used when this flag is off.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PulseTokens.textSecondary,
                    height: 1.45,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeverityRow extends StatelessWidget {
  const _SeverityRow({required this.selected, required this.onSelected});

  final _SeverityFilter selected;
  final ValueChanged<_SeverityFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (_SeverityFilter.all, 'All'),
      (_SeverityFilter.errors, 'Errors'),
      (_SeverityFilter.warnings, 'Warnings'),
      (_SeverityFilter.info, 'Info'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          _FilterChip(
            label: item.$2,
            selected: selected == item.$1,
            onTap: () => onSelected(item.$1),
          ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.selected, required this.onSelected});

  final _SourceFilter selected;
  final ValueChanged<_SourceFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (_SourceFilter.all, 'All'),
      (_SourceFilter.system, 'System'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          _FilterChip(
            label: item.$2,
            selected: selected == item.$1,
            onTap: () => onSelected(item.$1),
          ),
      ],
    );
  }
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> with SafeHoverState {
  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setHovered(true),
      onExit: (_) => setHovered(false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: PulseTokens.motionFast,
          curve: PulseTokens.motionCurve,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? PulseTokens.accentSoft
                : hover
                    ? PulseTokens.surfaceHover
                    : PulseTokens.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? PulseTokens.accent.withValues(alpha: 0.38)
                  : PulseTokens.stroke.withValues(alpha: 0.65),
            ),
            boxShadow: selected ? PulseTokens.elevationSoft : null,
          ),
          child: AnimatedDefaultTextStyle(
            duration: PulseTokens.motionFast,
            style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color:
                      selected ? PulseTokens.accent : PulseTokens.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 12.5,
                ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}
