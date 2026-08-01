import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/pulse_theme.dart';

/// A single actionable entry in the command palette.
class PulseCommand {
  const PulseCommand({
    required this.id,
    required this.title,
    required this.icon,
    required this.onInvoke,
    this.subtitle,
    this.keywords = const [],
  });

  final String id;
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<String> keywords;
  final VoidCallback onInvoke;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (title.toLowerCase().contains(q)) return true;
    if (subtitle != null && subtitle!.toLowerCase().contains(q)) return true;
    for (final keyword in keywords) {
      if (keyword.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

/// Opens the modal command palette. Returns when dismissed.
Future<void> showCommandPalette(
  BuildContext context, {
  String initialQuery = '',
  required List<PulseCommand> commands,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss command palette',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: MediaQuery.maybeOf(context)?.disableAnimations == true
        ? Duration.zero
        : PulseTokens.motionFast,
    pageBuilder: (context, animation, secondaryAnimation) {
      return _CommandPaletteDialog(
        initialQuery: initialQuery,
        commands: commands,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: PulseTokens.motionEmphasized,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({
    required this.initialQuery,
    required this.commands,
  });

  final String initialQuery;
  final List<PulseCommand> commands;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<PulseCommand> get _filtered {
    return widget.commands
        .where((c) => c.matches(_controller.text))
        .toList(growable: false);
  }

  void _moveSelection(int delta) {
    final items = _filtered;
    if (items.isEmpty) return;
    setState(() {
      _selectedIndex =
          (_selectedIndex + delta).clamp(0, items.length - 1).toInt();
    });
  }

  void _invokeSelected() {
    final items = _filtered;
    if (items.isEmpty) return;
    final index = _selectedIndex.clamp(0, items.length - 1);
    final command = items[index];
    Navigator.of(context).pop();
    // Defer so the dialog route fully pops before navigation side-effects.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      command.onInvoke();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _invokeSelected();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    if (_selectedIndex >= items.length) {
      _selectedIndex = items.isEmpty ? 0 : items.length - 1;
    }

    return Center(
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 440),
          child: Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: PulseTokens.surfaceElevated,
                borderRadius: BorderRadius.circular(PulseTokens.radiusXl),
                border: Border.all(
                  color: PulseTokens.stroke.withValues(alpha: 0.7),
                ),
                boxShadow: PulseTokens.elevationLift,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.search,
                          size: 18,
                          color: PulseTokens.textTertiary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: PulseTokens.textPrimary,
                                  fontSize: 15,
                                ),
                            cursorColor: PulseTokens.accent,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Type a command…',
                              hintStyle: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: PulseTokens.textTertiary,
                                    fontSize: 15,
                                  ),
                            ),
                            onChanged: (_) {
                              setState(() => _selectedIndex = 0);
                            },
                            onSubmitted: (_) => _invokeSelected(),
                          ),
                        ),
                        Text(
                          'Esc',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: PulseTokens.textDisabled,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: PulseTokens.strokeSubtle,
                  ),
                  Flexible(
                    child: items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              'No matching commands',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: PulseTokens.textTertiary,
                                  ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 6,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final command = items[index];
                              final selected = index == _selectedIndex;
                              return _CommandTile(
                                command: command,
                                selected: selected,
                                onTap: () {
                                  setState(() => _selectedIndex = index);
                                  _invokeSelected();
                                },
                                onHover: () {
                                  if (_selectedIndex != index) {
                                    setState(() => _selectedIndex = index);
                                  }
                                },
                              );
                            },
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

class _CommandTile extends StatelessWidget {
  const _CommandTile({
    required this.command,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final PulseCommand command;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Material(
        color: selected
            ? PulseTokens.accentSoft
            : Colors.transparent,
        borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  command.icon,
                  size: 16,
                  color: selected
                      ? PulseTokens.accent
                      : PulseTokens.textTertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        command.title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: PulseTokens.textPrimary,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                      ),
                      if (command.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          command.subtitle!,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: PulseTokens.textTertiary,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    LucideIcons.cornerDownLeft,
                    size: 14,
                    color: PulseTokens.textDisabled,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
