import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../../app/theme/pulse_theme.dart';
import '../../../application/timeline_library_controller.dart';
import '../../../ipc/pulse_ipc_client.dart';
import '../../../presentation/components/pulse_badge.dart';
import '../timeline_display.dart';
import '../timeline_incident_engine.dart';
import 'detail_section.dart';
import 'metadata_table.dart';

/// Right-side Event Details panel.
/// Compact Wevtapi fields come from the list [TimelineEvent]; raw XML is lazy-loaded.
class TimelineDetailsPanel extends StatefulWidget {
  const TimelineDetailsPanel({
    super.key,
    required this.event,
    required this.onClose,
    this.rcaHint,
    this.relatedEvents = const [],
    this.onSelectRelated,
    this.isLive = false,
  });

  final TimelineEvent event;
  final VoidCallback onClose;
  final TimelineRcaHint? rcaHint;
  final List<TimelineEvent> relatedEvents;
  final ValueChanged<TimelineEvent>? onSelectRelated;
  final bool isLive;

  @override
  State<TimelineDetailsPanel> createState() => _TimelineDetailsPanelState();
}

class _TimelineDetailsPanelState extends State<TimelineDetailsPanel> {
  String? _rawXml;
  bool _loadingXml = false;
  String? _xmlError;
  bool _xmlRequested = false;

  TimelineEvent get event => widget.event;

  @override
  void didUpdateWidget(covariant TimelineDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.eventId != widget.event.eventId) {
      _rawXml = widget.event.rawXml.isNotEmpty ? widget.event.rawXml : null;
      _loadingXml = false;
      _xmlError = null;
      _xmlRequested = false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (event.rawXml.isNotEmpty) {
      _rawXml = event.rawXml;
      _xmlRequested = true;
    }
  }

