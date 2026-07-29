import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/pulse_theme.dart';
import '../components/pulse_badge.dart';
import '../components/pulse_card.dart';
import 'health_view_models.dart';

/// Top-of-page posture card — primary entry for System Health (TASK-007.1).
class HealthSystemStatusCard extends StatelessWidget {
  const HealthSystemStatusCard({
    super.key,
    required this.summary,
    this.uptime,
    this.healthScore,
    this.lastUpdated,
    this.compact = false,
  });

  final SystemStatusSummary summary;
  final String? uptime;
  final String? healthScore;
  final String? lastUpdated;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (dot, soft, icon) = switch (summary.level) {
      SystemStatusLevel.healthy => (
          PulseTokens.success,
          PulseTokens.successSoft,
          LucideIcons.shieldCheck,
        ),
      SystemStatusLevel.attention => (
          PulseTokens.warning,
          PulseTokens.warningSoft,
          LucideIcons.shieldAlert,
        ),
      SystemStatusLevel.critical => (
          PulseTokens.error,
          PulseTokens.errorSoft,
          LucideIcons.shieldX,
        ),
    };

    final hasMeta = uptime != null || healthScore != null || lastUpdated != null;
    final pad = compact
        ? const EdgeInsets.fromLTRB(14, 10, 14, 10)
        : const EdgeInsets.fromLTRB(20, 18, 20, 18);
    final iconBox = compact ? 40.0 : 48.0;

    return PulseCard(
      elevated: true,
      padding: pad,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: iconBox,
            height: iconBox,
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(PulseTokens.radiusCard),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: compact ? 18 : 22, color: dot),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  summary.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: PulseTokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        fontSize: compact ? 15 : null,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: PulseTokens.textSecondary,
                        height: 1.3,
                        fontSize: compact ? 12.5 : null,
                      ),
                ),
              ],
            ),
          ),
          if (hasMeta) ...[
            const SizedBox(width: 16),
            _StatusMetaColumn(
              uptime: uptime,
              healthScore: healthScore,
              lastUpdated: lastUpdated,
              compact: compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusMetaColumn extends StatelessWidget {
  const _StatusMetaColumn({
    this.uptime,
    this.healthScore,
    this.lastUpdated,
    this.compact = false,
  });

  final String? uptime;
  final String? healthScore;
  final String? lastUpdated;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (uptime != null) ('Uptime', uptime!),
      if (healthScore != null) ('Health Score', healthScore!),
      if (lastUpdated != null) ('Last Updated', lastUpdated!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 4 : 8),
          _StatusMetaRow(
            label: rows[i].$1,
            value: rows[i].$2,
            compact: compact,
          ),
        ],
      ],
    );
  }
}

class _StatusMetaRow extends StatelessWidget {
  const _StatusMetaRow({
    required this.label,
    required this.value,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: PulseTokens.textTertiary,
                fontWeight: FontWeight.w500,
                fontSize: compact ? 10.5 : null,
              ),
        ),
        SizedBox(width: compact ? 8 : 12),
        Text(
          value,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: PulseTokens.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: compact ? 11.5 : null,
              ),
        ),
      ],
    );
  }
}

/// Compact primary metric — optional progress for memory/CPU.
class HealthHeroCard extends StatelessWidget {
  const HealthHeroCard({
    super.key,
    required this.metric,
    this.selected = false,
    this.onTap,
    this.compact = false,
  });

  final HealthMetric metric;
  final bool selected;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final progress = metric.progress;
    final pad = compact
        ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
        : const EdgeInsets.fromLTRB(16, 14, 16, 14);
    final valueSize = compact ? 20.0 : 28.0;
    final sparkH = compact ? 22.0 : 36.0;

