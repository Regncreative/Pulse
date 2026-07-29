import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../app/theme/pulse_theme.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../components/pulse_content_frame.dart';
import '../components/pulse_mica.dart';
import '../components/pulse_sidebar.dart';
import '../components/pulse_title_bar.dart';
import '../components/service_status_card.dart';
import '../timeline/timeline_page.dart';
import '../health/system_health_page.dart';
import '../diagnostics/diagnostics_page.dart';
import '../settings/settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

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
    'Diagnostics',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    // Do not watch IPC here — that rebuilt the entire page tree (and every
    // MouseRegion) on each connection tick. Sidebar status is isolated below.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const PulseTitleBar(),
          Expanded(
            child: Row(
              children: [
                PulseSidebar(
                  selectedIndex: _index,
                  onSelected: (i) => setState(() => _index = i),
                  items: _nav,
                  footer: const _SidebarConnectionFooter(),
                ),
                Expanded(
                  child: PulseMicaBackground(
                    child: PulseContentFrame(
                      child: AnimatedSwitcher(
                        duration: MediaQuery.maybeOf(context)?.disableAnimations ==
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
    );
  }

  Widget _pageFor(int index, String title) {
    switch (index) {
      case 0:
        return TimelinePage(title: title);
      case 1:
        return SystemHealthPage(title: title);
      case 2:
        return DiagnosticsPage(title: title);
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