  Future<void> _loadRawXml() async {
    if (_xmlRequested || _loadingXml) return;
    if (event.channel.isEmpty || event.recordId == 0) {
      setState(() {
        _xmlRequested = true;
        _xmlError = 'Record ID or channel unavailable — cannot load Event XML.';
      });
      return;
    }
    setState(() {
      _loadingXml = true;
      _xmlError = null;
      _xmlRequested = true;
    });
    try {
      final ipc = context.read<PulseIpcClient>();
      final detail = await ipc.getTimelineEventDetail(
        channel: event.displayChannel,
        recordId: event.recordId,
      );
      if (!mounted) return;
      if (!detail.found) {
        setState(() {
          _loadingXml = false;
          _xmlError = 'Event was not found in the Event Log (it may have been cleared).';
        });
        return;
      }
      setState(() {
        _loadingXml = false;
        _rawXml = detail.event.rawXml;
        if (_rawXml == null || _rawXml!.isEmpty) {
          _xmlError = 'Windows did not return Event XML for this record.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingXml = false;
        _xmlError = e.toString();
      });
    }
  }

  List<MetadataEntry> _technicalEntries({required bool dense}) {
    String dash(String v) => dense ? (v.isEmpty ? '—' : v) : v;
    String hexKeywords() {
      if (!event.hasKeywords) return '';
      return '0x${event.keywords.toUnsigned(64).toRadixString(16)}';
    }

    // Structured Wevtapi system props mirrored on TimelineEvent.
    // Version / Qualifiers / Provider Guid appear in Raw Event XML when present
    // (not duplicated as structured columns in R2 — see validation report).
    return [
      MetadataEntry('Logged (ISO UTC)', dash(event.timestampIso)),
      MetadataEntry(
        'Logged (Unix ms)',
        event.timestampUnixMs == 0
            ? dash('')
            : event.timestampUnixMs.toString(),
      ),
      MetadataEntry('Provider', dash(event.providerName)),
      MetadataEntry(
        'Event ID',
        event.winEventId == 0 ? dash('') : event.winEventId.toString(),
      ),
      MetadataEntry('Channel', dash(event.displayChannel)),
      MetadataEntry('Computer', dash(event.computerName)),
      MetadataEntry(
        'Level',
        dash(event.levelName.isNotEmpty
            ? event.levelName
            : event.severityVisual.label),
      ),
      MetadataEntry(
        'Task',
        event.hasTask ? event.task.toString() : dash(''),
      ),
      MetadataEntry(
        'Opcode',
        event.hasOpcode ? event.opcode.toString() : dash(''),
      ),
      MetadataEntry('Keywords', dash(hexKeywords())),
      MetadataEntry(
        'Process',
        dash(event.processName),
      ),
      MetadataEntry(
        'PID',
        event.hasProcessId ? event.processId.toString() : dash(''),
      ),
      MetadataEntry(
        'Thread ID',
        event.hasThreadId ? event.threadId.toString() : dash(''),
      ),
      MetadataEntry('User (SID)', dash(event.userSid)),
      MetadataEntry(
        'Record ID',
        event.recordId == 0 ? dash('') : event.recordId.toString(),
      ),
      MetadataEntry('Activity ID', dash(event.activityId)),
      MetadataEntry(
        'Related Activity ID',
        dash(event.relatedActivityId),
      ),
      MetadataEntry('Category', dash(event.category)),
      MetadataEntry('Importance', dash(event.importanceLabel)),
      MetadataEntry(
        'Pulse event id',
        dense
            ? (event.eventId.isEmpty ? '—' : event.eventId)
            : dash(event.eventId),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final style = event.severityVisual;

    return Container(
      decoration: BoxDecoration(
        color: PulseTokens.sidebarSolid.withValues(alpha: 0.98),
        border: Border(
          left: BorderSide(color: PulseTokens.strokeSubtle),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailsHeader(
            onClose: widget.onClose,
            bookmarked: context.watch<TimelineLibraryController>()
                .isBookmarked(event.eventId),
            pinned: context
                .watch<TimelineLibraryController>()
                .isPinned(event.eventId),
            onToggleBookmark: () => context
                .read<TimelineLibraryController>()
                .toggleBookmark(event.eventId),
            onTogglePin: () => context
                .read<TimelineLibraryController>()
                .togglePin(event.eventId),
          ),
          Divider(height: 1, color: PulseTokens.strokeSubtle),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                DetailSection(
                  title: 'Overview',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.displayTitle,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontSize: 18,
                              height: 1.3,
                              letterSpacing: -0.2,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        event.displaySummary,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: PulseTokens.textSecondary,
                              height: 1.45,
                            ),
                      ),
                      if (event.technicalSummary.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          event.technicalSummary,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: PulseTokens.textTertiary,
                                    height: 1.4,
                                  ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        event.actionGuidance,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: event.actionRequired
                                  ? PulseTokens.severityWarning
                                  : PulseTokens.textTertiary,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      if (event.showRecommendationSection) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: PulseTokens.warningSoft.withValues(alpha: 0.55),
                            borderRadius:
                                BorderRadius.circular(PulseTokens.radiusMd),
                            border: Border.all(
                              color: PulseTokens.severityWarning
                                  .withValues(alpha: 0.22),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Recommendation',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: PulseTokens.severityWarning,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                event.recommendation,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: PulseTokens.textSecondary,
                                      height: 1.45,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          PulseBadge(
                            label: style.label,
                            tone: style.tone,
                            compact: true,
                          ),
                          PulseBadge(
                            label: event.importanceLabel,
                            tone: event.actionRequired
                                ? PulseBadgeTone.warning
                                : PulseBadgeTone.neutral,
                            compact: true,
                          ),
                          if (event.category.isNotEmpty)
                            PulseBadge(
                              label: event.category,
                              compact: true,
                            ),
                          if (widget.isLive)
                            const PulseBadge(
                              label: 'Live',
                              tone: PulseBadgeTone.success,
                              compact: true,
                            ),
                          if (widget.rcaHint != null)
                            const PulseBadge(
                              label: 'Correlated',
                              compact: true,
                            ),
                          if (widget.rcaHint != null)
                            const PulseBadge(
                              label: 'Generated by rule',
                              compact: true,
                            ),
                          if (context.watch<TimelineLibraryController>()
                              .isBookmarked(event.eventId))
                            const PulseBadge(
                              label: 'Bookmarked',
                              compact: true,
                            ),
                          if (context.watch<TimelineLibraryController>()
                              .isPinned(event.eventId))
                            const PulseBadge(
                              label: 'Pinned',
                              compact: true,
                            ),
                          _OverviewChip(
                            icon: LucideIcons.clock,
                            label: event.absoluteTimeLabel,
                          ),
                          _OverviewChip(
                            icon: LucideIcons.timer,
                            label: event.relativeTimeLabel,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: PulseTokens.strokeSubtle),
                if (widget.rcaHint != null)
                  DetailSection(
                    title: 'Possible cause',
                    child: _RcaHintBox(hint: widget.rcaHint!),
                  ),
                if (widget.rcaHint != null)
                  Divider(height: 1, color: PulseTokens.strokeSubtle),
                if (widget.onSelectRelated != null)
                  DetailSection(
                    title: 'Event links',
                    child: _EventLinks(
                      event: event,
                      relatedIds: widget.rcaHint?.relatedEventIds ?? const [],
                      pool: widget.relatedEvents,
                      onSelect: widget.onSelectRelated!,
                    ),
                  ),
                if (widget.onSelectRelated != null)
                  Divider(height: 1, color: PulseTokens.strokeSubtle),
                DetailSection(
                  title: 'Technical Information',
                  child: MetadataTable(
                    entries: _technicalEntries(dense: false),
                  ),
                ),
                Divider(height: 1, color: PulseTokens.strokeSubtle),
                DetailSection(
                  title: 'Original Windows Message',
                  child: _OriginalMessageBox(
                    message: event.message.isNotEmpty
                        ? event.message
                        : 'No original Event Viewer message was available for this entry.',
                  ),
                ),
                Divider(height: 1, color: PulseTokens.strokeSubtle),
                DetailSection(
                  title: 'Raw Event XML',
                  child: _RawXmlSection(
                    loading: _loadingXml,
                    error: _xmlError,
                    xml: _rawXml,
                    onLoad: _loadRawXml,
                    loaded: _xmlRequested && !_loadingXml,
                  ),
                ),
                Divider(height: 1, color: PulseTokens.strokeSubtle),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      initiallyExpanded: false,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      iconColor: PulseTokens.textTertiary,
                      collapsedIconColor: PulseTokens.textTertiary,
                      title: Text(
                        'RAW METADATA',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: PulseTokens.textTertiary,
                              letterSpacing: 0.9,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      children: [
                        MetadataTable(
                          dense: true,
                          entries: _technicalEntries(dense: true),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RcaHintBox extends StatelessWidget {
  const _RcaHintBox({required this.hint});

  final TimelineRcaHint hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hint.possibleCause,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: PulseTokens.textSecondary,
                height: 1.45,
              ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PulseBadge(
              label: 'Confidence: ${hint.confidenceLabel}',
              compact: true,
            ),
            PulseBadge(
              label: 'Rule ${hint.ruleId}',
              compact: true,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Suggested next step',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          hint.nextStep,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PulseTokens.textSecondary,
                height: 1.45,
              ),
        ),
      ],
    );
  }
}

class _EventLinks extends StatelessWidget {
  const _EventLinks({
    required this.event,
    required this.relatedIds,
    required this.pool,
    required this.onSelect,
  });

  final TimelineEvent event;
  final List<String> relatedIds;
  final List<TimelineEvent> pool;
  final ValueChanged<TimelineEvent> onSelect;

  @override
  Widget build(BuildContext context) {
    TimelineEvent? byId(String id) {
      for (final e in pool) {
        if (e.eventId == id) return e;
      }
      return null;
    }

    final related = [
      for (final id in relatedIds)
        if (id != event.eventId) byId(id),
    ].whereType<TimelineEvent>().toList();

    final sameProvider = pool
        .where(
          (e) =>
              e.eventId != event.eventId &&
              e.providerName.isNotEmpty &&
              e.providerName == event.providerName,
        )
        .take(3)
        .toList();

    final sameProcess = event.hasProcessId
        ? pool
            .where(
              (e) =>
                  e.eventId != event.eventId &&
                  e.hasProcessId &&
                  e.processId == event.processId,
            )
            .take(3)
            .toList()
        : const <TimelineEvent>[];

    Widget link(String label, TimelineEvent target) {
      return TextButton(
        onPressed: () => onSelect(target),
        child: Text(
          '$label · ${target.displayTitle}',
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (related.isEmpty && sameProvider.isEmpty && sameProcess.isEmpty)
          Text(
            'No related events in the current Timeline view.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PulseTokens.textTertiary,
                ),
          ),
        for (var i = 0; i < related.length; i++)
          link(i == 0 ? 'Previous related' : 'Next related', related[i]),
        for (final e in sameProvider) link('Same provider', e),
        for (final e in sameProcess) link('Same process', e),
        if (relatedIds.length > 1)
          Text(
            'Same incident · ${relatedIds.length} events',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: PulseTokens.textTertiary,
                ),
          ),
      ],
    );
  }
}

class _RawXmlSection extends StatelessWidget {
  const _RawXmlSection({
    required this.loading,
    required this.error,
    required this.xml,
    required this.onLoad,
    required this.loaded,
  });

  final bool loading;
  final String? error;
  final String? xml;
  final VoidCallback onLoad;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    if (!loaded && !loading) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onLoad,
          icon: const Icon(LucideIcons.fileCode, size: 16),
          label: const Text('Load Event XML'),
        ),
      );
    }
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Loading Event XML…'),
          ],
        ),
      );
    }
    if (error != null && (xml == null || xml!.isEmpty)) {
      return Text(
        error!,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: PulseTokens.severityWarning,
              height: 1.4,
            ),
      );
    }
    final text = xml ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: 'Copy XML',
            onPressed: text.isEmpty
                ? null
                : () => Clipboard.setData(ClipboardData(text: text)),
            icon: const Icon(LucideIcons.copy, size: 16),
          ),
        ),
        _OriginalMessageBox(message: text.isEmpty ? '(empty)' : text),
      ],
    );
  }
}

