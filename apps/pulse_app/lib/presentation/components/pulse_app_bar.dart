import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/pulse_theme.dart';
import '../../ipc/pulse_ipc_client.dart';
import 'connection_indicator.dart';
import 'pulse_button.dart';
import 'pulse_header_action.dart';
import 'safe_hover.dart';

export 'pulse_header_action.dart';

class PulseAppBar extends StatelessWidget {
  const PulseAppBar({
    super.key,
    required this.title,
    required this.connectionState,
    required this.connectionLabel,
    this.actions,
    this.headerActions,
    this.searchHint,
    this.searchQuery,
    this.onSearchChanged,
    this.searchEnabled = false,
  });

  final String title;
  final IpcConnectionState connectionState;
  final String connectionLabel;

  /// Legacy widget actions (not auto-responsive). Prefer [headerActions].
  final List<Widget>? actions;

  /// Overflow-safe actions laid out by density (full → partial → icons → ⋯).
  final List<PulseHeaderAction>? headerActions;

  final String? searchHint;
  final String? searchQuery;
  final ValueChanged<String>? onSearchChanged;
  final bool searchEnabled;

  @override
  Widget build(BuildContext context) {
    // Rebuild with Material theme animation frames.
    Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        PulseTokens.pagePadX,
        10,
        PulseTokens.pagePadX,
        10,
      ),
      decoration: BoxDecoration(
        color: PulseTokens.header.withValues(alpha: 0.72),
        border: Border(
          bottom: BorderSide(color: PulseTokens.divider),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final windowW = MediaQuery.sizeOf(context).width;
              final narrowBadge = windowW < 1100;
              final actionSlot = _resolveActions(
                context: context,
                windowWidth: windowW,
                barWidth: constraints.maxWidth,
              );
              return SizedBox(
                height: 36,
                child: Row(
                  children: [
                    // Title + connection shrink first; actions keep intrinsic width.
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontSize: 20,
                                    letterSpacing: -0.3,
                                    color: PulseTokens.primaryText,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ConnectionIndicator(
                                state: connectionState,
                                label: connectionLabel,
                                compact: narrowBadge,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (actionSlot != null) ...[
                      const SizedBox(width: 8),
                      actionSlot,
                    ],
                  ],
                ),
              );
            },
          ),
          if (searchHint != null || searchEnabled) ...[
            const SizedBox(height: 10),
            _SearchField(
              hint: searchHint ?? 'Search events…',
              enabled: searchEnabled,
              query: searchQuery ?? '',
              onChanged: onSearchChanged,
            ),
          ],
        ],
      ),
    );
  }

  Widget? _resolveActions({
    required BuildContext context,
    required double windowWidth,
    required double barWidth,
  }) {
    final declarative = headerActions;
    if (declarative != null && declarative.isNotEmpty) {
      final density = _ActionDensity.resolve(
        windowWidth: windowWidth,
        barWidth: barWidth,
        actionCount: declarative.length,
      );
      return _HeaderActionStrip(actions: declarative, density: density);
    }
    if (actions == null || actions!.isEmpty) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actions!.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          actions![i],
        ],
      ],
    );
  }
}

enum _ActionDensity {
  /// ≥1400 — all labels.
  full,

  /// 1200–1400 — collapseFirst → icon; others labeled.
  partial,

  /// 1000–1200 — all icons + tooltips.
  icons,

  /// <1000 — overflow menu.
  overflow;

  static _ActionDensity resolve({
    required double windowWidth,
    required double barWidth,
    required int actionCount,
  }) {
    var density = switch (windowWidth) {
      >= 1400 => _ActionDensity.full,
      >= 1200 => _ActionDensity.partial,
      >= 1000 => _ActionDensity.icons,
      _ => _ActionDensity.overflow,
    };

    // Available bar width can be tighter than the window (sidebar + padding).
    // Escalate collapse so actions never clip the title row.
    final budget = barWidth * 0.42;
    final fullNeed = actionCount * 108.0;
    final partialNeed = actionCount * 78.0;
    final iconsNeed = actionCount * 44.0;

    if (density == _ActionDensity.full && budget < fullNeed) {
      density = _ActionDensity.partial;
    }
    if (density == _ActionDensity.partial && budget < partialNeed) {
      density = _ActionDensity.icons;
    }
    if ((density == _ActionDensity.icons ||
            density == _ActionDensity.partial ||
            density == _ActionDensity.full) &&
        budget < iconsNeed) {
      density = _ActionDensity.overflow;
    }
    return density;
  }
}

