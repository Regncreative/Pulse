import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../../app/theme/pulse_theme.dart';
import '../../../presentation/components/pulse_badge.dart';
import '../timeline_display.dart';
import 'detail_section.dart';
import 'metadata_table.dart';

/// Right-side Event Details panel. Uses IPC [TimelineEvent] only — no extra fetch.
class TimelineDetailsPanel extends StatelessWidget {
  const TimelineDetailsPanel({
    super.key,
    required this.event,
    required this.onClose,
  });

  final TimelineEvent event;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final style = event.severityVisual;

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
          _DetailsHeader(onClose: onClose),
          const Divider(height: 1, color: PulseTokens.strokeSubtle),
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
                const Divider(height: 1, color: PulseTokens.strokeSubtle),
                DetailSection(
                  title: 'Technical Information',
                  child: MetadataTable(
                    entries: [
                      MetadataEntry('Provider', event.providerName),
                      MetadataEntry(
                        'Event ID',
                        event.winEventId == 0
                            ? ''
                            : event.winEventId.toString(),
                      ),
                      MetadataEntry('Channel', event.displayChannel),
                      MetadataEntry('Computer Name', event.computerName),
                      MetadataEntry(
                        'Record ID',
                        event.recordId == 0 ? '' : event.recordId.toString(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: PulseTokens.strokeSubtle),
                DetailSection(
                  title: 'Original Windows Message',
                  child: _OriginalMessageBox(
                    message: event.message.isNotEmpty
                        ? event.message
                        : 'No original Event Viewer message was available for this entry.',
                  ),
                ),
                const Divider(height: 1, color: PulseTokens.strokeSubtle),
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
                          entries: [
                            MetadataEntry('Provider', event.providerName),
                            MetadataEntry(
                              'Event ID',
                              event.winEventId == 0
                                  ? '—'
                                  : event.winEventId.toString(),
                            ),
                            MetadataEntry('Channel', event.displayChannel),
                            MetadataEntry(
                              'Timestamp ISO',
                              event.timestampIso.isEmpty
                                  ? '—'
                                  : event.timestampIso,
                            ),
                            MetadataEntry(
                              'Timestamp Unix',
                              event.timestampUnixMs == 0
                                  ? '—'
                                  : event.timestampUnixMs.toString(),
                            ),
                            MetadataEntry(
                              'Computer',
                              event.computerName.isEmpty
                                  ? '—'
                                  : event.computerName,
                            ),
                            MetadataEntry(
                              'Record ID',
                              event.recordId == 0
                                  ? '—'
                                  : event.recordId.toString(),
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
        ],
      ),
    );
  }
}

class _DetailsHeader extends StatelessWidget {
  const _DetailsHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
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

class _OriginalMessageBox extends StatefulWidget {
  const _OriginalMessageBox({required this.message});

  final String message;

  @override
  State<_OriginalMessageBox> createState() => _OriginalMessageBoxState();
}

class _OriginalMessageBoxState extends State<_OriginalMessageBox> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 260, minHeight: 96),
      decoration: BoxDecoration(
        color: PulseTokens.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        border: Border.all(color: PulseTokens.strokeSubtle),
      ),
      child: Scrollbar(
        controller: _controller,
        child: SingleChildScrollView(
          controller: _controller,
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            widget.message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'Consolas',
                  color: PulseTokens.textSecondary,
                  height: 1.55,
                ),
          ),
        ),
      ),
    );
  }
}

/// Animated host that expands the details panel beside the timeline list.
class TimelineDetailsHost extends StatelessWidget {
  const TimelineDetailsHost({
    super.key,
    required this.expanded,
    required this.width,
    required this.event,
    required this.onClose,
  });

  final bool expanded;
  final double width;
  final TimelineEvent? event;
  final VoidCallback onClose;

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
          child: event == null
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
                    key: ValueKey(
                      event!.eventId.isNotEmpty
                          ? event!.eventId
                          : event!.displayTitle,
                    ),
                    child: TimelineDetailsPanel(
                      event: event!,
                      onClose: onClose,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