class _DetailsHeader extends StatelessWidget {
  const _DetailsHeader({
    required this.onClose,
    required this.bookmarked,
    required this.pinned,
    required this.onToggleBookmark,
    required this.onTogglePin,
  });

  final VoidCallback onClose;
  final bool bookmarked;
  final bool pinned;
  final VoidCallback onToggleBookmark;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
      child: Row(
        children: [
          Text(
            'Event Details',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 15,
                ),
          ),
          const Spacer(),
          IconButton(
            tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark',
            onPressed: onToggleBookmark,
            icon: Icon(
              bookmarked ? LucideIcons.bookmarkCheck : LucideIcons.bookmark,
              size: 17,
            ),
          ),
          IconButton(
            tooltip: pinned ? 'Unpin' : 'Pin',
            onPressed: onTogglePin,
            icon: Icon(
              pinned ? LucideIcons.pinOff : LucideIcons.pin,
              size: 17,
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

class _OverviewChip extends StatelessWidget {
  const _OverviewChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: PulseTokens.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: PulseTokens.strokeSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: PulseTokens.textTertiary),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PulseTokens.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _OriginalMessageBox extends StatelessWidget {
  const _OriginalMessageBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PulseTokens.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        border: Border.all(color: PulseTokens.strokeSubtle),
      ),
      child: SelectableText(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: PulseTokens.textSecondary,
              height: 1.45,
              fontFamily: 'Consolas',
            ),
      ),
    );
  }
}
