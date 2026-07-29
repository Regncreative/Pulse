import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../app/dev_flags.dart';
import '../../app/theme/pulse_theme.dart';
import '../../application/connection_controller.dart';
import '../../application/timeline_session_controller.dart';
import '../../features/timeline/timeline_display.dart';
import '../../features/timeline/widgets/timeline_details_panel.dart';
import '../../features/timeline/widgets/timeline_event_tile.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../components/pulse_app_bar.dart';
import '../components/pulse_badge.dart';
import '../components/pulse_empty_state.dart';
import '../components/pulse_loading.dart';
import '../components/safe_hover.dart';
import '../utils/pulse_user_errors.dart';

enum _TimelineFilter { all, errors, warnings, system, application }

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key, required this.title});

  final String title;

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  /// Stable IPC event id — selection survives filter changes when still visible.
  String? _selectedEventId;
  _TimelineFilter _filter = _TimelineFilter.all;
  final _listScrollController = ScrollController();

  TimelineSessionController? _session;
  String? _lastTopEventId;
  int _lastEventCount = 0;

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

  /// Detects a single new live event prepended to [events] since the last
  /// build and keeps the viewport stable (or follows to the top when the
  /// session is sticking) — the session only owns data, scrolling is UI.
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

  void _onFilter(_TimelineFilter f) {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _filter = f;
      if (_selectedEventId == null) return;
      final stillVisible = events.any(
        (e) => e.eventId == _selectedEventId && _matches(e, f),
      );
      if (!stillVisible) {
        _selectedEventId = null;
      }
    });
  }

  void _selectEvent(TimelineEvent event) {
    setState(() => _selectedEventId = event.eventId);
  }

  void _clearSelection() {
    // Close panel only — do not reload timeline.
    setState(() => _selectedEventId = null);
  }

  List<TimelineEvent> _visible(List<TimelineEvent> events) {
    return [for (final e in events) if (_matches(e, _filter)) e];
  }

  TimelineEvent? _selectedEvent(List<TimelineEvent> events) {
    final id = _selectedEventId;
    if (id == null) return null;
    for (final e in events) {
      if (e.eventId == id) return e;
    }
    return null;
  }

  bool _matches(TimelineEvent e, _TimelineFilter f) {
    final sev = e.severity;
    return switch (f) {
      _TimelineFilter.all => true,
      _TimelineFilter.errors =>
        sev == Severity.error || sev == Severity.critical,
      _TimelineFilter.warnings => sev == Severity.warning,
      _TimelineFilter.system => e.displayChannel == 'System',
      _TimelineFilter.application => e.displayChannel == 'Application',
    };
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

    final selectedEvent = _selectedEvent(events);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseAppBar(
          title: widget.title,
          connectionState: state,
          connectionLabel: connectionLabel,
          searchHint: 'Search becomes available once live events are collected.',
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
                          filter: _filter,
                          visible: _visible(events),
                          showMockBanner: kUseMockTimeline,
                          pendingNewCount: pendingNewCount,
                          scrollController: _listScrollController,
                          onFilter: _onFilter,
                          onSelect: _selectEvent,
                          onClear: _clearSelection,
                          onRefresh: session.reloadSnapshot,
                          onJumpToNewest: _jumpToNewest,
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

class _TimelineBody extends StatefulWidget {
  const _TimelineBody({
    required this.selectedEventId,
    required this.selectedEvent,
    required this.filter,
    required this.visible,
    required this.showMockBanner,
    required this.pendingNewCount,
    required this.scrollController,
    required this.onFilter,
    required this.onSelect,
    required this.onClear,
    required this.onRefresh,
    required this.onJumpToNewest,
  });

  final String? selectedEventId;
  final TimelineEvent? selectedEvent;
  final _TimelineFilter filter;
  final List<TimelineEvent> visible;
  final bool showMockBanner;
  final int pendingNewCount;
  final ScrollController scrollController;
  final ValueChanged<_TimelineFilter> onFilter;
  final ValueChanged<TimelineEvent> onSelect;
  final VoidCallback onClear;
  final VoidCallback onRefresh;
  final VoidCallback onJumpToNewest;

  @override
  State<_TimelineBody> createState() => _TimelineBodyState();
}

class _TimelineBodyState extends State<_TimelineBody> {
  @override
  Widget build(BuildContext context) {
    final selectedEvent = widget.selectedEvent;
    final filter = widget.filter;
    final visible = widget.visible;
    final showMockBanner = widget.showMockBanner;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final showSideDetail = wide && selectedEvent != null;

        final list = Scrollbar(
          controller: widget.scrollController,
          child: CustomScrollView(
            controller: widget.scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  PulseTokens.pagePadX,
                  PulseTokens.pagePadTop,
                  PulseTokens.pagePadX,
                  8,
                ),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: _FilterRow(
                          selected: filter,
                          onSelected: widget.onFilter,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh snapshot',
                        onPressed: widget.onRefresh,
                        icon: const Icon(LucideIcons.refreshCw, size: 16),
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
                      key: ValueKey(filter),
                      child: visible.isEmpty
                          ? Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 48),
                              child: PulseEmptyState(
                                useBrandIllustration: true,
                                title: 'Nothing in this view',
                                message: showMockBanner
                                    ? 'No sample events match this filter. Choose All to see the full preview timeline.'
                                    : 'No System events matched this filter in the latest snapshot.',
                              ),
                            )
                          : Column(
                              children: [
                                for (var i = 0; i < visible.length; i++)
                                  TimelineEventTile(
                                    key: ValueKey(
                                      visible[i].eventId.isNotEmpty
                                          ? visible[i].eventId
                                          : '${filter.name}-$i',
                                    ),
                                    event: visible[i],
                                    isFirst: i == 0,
                                    isLast: i == visible.length - 1,
                                    emphasize:
                                        i == 0 && filter == _TimelineFilter.all,
                                    animationIndex: i.clamp(0, 12),
                                    selected: widget.selectedEventId != null &&
                                        visible[i].eventId ==
                                            widget.selectedEventId,
                                    onTap: () =>
                                        widget.onSelect(visible[i]),
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
                  onClose: widget.onClear,
                ),
              ],
            ),
            if (widget.pendingNewCount > 0)
              Positioned(
                top: 64,
                left: 0,
                right: showSideDetail ? 400 : 0,
                child: Center(
                  child: _NewEventsButton(
                    count: widget.pendingNewCount,
                    onPressed: widget.onJumpToNewest,
                  ),
                ),
              ),
            if (selectedEvent != null && !wide)
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.onClear,
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.38),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: constraints.maxWidth.clamp(300, 420),
                      child: TimelineDetailsPanel(
                        event: selectedEvent,
                        onClose: widget.onClear,
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
                const Icon(LucideIcons.arrowUp, size: 14, color: PulseTokens.onAccent),
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

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.selected, required this.onSelected});

  final _TimelineFilter selected;
  final ValueChanged<_TimelineFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (_TimelineFilter.all, 'All'),
      (_TimelineFilter.errors, 'Errors'),
      (_TimelineFilter.warnings, 'Warnings'),
      (_TimelineFilter.system, 'System'),
      (_TimelineFilter.application, 'Application'),
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
