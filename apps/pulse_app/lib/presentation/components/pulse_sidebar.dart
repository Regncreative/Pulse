import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/pulse_theme.dart';
import 'safe_hover.dart';

class PulseNavItem {
  const PulseNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class PulseSidebar extends StatelessWidget {
  const PulseSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
    this.pinnedItem,
    this.pinnedIndex,
    this.footer,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<PulseNavItem> items;

  /// Optional nav item pinned above the footer (e.g. Assistant).
  final PulseNavItem? pinnedItem;
  final int? pinnedIndex;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final width = wide ? PulseTokens.sidebarWidth : PulseTokens.sidebarNarrow;

    return AnimatedContainer(
      duration: PulseTokens.motionNormal,
      curve: PulseTokens.motionCurve,
      width: width,
      decoration: BoxDecoration(
        color: PulseTokens.sidebarSolid,
        border: Border(
          right: BorderSide(color: PulseTokens.strokeSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(PulseTokens.radiusIconWell),
                  child: SvgPicture.asset(
                    'assets/branding/app_icon.svg',
                    width: 34,
                    height: 34,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pulse',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 16,
                              letterSpacing: -0.2,
                            ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Windows diagnostics',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: PulseTokens.textTertiary,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'WORKSPACE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.9,
                    fontSize: 10.5,
                    color: PulseTokens.textDisabled,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final selected = index == selectedIndex;
                return _SidebarTile(
                  item: item,
                  selected: selected,
                  onTap: () => onSelected(index),
                );
              },
            ),
          ),
          if (pinnedItem != null && pinnedIndex != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Divider(
                height: 1,
                color: PulseTokens.strokeSubtle.withValues(alpha: 0.9),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: _SidebarTile(
                item: pinnedItem!,
                selected: selectedIndex == pinnedIndex,
                onTap: () => onSelected(pinnedIndex!),
              ),
            ),
          ],
          if (footer != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Divider(
                height: 1,
                color: PulseTokens.strokeSubtle.withValues(alpha: 0.9),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: footer!,
            ),
          ],
        ],
      ),
    );
  }
}

class _SidebarTile extends StatefulWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final PulseNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> with SafeHoverState {
  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? PulseTokens.accentSoft
        : hover
            ? PulseTokens.surfaceHover.withValues(alpha: 0.45)
            : Colors.transparent;
    final fg = widget.selected ? PulseTokens.accent : PulseTokens.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.item.label,
        child: AnimatedContainer(
          duration: MediaQuery.maybeOf(context)?.disableAnimations == true
              ? Duration.zero
              : PulseTokens.motionFast,
          curve: PulseTokens.motionCurve,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
            border: widget.selected
                ? Border.all(color: PulseTokens.accent.withValues(alpha: 0.22))
                : Border.all(color: Colors.transparent),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              onHover: setHovered,
              borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
              splashColor: PulseTokens.accent.withValues(alpha: 0.08),
              mouseCursor: SystemMouseCursors.click,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    Icon(
                      widget.selected
                          ? widget.item.selectedIcon
                          : widget.item.icon,
                      size: PulseTokens.iconNav,
                      color: fg,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.item.label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: widget.selected
                                  ? PulseTokens.textPrimary
                                  : PulseTokens.textSecondary,
                              fontWeight: widget.selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                      ),
                    ),
                    if (widget.selected)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: PulseTokens.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