class _HeaderActionStrip extends StatelessWidget {
  const _HeaderActionStrip({
    required this.actions,
    required this.density,
  });

  final List<PulseHeaderAction> actions;
  final _ActionDensity density;

  @override
  Widget build(BuildContext context) {
    if (density == _ActionDensity.overflow) {
      return _OverflowActionsButton(actions: actions);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _buildButton(actions[i]),
        ],
      ],
    );
  }

  Widget _buildButton(PulseHeaderAction action) {
    final iconOnly = switch (density) {
      _ActionDensity.full => false,
      _ActionDensity.partial => action.collapseFirst,
      _ActionDensity.icons => true,
      _ActionDensity.overflow => true,
    };
    return PulseButton(
      label: action.label,
      icon: action.icon,
      variant: PulseButtonVariant.secondary,
      dense: true,
      iconOnly: iconOnly,
      tooltip: action.tooltip ?? action.label,
      onPressed: action.onPressed,
    );
  }
}

class _OverflowActionsButton extends StatelessWidget {
  const _OverflowActionsButton({required this.actions});

  final List<PulseHeaderAction> actions;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'More actions',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        side: BorderSide(color: PulseTokens.stroke),
      ),
      color: PulseTokens.surfaceElevated,
      onSelected: (index) => actions[index].onPressed?.call(),
      itemBuilder: (context) {
        return [
          for (var i = 0; i < actions.length; i++)
            PopupMenuItem<int>(
              value: i,
              enabled: actions[i].onPressed != null,
              child: Row(
                children: [
                  Icon(
                    actions[i].icon,
                    size: 16,
                    color: actions[i].onPressed == null
                        ? PulseTokens.textDisabled
                        : PulseTokens.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Text(actions[i].label),
                ],
              ),
            ),
        ];
      },
      child: Tooltip(
        message: 'More actions',
        child: Material(
          color: PulseTokens.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
            side: BorderSide(color: PulseTokens.stroke),
          ),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              LucideIcons.ellipsis,
              size: 16,
              color: PulseTokens.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.hint,
    required this.enabled,
    required this.query,
    required this.onChanged,
  });

  final String hint;
  final bool enabled;
  final String query;
  final ValueChanged<String>? onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> with SafeHoverState {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
    _focus = FocusNode()..addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant _SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.text = widget.query;
      _controller.selection = TextSelection.collapsed(
        offset: widget.query.length,
      );
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return MouseRegion(
      onEnter: (_) => setHovered(true),
      onExit: (_) => setHovered(false),
      child: AnimatedContainer(
        duration: PulseTokens.motionFast,
        height: 36,
        decoration: BoxDecoration(
          color: !widget.enabled
              ? PulseTokens.surface.withValues(alpha: 0.55)
              : focused || hover
                  ? PulseTokens.surfaceHover.withValues(alpha: 0.45)
                  : PulseTokens.surface,
          borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
          border: Border.all(
            color: focused && widget.enabled
                ? PulseTokens.accent.withValues(alpha: 0.45)
                : PulseTokens.stroke.withValues(alpha: 0.65),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              LucideIcons.search,
              size: 15,
              color: widget.enabled
                  ? PulseTokens.textTertiary
                  : PulseTokens.textDisabled,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: widget.enabled
                  ? TextField(
                      controller: _controller,
                      focusNode: _focus,
                      onChanged: widget.onChanged,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: PulseTokens.textPrimary,
                            fontSize: 13.5,
                          ),
                      cursorColor: PulseTokens.accent,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: widget.hint,
                        hintStyle:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: PulseTokens.textTertiary,
                                  fontSize: 13.5,
                                ),
                      ),
                    )
                  : Text(
                      widget.hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: PulseTokens.textTertiary,
                          ),
                    ),
            ),
            if (widget.enabled && widget.query.isNotEmpty)
              IconButton(
                tooltip: 'Clear search',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged?.call('');
                },
                icon: Icon(
                  LucideIcons.x,
                  size: 14,
                  color: PulseTokens.textTertiary,
                ),
              )
            else if (!widget.enabled)
              Text(
                'Unavailable',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: PulseTokens.textDisabled,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}
