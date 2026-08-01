import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../app/theme/pulse_theme.dart';
import '../../application/health_navigation.dart';
import '../../application/settings_controller.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../components/pulse_content_frame.dart';
import '../components/pulse_mica.dart';
import '../components/pulse_sidebar.dart';
import '../components/pulse_title_bar.dart';
import '../components/service_status_card.dart';
import '../diagnostics/diagnostics_page.dart';
import '../health/health_view_models.dart';
import '../health/system_health_page.dart';
import '../reports/reports_page.dart';
import '../settings/settings_page.dart';
import '../timeline/timeline_page.dart';
import '../utils/pulse_snack.dart';
import 'command_palette.dart';

/// Sidebar / shell page indices.
abstract final class PulseShellPages {
  static const timeline = 0;
  static const health = 1;
  static const reports = 2;
  static const diagnostics = 3;
  static const settings = 4;
  static const count = 5;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = PulseShellPages.timeline;
  bool _paletteOpen = false;

  static const _nav = [
    PulseNavItem(
      label: 'Timeline',
      icon: LucideIcons.listTree,
      selectedIcon: LucideIcons.listTree,
    ),
    PulseNavItem(
      label: 'System Health',
      icon: LucideIcons.heartPulse,
      selectedIcon: LucideIcons.heartPulse,
    ),
    PulseNavItem(
      label: 'Reports',
      icon: LucideIcons.fileText,
      selectedIcon: LucideIcons.fileText,
    ),
    PulseNavItem(
      label: 'Diagnostics',
      icon: LucideIcons.activity,
      selectedIcon: LucideIcons.activity,
    ),
    PulseNavItem(
      label: 'Settings',
      icon: LucideIcons.settings,
      selectedIcon: LucideIcons.settings,
    ),
  ];

  static const _titles = [
    'Timeline',
    'System Health',
    'Reports',
    'Diagnostics',
    'Settings',
  ];

  void _selectPage(int index) {
    if (index < 0 || index >= PulseShellPages.count) return;
    if (_index == index) return;
    setState(() => _index = index);
  }

  Future<void> _openCommandPalette({String initialQuery = ''}) async {
    if (_paletteOpen || !mounted) return;
    _paletteOpen = true;
    try {
      await showCommandPalette(
        context,
        initialQuery: initialQuery,
        commands: _buildCommands(),
      );
    } finally {
      _paletteOpen = false;
    }
  }