    return PulseCard(
      elevated: true,
      selected: selected,
      onTap: onTap,
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!compact) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: PulseTokens.accentSoft,
                    borderRadius: BorderRadius.circular(PulseTokens.radiusLg),
                  ),
                  child: Icon(
                    metric.icon,
                    size: 15,
                    color: PulseTokens.accent,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  metric.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: PulseTokens.textSecondary,
                        fontWeight: FontWeight.w500,
                        fontSize: compact ? 11.5 : null,
                      ),
                ),
              ),
              if (metric.needsAttention && !compact)
                PulseBadge(
                  label: metric.attentionLabel ??
                      (metric.status == HealthStatus.elevated
                          ? 'High Usage'
                          : 'Fair'),
                  tone: metric.status == HealthStatus.elevated
                      ? PulseBadgeTone.error
                      : PulseBadgeTone.warning,
                  compact: true,
                ),
            ],
          ),
          SizedBox(height: compact ? 6 : 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: metric.value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontSize: valueSize,
                        letterSpacing: -0.8,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: PulseTokens.textPrimary,
                      ),
                ),
                if (metric.unit.isNotEmpty)
                  TextSpan(
                    text: ' ${metric.unit}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: PulseTokens.textTertiary,
                          fontWeight: FontWeight.w500,
                          fontSize: compact ? 11 : 14,
                        ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (!compact && metric.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              metric.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PulseTokens.textTertiary,
                    height: 1.3,
                    fontSize: 12,
                  ),
            ),
          ],
          if (compact && metric.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              metric.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PulseTokens.textTertiary,
                    height: 1.2,
                    fontSize: 10.5,
                  ),
            ),
          ],
          const Spacer(),
          if (progress != null)
            _HealthProgressBar(
              value: progress,
              tone: metric.status,
            )
          else if (metric.sparkline.length >= 2)
            SizedBox(
              height: sparkH,
              width: double.infinity,
              child: CustomPaint(
                painter: HealthSparklinePainter(
                  values: metric.sparkline,
                  color: PulseTokens.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HealthProgressBar extends StatelessWidget {
  const _HealthProgressBar({required this.value, required this.tone});

  final double value;
  final HealthStatus tone;

  @override
  Widget build(BuildContext context) {
    final fill = switch (tone) {
      HealthStatus.elevated => PulseTokens.error,
      HealthStatus.fair => PulseTokens.warning,
      _ => PulseTokens.accent,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(PulseTokens.radiusPill),
      child: SizedBox(
        height: 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: PulseTokens.strokeSubtle),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(color: fill),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact system identity chip.
class HealthSummaryChip extends StatelessWidget {
  const HealthSummaryChip({
    super.key,
    required this.item,
    this.compact = false,
  });

  final HealthInfoItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 10,
      ),
      decoration: BoxDecoration(
        color: PulseTokens.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(PulseTokens.radiusPill),
        border: Border.all(color: PulseTokens.stroke.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.icon,
            size: compact ? 12 : 14,
            color: PulseTokens.textTertiary,
          ),
          SizedBox(width: compact ? 6 : 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 200 : 240),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${item.label}  ',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: PulseTokens.textDisabled,
                          fontWeight: FontWeight.w600,
                          fontSize: compact ? 10.5 : null,
                        ),
                  ),
                  TextSpan(
                    text: item.value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: PulseTokens.textSecondary,
                          fontWeight: FontWeight.w500,
                          fontSize: compact ? 11.5 : null,
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
    );
  }
}

/// Monitoring-style sparkline tile inside Performance.
class HealthSparklineTile extends StatelessWidget {
  const HealthSparklineTile({
    super.key,
    required this.metric,
    this.selected = false,
    this.onTap,
    this.fillHeight = false,
  });

  final HealthMetric metric;
  final bool selected;
  final VoidCallback? onTap;
  final bool fillHeight;

  static const double sparklineHeight = 94;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? PulseTokens.accent.withValues(alpha: 0.7)
        : PulseTokens.strokeSubtle;
    final bg = selected
        ? PulseTokens.accentSoft
        : PulseTokens.surface.withValues(alpha: 0.55);

    final content = Padding(
      padding: EdgeInsets.fromLTRB(12, fillHeight ? 10 : 12, 12, fillHeight ? 8 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  metric.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: PulseTokens.textTertiary,
                        fontSize: fillHeight ? 11.5 : null,
                      ),
                ),
              ),
              Text(
                metric.unit.isEmpty
                    ? metric.value
                    : '${metric.value} ${metric.unit}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: PulseTokens.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: fillHeight ? 12.5 : null,
                    ),
              ),
            ],
          ),
          SizedBox(height: fillHeight ? 6 : 10),
          if (fillHeight)
            Expanded(
              child: CustomPaint(
                painter: HealthSparklinePainter(
                  values: metric.sparkline,
                  color: PulseTokens.accent,
                ),
                child: const SizedBox.expand(),
              ),
            )
          else
            SizedBox(
              height: sparklineHeight,
              width: double.infinity,
              child: CustomPaint(
                painter: HealthSparklinePainter(
                  values: metric.sparkline,
                  color: PulseTokens.accent,
                ),
              ),
            ),
        ],
      ),
    );

    return AnimatedContainer(
      duration: PulseTokens.motionNormal,
      curve: PulseTokens.motionCurve,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
      ),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
                splashColor: PulseTokens.accent.withValues(alpha: 0.08),
                highlightColor: PulseTokens.accent.withValues(alpha: 0.04),
                mouseCursor: SystemMouseCursors.click,
                child: content,
              ),
            ),
    );
  }
}

