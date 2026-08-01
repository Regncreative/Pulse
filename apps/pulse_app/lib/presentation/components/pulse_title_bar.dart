import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/theme/pulse_theme.dart';
import 'safe_hover.dart';

/// Native-feeling custom title bar that blends into Pulse chrome.
class PulseTitleBar extends StatefulWidget {
  const PulseTitleBar({
    super.key,
    this.onOpenSearch,
  });

  /// Opens the global command palette (title-bar search affordance).
  final VoidCallback? onOpenSearch;

  @override
  State<PulseTitleBar> createState() => _PulseTitleBarState();
}

class _PulseTitleBarState extends State<PulseTitleBar> with WindowListener {
  bool _maximized = false;
  bool _focused = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refresh();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    final maximized = await windowManager.isMaximized();
    final focused = await windowManager.isFocused();
    if (!mounted) return;
    if (_maximized == maximized && _focused == focused) return;
    setState(() {
      _maximized = maximized;
      _focused = focused;
    });
  }

  @override
  void onWindowMaximize() => _refresh();

  @override
  void onWindowUnmaximize() => _refresh();

  @override
  void onWindowRestore() => _refresh();

  @override
  void onWindowFocus() => _refresh();

  @override
  void onWindowBlur() => _refresh();

  @override
  Widget build(BuildContext context) {
    final fg = _focused ? PulseTokens.textPrimary : PulseTokens.textTertiary;

    return DragToMoveArea(
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: PulseTokens.sidebarSolid,
          border: Border(
            bottom: BorderSide(color: PulseTokens.strokeSubtle),
          ),
        ),
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/branding/mark.svg',
              width: 16,
              height: 16,
            ),
            const SizedBox(width: 10),
            Text(
              'Pulse',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    fontSize: 13,
                  ),
            ),
            const Spacer(),
            if (widget.onOpenSearch != null) ...[
              _TitleSearchButton(
                color: fg,
                onPressed: widget.onOpenSearch!,
              ),
              const SizedBox(width: 4),
            ],
            _CaptionButton(
              tooltip: 'Minimize',
              onPressed: windowManager.minimize,
              icon: Icons.remove,
              color: fg,
            ),
            _CaptionButton(
              tooltip: _maximized ? 'Restore' : 'Maximize',
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              icon: _maximized ? Icons.filter_none : Icons.crop_square,
              iconSize: _maximized ? 13 : 14,
              color: fg,
            ),
            _CaptionButton(
              tooltip: 'Close',
              isClose: true,
              onPressed: windowManager.close,
              icon: Icons.close,
              color: fg,
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleSearchButton extends StatefulWidget {
  const _TitleSearchButton({
    required this.onPressed,
    required this.color,
  });

  final VoidCallback onPressed;
  final Color color;

  @override
  State<_TitleSearchButton> createState() => _TitleSearchButtonState();
}

class _TitleSearchButtonState extends State<_TitleSearchButton>
    with SafeHoverState {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Search commands (Ctrl+K)',
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: MouseRegion(
          onEnter: (_) => setHovered(true),
          onExit: (_) => setHovered(false),
          child: AnimatedContainer(
            duration: PulseTokens.motionFast,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hover
                  ? PulseTokens.surfaceHover.withValues(alpha: 0.7)
                  : PulseTokens.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
              border: Border.all(
                color: PulseTokens.stroke.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.search,
                  size: 13,
                  color: widget.color.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 8),
                Text(
                  'Search',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: widget.color.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                        fontSize: 11.5,
                      ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Ctrl+K',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: PulseTokens.textDisabled,
                        fontWeight: FontWeight.w600,
                        fontSize: 10.5,
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

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    required this.color,
    this.iconSize = 16,
    this.isClose = false,
  });

  final IconData icon;
  final Future<void> Function() onPressed;
  final String tooltip;
  final Color color;
  final double iconSize;
  final bool isClose;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> with SafeHoverState {
  @override
  Widget build(BuildContext context) {
    final bg = !hover
        ? Colors.transparent
        : widget.isClose
            ? const Color(0xFFE81123)
            : PulseTokens.surfaceHover.withValues(alpha: 0.7);
    final iconColor =
        widget.isClose && hover ? Colors.white : widget.color;

    // Avoid Tooltip + MouseRegion nesting — Tooltip already tracks the pointer.
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onPressed(),
        child: MouseRegion(
          onEnter: (_) => setHovered(true),
          onExit: (_) => setHovered(false),
          child: AnimatedContainer(
            duration: PulseTokens.motionFast,
            width: 46,
            height: 40,
            color: bg,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}
