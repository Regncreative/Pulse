import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/pulse_theme.dart';
import '../../ipc/pulse_ipc_client.dart';
import 'connection_indicator.dart';
import 'safe_hover.dart';

class PulseAppBar extends StatelessWidget {
  const PulseAppBar({
    super.key,
    required this.title,
    required this.connectionState,
    required this.connectionLabel,
    this.actions,
    this.searchHint,
    this.searchQuery,
    this.onSearchChanged,
    this.searchEnabled = false,
  });

  final String title;
  final IpcConnectionState connectionState;
  final String connectionLabel;
  final List<Widget>? actions;
  final String? searchHint;
  final String? searchQuery;
  final ValueChanged<String>? onSearchChanged;
  final bool searchEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        PulseTokens.pagePadX,
        12,
        28,
        12,
      ),
      decoration: BoxDecoration(
        color: PulseTokens.canvas.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(color: PulseTokens.strokeSubtle),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 20,
                        letterSpacing: -0.3,
                      ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConnectionIndicator(
                      state: connectionState,
                      label: connectionLabel,
                      compact: MediaQuery.sizeOf(context).width < 1100,
                    ),
                  ),
                ),
                if (actions != null && actions!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ...actions!,
                ],
              ],
            ),
          ),
          if (searchHint != null || searchEnabled) ...[
            const SizedBox(height: 12),
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
}

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.hint,
    required this.enabled,
    required this.query,
    this.onChanged,
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