/// One grouped card for Hardware / Storage / Network detail rows.
class HealthGroupedCard extends StatelessWidget {
  const HealthGroupedCard({
    super.key,
    required this.title,
    required this.icon,
    required this.rows,
    this.selected = false,
    this.onTap,
    this.compact = false,
  });

  final String title;
  final IconData icon;
  final List<HealthDetailRow> rows;
  final bool selected;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PulseCard(
      elevated: true,
      selected: selected,
      onTap: onTap,
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 20,
        compact ? 10 : 18,
        compact ? 12 : 20,
        compact ? 4 : 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: compact ? 14 : 18, color: PulseTokens.accent),
              SizedBox(width: compact ? 8 : 10),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: compact ? 13.5 : null,
                    ),
              ),
            ],
          ),
          SizedBox(height: compact ? 2 : 6),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: PulseTokens.strokeSubtle),
                  Expanded(
                    child: _DetailRow(row: rows[i], compact: compact),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.row, this.compact = false});

  final HealthDetailRow row;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final display = row.available
        ? row.value
        : (row.value == kNotSupported || row.value == kUnavailableDash
            ? kNotSupported
            : row.value);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 4 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  row.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: PulseTokens.textTertiary,
                        fontSize: compact ? 11.5 : null,
                      ),
                ),
              ),
              SizedBox(width: compact ? 8 : 16),
              Expanded(
                flex: 3,
                child: Text(
                  display,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: row.available
                            ? PulseTokens.textPrimary
                            : PulseTokens.textDisabled,
                        fontWeight:
                            row.available ? FontWeight.w500 : FontWeight.w400,
                        fontSize: compact ? 11.5 : null,
                      ),
                ),
              ),
            ],
          ),
          if (row.progress != null) ...[
            SizedBox(height: compact ? 6 : 10),
            _HealthProgressBar(
              value: row.progress!,
              tone: statusFromPercent(row.progress! * 100),
            ),
          ],
        ],
      ),
    );
  }
}

class HealthSparklinePainter extends CustomPainter {
  HealthSparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 0.0001 ? 1.0 : (maxV - minV);
    const padY = 4.0;

    Offset pointAt(int i) {
      final x = size.width * (i / (values.length - 1));
      final n = (values[i] - minV) / range;
      final y = size.height - padY - (n * (size.height - padY * 2));
      return Offset(x, y);
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(pointAt(i).dx, pointAt(i).dy);
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.75
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant HealthSparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}

/// Responsive card grid: 4 → 2 → 1 columns as width shrinks.
class HealthCardGrid extends StatelessWidget {
  const HealthCardGrid({
    super.key,
    required this.children,
    this.minCardWidth = 220,
    this.maxColumns = 4,
  });

  final List<Widget> children;
  final double minCardWidth;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const gap = 14.0;

        final int columns;
        if (width < 560) {
          columns = 1;
        } else if (width < 900) {
          columns = 2.clamp(1, maxColumns);
        } else {
          final fitted = (width / (minCardWidth + gap))
              .floor()
              .clamp(1, maxColumns);
          columns =
              fitted >= maxColumns ? maxColumns : fitted.clamp(2, maxColumns);
        }

        final cardWidth = (width - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: cardWidth, child: child),
          ],
        );
      },
    );
  }
}
