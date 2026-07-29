import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pulse_protocol/pulse_constants.dart';

import '../../application/connection_controller.dart';
import '../../application/diagnostics_controller.dart';
import '../../application/settings_controller.dart';
import '../../application/timeline_session_controller.dart';
import '../../app/theme/pulse_theme.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../components/pulse_app_bar.dart';
import '../components/pulse_badge.dart';
import '../components/pulse_button.dart';
import '../components/pulse_card.dart';
import '../components/pulse_section_header.dart';
import '../utils/pulse_snack.dart';
import '../utils/pulse_user_errors.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.title});

  final String title;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<DiagnosticsController>().refresh());
    });
  }

  void _snack(BuildContext context, String message, {bool error = false}) {
    if (error) {
      PulseSnack.error(context, PulseUserErrors.fromMessage(message));
    } else {
      PulseSnack.success(context, message);
    }
  }

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required Future<void> Function() onConfirm,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PulseTokens.surfaceElevated,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await onConfirm();
      if (context.mounted) _snack(context, 'Done');
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionLabel = context.select<ConnectionController, String>(
      (c) => c.statusLabel,
    );
    final state = context.select<PulseIpcClient, IpcConnectionState>(
      (c) => c.status.state,
    );
    final settings = context.watch<SettingsController>();
    final ipc = context.watch<PulseIpcClient>();
    final diag = context.watch<DiagnosticsController>();
    final timeline = context.watch<TimelineSessionController>();
    final serviceVersion = ipc.status.serviceVersion.isEmpty
        ? '—'
        : ipc.status.serviceVersion;
    final windows = [
      if (diag.snapshot != null) ...[
        diag.snapshot!.windowsEdition,
        diag.snapshot!.windowsVersion,
      ],
    ].where((s) => s.trim().isNotEmpty).join(' ');
    final windowsLabel = windows.isNotEmpty
        ? windows
        : (state == IpcConnectionState.connected
            ? 'Loading from PulseService…'
            : 'Unavailable — PulseService offline');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseAppBar(
          title: widget.title,
          connectionState: state,
          connectionLabel: connectionLabel,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              PulseTokens.pagePadX,
              20,
              PulseTokens.pagePadX,
              PulseTokens.pagePadBottom,
            ),
            children: [
              PulseSectionHeader(
                title: 'Preferences',
                subtitle:
                    'Everything stays on this PC. No accounts, cloud sync, or telemetry.',
              ),
              const SizedBox(height: PulseTokens.spaceMd),
              _SettingsGroup(
                title: 'Timeline',
                children: [
                  _SettingsRow(
                    icon: LucideIcons.listOrdered,
                    title: 'Maximum stored events',
                    subtitle: '${settings.maxStoredEvents} events in memory',
                    trailing: _PrefSlider(
                      value: settings.maxStoredEvents,
                      min: 50,
                      max: 2000,
                      divisions: 39,
                      onCommit: (v) async {
                        await settings.setMaxStoredEvents(v);
                        if (context.mounted) {
                          _snack(context, 'Timeline limit set to $v');
                        }
                      },
                    ),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.download,
                    title: 'Startup snapshot size',
                    subtitle:
                        '${settings.startupSnapshotSize} events on connect',
                    trailing: _PrefSlider(
                      value: settings.startupSnapshotSize,
                      min: 20,
                      max: 500,
                      divisions: 48,
                      onCommit: (v) async {
                        await settings.setStartupSnapshotSize(v);
                        await timeline.reloadSnapshot();
                        if (context.mounted) {
                          _snack(context, 'Snapshot size set to $v');
                        }
                      },
                    ),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.arrowDownToLine,
                    title: 'Auto-scroll',
                    subtitle: 'Keep Timeline pinned to newest events',
                    trailing: Switch(
                      value: settings.autoScroll,
                      onChanged: (v) async {
                        await settings.setAutoScroll(v);
                        if (context.mounted) {
                          _snack(
                            context,
                            v ? 'Auto-scroll on' : 'Auto-scroll off',
                          );
                        }
                      },
                    ),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.radio,
                    title: 'Live Monitoring',
                    subtitle: 'Receive pushed Event Log updates',
                    trailing: Switch(
                      value: settings.liveMonitoringEnabled,
                      onChanged: (v) async {
                        await settings.setLiveMonitoringEnabled(v);
                        try {
                          await timeline.applyLiveMonitoringPreference();
                          if (context.mounted) {
                            _snack(
                              context,
                              v
                                  ? 'Live Monitoring enabled'
                                  : 'Live Monitoring paused',
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            _snack(context, 'Failed: $e', error: true);
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PulseTokens.spaceMd),
              _SettingsGroup(
                title: 'Collection',
                children: [
                  _SettingsRow(
                    icon: LucideIcons.scrollText,
                    title: 'System',
                    subtitle: 'Windows System Event Log — active channel',
                    trailing: const PulseBadge(
                      label: 'Active',
                      tone: PulseBadgeTone.success,
                      compact: true,
                    ),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.appWindow,
                    title: 'Application',
                    subtitle: 'Not enabled in this milestone',
                    trailing: const PulseBadge(label: 'Future', compact: true),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.shield,
                    title: 'Security',
                    subtitle: 'Requires elevated collection — future',
                    trailing: const PulseBadge(label: 'Future', compact: true),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.settings2,
                    title: 'Setup',
                    subtitle: 'Windows Setup channel — future',
                    trailing: const PulseBadge(label: 'Future', compact: true),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.radar,
                    title: 'ETW',
                    subtitle: 'Future milestone',
                    trailing: const PulseBadge(label: 'Future', compact: true),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.database,
                    title: 'WMI',
                    subtitle: 'Future milestone',
                    trailing: const PulseBadge(label: 'Future', compact: true),
                  ),
                ],
              ),
              const SizedBox(height: PulseTokens.spaceMd),
              _SettingsGroup(
                title: 'Interface',
                children: [
                  _SettingsRow(
                    icon: LucideIcons.moon,
                    title: 'Theme',
                    subtitle: 'Dark mode first (Windows 11 Fluent)',
                    trailing: const PulseBadge(label: 'Dark', compact: true),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.minimize2,
                    title: 'Compact mode',
                    subtitle: 'Slightly denser typography',
                    trailing: Switch(
                      value: settings.compactMode,
                      onChanged: (v) async {
                        await settings.setCompactMode(v);
                        if (context.mounted) {
                          _snack(context, v ? 'Compact mode on' : 'Compact mode off');
                        }
                      },
                    ),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.sparkles,
                    title: 'Animations',
                    subtitle: 'Motion for panels and transitions',
                    trailing: Switch(
                      value: settings.animationsEnabled,
                      onChanged: (v) async {
                        await settings.setAnimationsEnabled(v);
                        if (context.mounted) {
                          _snack(context, v ? 'Animations on' : 'Animations off');
                        }
                      },
                    ),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.languages,
                    title: 'Language',
                    subtitle: 'English only in this build',
                    trailing: const PulseBadge(label: 'Future', compact: true),
                  ),
                ],
              ),
              const SizedBox(height: PulseTokens.spaceMd),
              _SettingsGroup(
                title: 'Diagnostics',
                children: [
                  _SettingsRow(
                    icon: LucideIcons.bug,
                    title: 'Enable debug logging',
                    subtitle: 'Verbose AppLogger lines (local only)',
                    trailing: Switch(
                      value: settings.debugLogging,
                      onChanged: (v) async {
                        await settings.setDebugLogging(v);
                        if (context.mounted) {
                          _snack(context, v ? 'Debug logging on' : 'Debug logging off');
                        }
                      },
                    ),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.fileText,
                    title: 'Export logs',
                    subtitle: 'Write recent app log lines to Documents',
                    trailing: PulseButton(
                      label: 'Export',
                      icon: LucideIcons.download,
                      variant: PulseButtonVariant.secondary,
                      onPressed: () async {
                        try {
                          final path = await diag.exportLogsOnly();
                          if (context.mounted) _snack(context, 'Saved: $path');
                        } catch (e) {
                          if (context.mounted) {
                            _snack(context, 'Failed: $e', error: true);
                          }
                        }
                      },
                    ),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.rotateCcw,
                    title: 'Reset diagnostics',
                    subtitle: 'Clear client ping / message counters',
                    trailing: PulseButton(
                      label: 'Reset',
                      icon: LucideIcons.eraser,
                      variant: PulseButtonVariant.secondary,
                      onPressed: () {
                        diag.resetClientCounters();
                        _snack(context, 'Diagnostics counters reset');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PulseTokens.spaceMd),
              _SettingsGroup(
                title: 'Privacy',
                children: [
                  _SettingsRow(
                    icon: LucideIcons.shieldCheck,
                    title: 'Local-first',
                    subtitle: 'All observation data stays on this PC',
                    trailing: Icon(LucideIcons.check, size: 18, color: PulseTokens.success),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.eyeOff,
                    title: 'No telemetry',
                    subtitle: 'Pulse does not send analytics or crash reports',
                    trailing: Icon(LucideIcons.check, size: 18, color: PulseTokens.success),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.history,
                    title: 'Clear local history',
                    subtitle: 'Remove Timeline events from this session',
                    trailing: PulseButton(
                      label: 'Clear',
                      icon: LucideIcons.trash2,
                      variant: PulseButtonVariant.secondary,
                      onPressed: () => _confirm(
                        context,
                        title: 'Clear local history?',
                        body:
                            'This clears the in-memory Timeline. It does not modify Windows Event Logs.',
                        onConfirm: timeline.clearTimeline,
                      ),
                    ),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.slidersHorizontal,
                    title: 'Reset all settings',
                    subtitle: 'Restore defaults and clear preferences',
                    trailing: PulseButton(
                      label: 'Reset',
                      icon: LucideIcons.rotateCcw,
                      variant: PulseButtonVariant.secondary,
                      onPressed: () => _confirm(
                        context,
                        title: 'Reset all settings?',
                        body: 'Timeline preferences and interface options return to defaults.',
                        onConfirm: () async {
                          await settings.resetAll();
                          await timeline.applyLiveMonitoringPreference();
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PulseTokens.spaceMd),
              _SettingsGroup(
                title: 'About',
                children: [
                  _SettingsRow(
                    icon: LucideIcons.info,
                    title: 'Pulse version',
                    subtitle: kAppVersion,
                    trailing: const PulseBadge(
                      label: 'Bootstrap',
                      tone: PulseBadgeTone.accent,
                      compact: true,
                    ),
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.server,
                    title: 'Service version',
                    subtitle: serviceVersion,
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.calendar,
                    title: 'Build date',
                    subtitle: SettingsController.buildDate,
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.hash,
                    title: 'Protocol version',
                    subtitle: '$kProtocolVersion',
                  ),
                  const SoftDivider(indent: 52),
                  _SettingsRow(
                    icon: LucideIcons.monitor,
                    title: 'Windows version',
                    subtitle: windowsLabel,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 0.7,
                  fontSize: 11,
                  color: PulseTokens.textTertiary,
                ),
          ),
        ),
        PulseCard(
          elevated: true,
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: PulseTokens.surfaceHover,
              borderRadius: BorderRadius.circular(PulseTokens.radiusIconWell),
            ),
            child: Icon(icon, size: 18, color: PulseTokens.textSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _PrefSlider extends StatefulWidget {
  const _PrefSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onCommit,
  });

  final int value;
  final int min;
  final int max;
  final int divisions;
  final ValueChanged<int> onCommit;

  @override
  State<_PrefSlider> createState() => _PrefSliderState();
}

class _PrefSliderState extends State<_PrefSlider> {
  late double _local;

  @override
  void initState() {
    super.initState();
    _local = widget.value.toDouble();
  }

  @override
  void didUpdateWidget(covariant _PrefSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _local = widget.value.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: Slider(
        value: _local.clamp(widget.min.toDouble(), widget.max.toDouble()),
        min: widget.min.toDouble(),
        max: widget.max.toDouble(),
        divisions: widget.divisions,
        label: '${_local.round()}',
        onChanged: (v) => setState(() => _local = v),
        onChangeEnd: (v) => widget.onCommit(v.round()),
      ),
    );
  }
}
