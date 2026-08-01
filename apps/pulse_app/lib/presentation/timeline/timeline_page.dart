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
import '../../application/timeline_library_controller.dart';
import '../../application/timeline_session_controller.dart';
import '../../features/timeline/timeline_display.dart';
import '../../features/timeline/timeline_export.dart';
import '../../features/timeline/timeline_incident_engine.dart';
import '../../features/timeline/timeline_query.dart';
import '../../features/timeline/widgets/timeline_details_panel.dart';
import '../../features/timeline/widgets/timeline_event_tile.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../components/pulse_app_bar.dart';
import '../components/pulse_badge.dart';
import '../components/pulse_empty_state.dart';
import '../components/pulse_loading.dart';
import '../components/safe_hover.dart';
import '../components/service_lifecycle_controls.dart';
import '../utils/pulse_snack.dart';
import '../utils/pulse_user_errors.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key, required this.title});

  final String title;

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  /// Stable IPC event id — selection survives filter changes when still visible.
  String? _selectedEventId;
  TimelineQuery _query = const TimelineQuery();
  final _listScrollController = ScrollController();
  final _providerFilterController = TextEditingController();
  final _eventIdFilterController = TextEditingController();
  final _processFilterController = TextEditingController();
  final _incidentEngine = TimelineIncidentEngine();
  final Set<String> _expandedIncidents = {};

  TimelineSessionController? _session;
  String? _lastTopEventId;
  int _lastEventCount = 0;

  bool get _filtersActive => _query.isActive;

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
    _providerFilterController.dispose();
    _eventIdFilterController.dispose();
    _processFilterController.dispose();
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
      (e) => e.eventId == _selectedEventId && _query.matches(e),
    );
    if (!stillVisible) {
      _selectedEventId = null;
    }
  }

  void _onSeverity(TimelineSeverityFilter f) {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _query = _query.copyWith(severity: f);
      _pruneSelection(events);
    });
  }

  void _onSource(TimelineSourceFilter f) {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _query = _query.copyWith(source: f);
      _pruneSelection(events);
    });
  }

  void _onCategory(TimelineCategoryFilter f) {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _query = _query.copyWith(category: f);
      _pruneSelection(events);
    });
  }

  void _onDateRange(TimelineDateRangeFilter f) {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _query = _query.copyWith(dateRange: f);
      _pruneSelection(events);
    });
  }

  void _onSearch(String q) {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _query = _query.copyWith(searchQuery: q);
      _pruneSelection(events);
    });
  }

  void _onProviderFilter(String v) {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _query = _query.copyWith(providerContains: v);
      _pruneSelection(events);
    });
  }

  void _onEventIdFilter(String v) {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _query = _query.copyWith(eventIdEquals: v);
      _pruneSelection(events);
    });
  }

  void _onProcessFilter(String v) {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _query = _query.copyWith(processContains: v);
      _pruneSelection(events);
    });
  }

  void _clearFilters() {
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _query = const TimelineQuery();
      _providerFilterController.clear();
      _eventIdFilterController.clear();
      _processFilterController.clear();
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
    final matched = [for (final e in events) if (_query.matches(e)) e];
    final library = context.read<TimelineLibraryController>();
    matched.sort((a, b) {
      final ap = library.isPinned(a.eventId) ? 0 : 1;
      final bp = library.isPinned(b.eventId) ? 0 : 1;
      if (ap != bp) return ap.compareTo(bp);
      return 0;
    });
    return matched;
  }

  TimelineEvent? _selectedEvent(List<TimelineEvent> events) {
    final id = _selectedEventId;
    if (id == null) return null;
    for (final e in events) {
      if (e.eventId == id) return e;
    }
    return null;
  }

  String _emptyMessage({required bool hasEvents, required bool mock}) {
    if (!hasEvents) {
      return mock
          ? 'No sample events are loaded. Rebuild with PULSE_MOCK_TIMELINE or connect PulseService.'
          : 'Pulse is connected and listening across diagnostics Event Log channels.\n\n'
              'New events appear here as Windows works. Use Refresh if you expect a historical snapshot.';
    }
    if (_filtersActive) {
      return 'No events match the current search and filters.\n\n'
          'Clear filters or try a different severity, source, category, provider, or date range.';
    }
    return 'Nothing to show in this view.';
  }

  Future<void> _saveCurrentSearch() async {
    if (!_query.isActive) {
      PulseSnack.info(context, 'Set a search or filter before saving.');
      return;
    }
    final controller = TextEditingController(
      text: _query.searchQuery.trim().isNotEmpty
          ? _query.searchQuery.trim()
          : 'Saved search',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Save search'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Kernel-Power 41',
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    await context.read<TimelineLibraryController>().saveSearch(
          name: name,
          query: _query,
        );
    if (!mounted) return;
    PulseSnack.success(context, 'Saved search “${name.trim()}”.');
  }

  void _applySavedSearch(SavedTimelineSearch saved) {
    final q = context.read<TimelineLibraryController>().queryFromSaved(saved);
    if (q == null) return;
    final events = context.read<TimelineSessionController>().events;
    setState(() {
      _query = q;
      _providerFilterController.text = q.providerContains;
      _eventIdFilterController.text = q.eventIdEquals;
      _processFilterController.text = q.processContains;
      _pruneSelection(events);
    });
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
      final library = context.read<TimelineLibraryController>();
      final json = TimelineExport.encodeEvents(
        toExport,
        note: note,
        appliedFilters: _query,
        bookmarkedEventIds: library.bookmarkedEventIds,
        pinnedEventIds: library.pinnedEventIds,
      );
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
    context.watch<TimelineLibraryController>();
    _handleEventsChanged(session);

    final events = session.events;
    final liveActive = session.liveActive;
    final loadingSnapshot = session.loadingSnapshot;
    final loadError = session.loadError;
    final pendingNewCount = session.pendingNewCount;
    final busy = connecting || loadingSnapshot;

    final visible = _visible(events);
    final selectedEvent = _selectedEvent(events);
    final listItems = _incidentEngine.buildItems(visible);
    final selectedRca = selectedEvent == null
        ? null
        : _incidentEngine.hintForEvent(selectedEvent, visible);

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
              : 'Search provider, Event ID, computer, message, process, PID…',
          searchQuery: _query.searchQuery,
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
              ? const ServiceOfflineRecovery(
                  titleFallback: 'Ready when Windows is',
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
                          selectedRca: selectedRca,
                          allVisibleEvents: visible,
                          listItems: listItems,
                          expandedIncidents: _expandedIncidents,
                          onToggleIncident: (id) {
                            setState(() {
                              if (_expandedIncidents.contains(id)) {
                                _expandedIncidents.remove(id);
                              } else {
                                _expandedIncidents.add(id);
                              }
                            });
                          },
                          query: _query,
                          providerFilterController: _providerFilterController,
                          eventIdFilterController: _eventIdFilterController,
                          processFilterController: _processFilterController,
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
                          onCategory: _onCategory,
                          onDateRange: _onDateRange,
                          onProviderFilter: _onProviderFilter,
                          onEventIdFilter: _onEventIdFilter,
                          onProcessFilter: _onProcessFilter,
                          onClearFilters: _clearFilters,
                          onSaveSearch: _saveCurrentSearch,
                          onApplySavedSearch: _applySavedSearch,
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
    required this.selectedRca,
    required this.allVisibleEvents,
    required this.listItems,
    required this.expandedIncidents,
    required this.onToggleIncident,
    required this.query,
    required this.providerFilterController,
    required this.eventIdFilterController,
    required this.processFilterController,
    required this.filtersActive,
    required this.visible,
    required this.hasStoredEvents,
    required this.emptyMessage,
    required this.showMockBanner,
    required this.pendingNewCount,
    required this.scrollController,
    required this.onSeverity,
    required this.onSource,
    required this.onCategory,
    required this.onDateRange,
    required this.onProviderFilter,
    required this.onEventIdFilter,
    required this.onProcessFilter,
    required this.onClearFilters,
    required this.onSaveSearch,
    required this.onApplySavedSearch,
    required this.onSelect,
    required this.onClear,
    required this.onRefresh,
    required this.onJumpToNewest,
    required this.onExport,
  });

  final String? selectedEventId;
  final TimelineEvent? selectedEvent;
  final TimelineRcaHint? selectedRca;
  final List<TimelineEvent> allVisibleEvents;
  final List<TimelineListItem> listItems;
  final Set<String> expandedIncidents;
  final ValueChanged<String> onToggleIncident;
  final TimelineQuery query;
  final TextEditingController providerFilterController;
  final TextEditingController eventIdFilterController;
  final TextEditingController processFilterController;
  final bool filtersActive;
  final List<TimelineEvent> visible;
  final bool hasStoredEvents;
  final String emptyMessage;
  final bool showMockBanner;
  final int pendingNewCount;
  final ScrollController scrollController;
  final ValueChanged<TimelineSeverityFilter> onSeverity;
  final ValueChanged<TimelineSourceFilter> onSource;
  final ValueChanged<TimelineCategoryFilter> onCategory;
  final ValueChanged<TimelineDateRangeFilter> onDateRange;
  final ValueChanged<String> onProviderFilter;
  final ValueChanged<String> onEventIdFilter;
  final ValueChanged<String> onProcessFilter;
  final VoidCallback onClearFilters;
  final VoidCallback onSaveSearch;
  final ValueChanged<SavedTimelineSearch> onApplySavedSearch;
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
                                selected: query.severity,
                                onSelected: onSeverity,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: selectedEvent != null
                                ? 'Export selected event as JSON'
                                : 'Export visible events as JSON',
                            onPressed: onExport,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            icon: const Icon(LucideIcons.download, size: 16),
                          ),
                          IconButton(
                            tooltip: 'Refresh snapshot',
                            onPressed: onRefresh,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
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
                                selected: query.source,
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
                          if (filtersActive)
                            TextButton.icon(
                              onPressed: onSaveSearch,
                              icon: const Icon(LucideIcons.save, size: 14),
                              label: const Text('Save search'),
                              style: TextButton.styleFrom(
                                foregroundColor: PulseTokens.textSecondary,
                                textStyle: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          Consumer<TimelineLibraryController>(
                            builder: (context, library, _) {
                              if (library.savedSearches.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return PopupMenuButton<String>(
                                tooltip: 'Saved searches',
                                onSelected: (id) {
                                  if (id.startsWith('del:')) {
                                    library.deleteSavedSearch(
                                      id.substring(4),
                                    );
                                    return;
                                  }
                                  for (final s in library.savedSearches) {
                                    if (s.id == id) {
                                      onApplySavedSearch(s);
                                      break;
                                    }
                                  }
                                },
                                itemBuilder: (context) => [
                                  for (final s in library.savedSearches) ...[
                                    PopupMenuItem(
                                      value: s.id,
                                      child: Text(s.name),
                                    ),
                                    PopupMenuItem(
                                      value: 'del:${s.id}',
                                      child: Text(
                                        'Delete “${s.name}”',
                                        style: TextStyle(
                                          color: PulseTokens.severityError,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(LucideIcons.bookmark, size: 14),
                                      SizedBox(width: 6),
                                      Text(
                                        'Saved',
                                        style: TextStyle(fontSize: 12.5),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _FilterSection(
                        label: 'Type',
                        child: _CategoryRow(
                          selected: query.category,
                          onSelected: onCategory,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _FilterSection(
                        label: 'When',
                        child: _DateRangeRow(
                          selected: query.dateRange,
                          onSelected: onDateRange,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _AdvancedFilterFields(
                        providerController: providerFilterController,
                        eventIdController: eventIdFilterController,
                        processController: processFilterController,
                        onProvider: onProviderFilter,
                        onEventId: onEventIdFilter,
                        onProcess: onProcessFilter,
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
                sliver: visible.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
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
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final item = listItems[i];
                            if (item is TimelineLoneEventItem) {
                              final event = item.event;
                              return TimelineEventTile(
                                key: ValueKey(
                                  event.eventId.isNotEmpty
                                      ? event.eventId
                                      : 'row-$i',
                                ),
                                event: event,
                                isFirst: i == 0,
                                isLast: i == listItems.length - 1,
                                emphasize: i == 0 && !filtersActive,
                                animationIndex: i.clamp(0, 12),
                                selected: selectedEventId != null &&
                                    event.eventId == selectedEventId,
                                onTap: () => onSelect(event),
                              );
                            }
                            final incident =
                                (item as TimelineIncidentItem).incident;
                            final expanded =
                                expandedIncidents.contains(incident.id);
                            return _IncidentGroupTile(
                              incident: incident,
                              expanded: expanded,
                              selectedEventId: selectedEventId,
                              onToggle: () => onToggleIncident(incident.id),
                              onSelect: onSelect,
                            );
                          },
                          childCount: listItems.length,
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
                if (showSideDetail)
                  SizedBox(
                    width: 400,
                    child: TimelineDetailsPanel(
                      event: selectedEvent!,
                      onClose: onClear,
                      rcaHint: selectedRca,
                      relatedEvents: allVisibleEvents,
                      onSelectRelated: onSelect,
                    ),
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
                        rcaHint: selectedRca,
                        relatedEvents: allVisibleEvents,
                        onSelectRelated: onSelect,
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

class _IncidentGroupTile extends StatelessWidget {
  const _IncidentGroupTile({
    required this.incident,
    required this.expanded,
    required this.selectedEventId,
    required this.onToggle,
    required this.onSelect,
  });

  final TimelineIncident incident;
  final bool expanded;
  final String? selectedEventId;
  final VoidCallback onToggle;
  final ValueChanged<TimelineEvent> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: PulseTokens.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
          border: Border.all(color: PulseTokens.strokeSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(
                expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                size: 18,
              ),
              title: Text(incident.title),
              subtitle: Text(
                '${incident.memberCount} related · ${incident.rca.confidenceLabel} confidence · rule ${incident.ruleId}',
              ),
              trailing: const PulseBadge(label: 'Correlated', compact: true),
              onTap: onToggle,
            ),
            if (expanded)
              for (final e in incident.events)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TimelineEventTile(
                    event: e,
                    isFirst: false,
                    isLast: false,
                    emphasize: false,
                    animationIndex: 0,
                    selected: selectedEventId != null &&
                        e.eventId == selectedEventId,
                    onTap: () => onSelect(e),
                  ),
                ),
          ],
        ),
      ),
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
    return Semantics(
      button: true,
      label: '$label. Jump to newest',
      child: Material(
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
                  Icon(
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
              'Mock timeline enabled (PULSE_MOCK_TIMELINE). Real multi-channel Event Log snapshots are used when this flag is off.',
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

  final TimelineSeverityFilter selected;
  final ValueChanged<TimelineSeverityFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (TimelineSeverityFilter.all, 'All'),
      (TimelineSeverityFilter.errors, 'Errors'),
      (TimelineSeverityFilter.warnings, 'Warnings'),
      (TimelineSeverityFilter.info, 'Info'),
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

  final TimelineSourceFilter selected;
  final ValueChanged<TimelineSourceFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (TimelineSourceFilter.all, 'All'),
      (TimelineSourceFilter.system, 'System'),
      (TimelineSourceFilter.application, 'Application'),
      (TimelineSourceFilter.security, 'Security'),
      (TimelineSourceFilter.other, 'Other'),
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

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.selected, required this.onSelected});

  final TimelineCategoryFilter selected;
  final ValueChanged<TimelineCategoryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (TimelineCategoryFilter.all, 'All'),
      (TimelineCategoryFilter.crash, 'Crash'),
      (TimelineCategoryFilter.service, 'Service'),
      (TimelineCategoryFilter.power, 'Power'),
      (TimelineCategoryFilter.update, 'Update'),
      (TimelineCategoryFilter.device, 'Device'),
      (TimelineCategoryFilter.boot, 'Boot'),
      (TimelineCategoryFilter.security, 'Security'),
      (TimelineCategoryFilter.storage, 'Storage'),
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

class _DateRangeRow extends StatelessWidget {
  const _DateRangeRow({required this.selected, required this.onSelected});

  final TimelineDateRangeFilter selected;
  final ValueChanged<TimelineDateRangeFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (TimelineDateRangeFilter.all, 'All time'),
      (TimelineDateRangeFilter.lastHour, '1 hour'),
      (TimelineDateRangeFilter.last24Hours, '24 hours'),
      (TimelineDateRangeFilter.last7Days, '7 days'),
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

class _AdvancedFilterFields extends StatelessWidget {
  const _AdvancedFilterFields({
    required this.providerController,
    required this.eventIdController,
    required this.processController,
    required this.onProvider,
    required this.onEventId,
    required this.onProcess,
  });

  final TextEditingController providerController;
  final TextEditingController eventIdController;
  final TextEditingController processController;
  final ValueChanged<String> onProvider;
  final ValueChanged<String> onEventId;
  final ValueChanged<String> onProcess;

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label, String hint) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: providerController,
            decoration: deco('Provider', 'e.g. Kernel-Power'),
            onChanged: onProvider,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: eventIdController,
            decoration: deco('Event ID', '41'),
            keyboardType: TextInputType.number,
            onChanged: onEventId,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: processController,
            decoration: deco('Process / PID', 'explorer.exe'),
            onChanged: onProcess,
          ),
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
    return Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setHovered(true),
        onExit: (_) => setHovered(false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: PulseTokens.motionFast,
            curve: PulseTokens.motionCurve,
            constraints: const BoxConstraints(minHeight: 28),
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
                    color: selected
                        ? PulseTokens.accent
                        : PulseTokens.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 12.5,
                  ),
              child: Text(widget.label),
            ),
          ),
        ),
      ),
    );
  }
}