  List<PulseCommand> _buildCommands() {
    final settings = context.read<SettingsController>();
    final healthNav = context.read<HealthNavigation>();

    void go(int page) => _selectPage(page);

    void openHealthPanel(HealthPanelKind kind) {
      _selectPage(PulseShellPages.health);
      healthNav.openPanel(kind);
    }

    Future<void> exportSettings() async {
      try {
        final path = await settings.exportSettingsJson();
        if (!mounted) return;
        PulseSnack.success(context, 'Saved: $path');
      } catch (e) {
        if (!mounted) return;
        PulseSnack.error(context, 'Failed: $e');
      }
    }

    return [
      PulseCommand(
        id: 'nav.timeline',
        title: 'Go to Timeline',
        icon: LucideIcons.listTree,
        keywords: const ['navigate', 'page'],
        onInvoke: () => go(PulseShellPages.timeline),
      ),
      PulseCommand(
        id: 'nav.health',
        title: 'Go to System Health',
        icon: LucideIcons.heartPulse,
        keywords: const ['navigate', 'page', 'health'],
        onInvoke: () => go(PulseShellPages.health),
      ),
      PulseCommand(
        id: 'nav.reports',
        title: 'Go to Reports',
        icon: LucideIcons.fileText,
        keywords: const ['navigate', 'page', 'export'],
        onInvoke: () => go(PulseShellPages.reports),
      ),
      PulseCommand(
        id: 'nav.diagnostics',
        title: 'Go to Diagnostics',
        icon: LucideIcons.activity,
        keywords: const ['navigate', 'page'],
        onInvoke: () => go(PulseShellPages.diagnostics),
      ),
      PulseCommand(
        id: 'nav.settings',
        title: 'Go to Settings',
        icon: LucideIcons.settings,
        keywords: const ['navigate', 'page', 'preferences'],
        onInvoke: () => go(PulseShellPages.settings),
      ),
      PulseCommand(
        id: 'theme.cycle',
        title: 'Toggle theme',
        subtitle: 'Cycle light / dark / system',
        icon: LucideIcons.sun,
        keywords: const ['appearance', 'dark', 'light', 'system'],
        onInvoke: () {
          settings.cycleThemeMode();
        },
      ),
      PulseCommand(
        id: 'health.cpu',
        title: 'Open CPU panel',
        icon: LucideIcons.cpu,
        keywords: const ['health', 'panel'],
        onInvoke: () => openHealthPanel(HealthPanelKind.cpu),
      ),
      PulseCommand(
        id: 'health.memory',
        title: 'Open Memory panel',
        icon: LucideIcons.memoryStick,
        keywords: const ['health', 'panel', 'ram'],
        onInvoke: () => openHealthPanel(HealthPanelKind.memory),
      ),
      PulseCommand(
        id: 'health.gpu',
        title: 'Open GPU panel',
        icon: LucideIcons.circuitBoard,
        keywords: const ['health', 'panel'],
        onInvoke: () => openHealthPanel(HealthPanelKind.gpu),
      ),
      PulseCommand(
        id: 'health.network',
        title: 'Open Network panel',
        icon: LucideIcons.wifi,
        keywords: const ['health', 'panel'],
        onInvoke: () => openHealthPanel(HealthPanelKind.network),
      ),
      PulseCommand(
        id: 'health.disk',
        title: 'Open Disk panel',
        icon: LucideIcons.hardDrive,
        keywords: const ['health', 'panel', 'storage'],
        onInvoke: () => openHealthPanel(HealthPanelKind.disk),
      ),
      PulseCommand(
        id: 'health.hardware',
        title: 'Open Hardware panel',
        icon: LucideIcons.thermometer,
        keywords: const ['health', 'panel', 'sensors'],
        onInvoke: () => openHealthPanel(HealthPanelKind.hardware),
      ),
      PulseCommand(
        id: 'settings.export',
        title: 'Export settings',
        icon: LucideIcons.download,
        keywords: const ['backup', 'json'],
        onInvoke: () {
          exportSettings();
        },
      ),
      PulseCommand(
        id: 'search.focus',
        title: 'Focus search',
        subtitle: 'Open command palette',
        icon: LucideIcons.search,
        keywords: const ['find', 'command'],
        onInvoke: () {
          // Palette already closed; reopen empty for focus.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openCommandPalette();
          });
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Do not watch IPC here — that rebuilt the entire page tree (and every
    // MouseRegion) on each connection tick. Sidebar status is isolated below.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            () => _openCommandPalette(),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            () => _openCommandPalette(),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true):
            () => _selectPage(PulseShellPages.timeline),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true):
            () => _selectPage(PulseShellPages.health),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true):
            () => _selectPage(PulseShellPages.reports),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true):
            () => _selectPage(PulseShellPages.diagnostics),
        const SingleActivator(LogicalKeyboardKey.digit5, control: true):
            () => _selectPage(PulseShellPages.settings),
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true):
            () => _selectPage(PulseShellPages.timeline),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true):
            () => _selectPage(PulseShellPages.health),
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true):
            () => _selectPage(PulseShellPages.reports),
        const SingleActivator(LogicalKeyboardKey.digit4, meta: true):
            () => _selectPage(PulseShellPages.diagnostics),
        const SingleActivator(LogicalKeyboardKey.digit5, meta: true):
            () => _selectPage(PulseShellPages.settings),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              PulseTitleBar(
                onOpenSearch: () => _openCommandPalette(),
              ),
              Expanded(
                child: Row(
                  children: [
                    PulseSidebar(
                      selectedIndex: _index,
                      onSelected: _selectPage,
                      items: _nav,
                      footer: const _SidebarConnectionFooter(),
                    ),
                    Expanded(
                      child: PulseMicaBackground(
                        child: PulseContentFrame(
                          child: AnimatedSwitcher(
                            duration:
                                MediaQuery.maybeOf(context)?.disableAnimations ==
                                        true
                                    ? Duration.zero
                                    : PulseTokens.motionPage,
                            switchInCurve: PulseTokens.motionEmphasized,
                            switchOutCurve: Curves.easeInCubic,
                            layoutBuilder: (currentChild, previousChildren) {
                              return Stack(
                                alignment: Alignment.topCenter,
                                children: [
                                  ...previousChildren,
                                  ?currentChild,
                                ],
                              );
                            },
                            transitionBuilder: (child, animation) {
                              final curved = CurvedAnimation(
                                parent: animation,
                                curve: PulseTokens.motionEmphasized,
                              );
                              return FadeTransition(
                                opacity: curved,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.012, 0),
                                    end: Offset.zero,
                                  ).animate(curved),
                                  child: child,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey(_index),
                              child: _pageFor(_index, _titles[_index]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageFor(int index, String title) {
    switch (index) {
      case PulseShellPages.timeline:
        return TimelinePage(title: title);
      case PulseShellPages.health:
        return SystemHealthPage(title: title);
      case PulseShellPages.reports:
        return ReportsPage(title: title);
      case PulseShellPages.diagnostics:
        return DiagnosticsPage(title: title);
      case PulseShellPages.settings:
      default:
        return SettingsPage(title: title);
    }
  }
}

/// Rebuilds only the sidebar status card when connection state/version changes.
class _SidebarConnectionFooter extends StatelessWidget {
  const _SidebarConnectionFooter();

  @override
  Widget build(BuildContext context) {
    final state = context.select<PulseIpcClient, IpcConnectionState>(
      (c) => c.status.state,
    );
    final version = context.select<PulseIpcClient, String>(
      (c) => c.status.serviceVersion,
    );
    return ServiceStatusCard(state: state, serviceVersion: version);
  }
}
