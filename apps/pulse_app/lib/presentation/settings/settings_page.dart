import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Snap arbitrary persisted caps onto the Settings dropdown presets.
int _nearestTimelineCap(int value) {
  const presets = [500, 2000, 10000, 50000, 100000];
  var best = presets.first;
  var bestDelta = (value - best).abs();
  for (final p in presets.skip(1)) {
    final d = (value - p).abs();
    if (d < bestDelta) {
      best = p;
      bestDelta = d;
    }
  }
  return best;
}

enum _SettingsCategory {
  general,
  appearance,
  systemHealth,
  timeline,
  diagnostics,
  performance,
  privacy,
  updates,
  developer,
}

extension on _SettingsCategory {
  String get label => switch (this) {
        _SettingsCategory.general => 'General',
        _SettingsCategory.appearance => 'Appearance',
        _SettingsCategory.systemHealth => 'System Health',
        _SettingsCategory.timeline => 'Timeline',
        _SettingsCategory.diagnostics => 'Diagnostics',
        _SettingsCategory.performance => 'Performance',
        _SettingsCategory.privacy => 'Privacy',
        _SettingsCategory.updates => 'Updates',
        _SettingsCategory.developer => 'Developer',
      };

  IconData get icon => switch (this) {
        _SettingsCategory.general => LucideIcons.settings,
        _SettingsCategory.appearance => LucideIcons.palette,
        _SettingsCategory.systemHealth => LucideIcons.heartPulse,
        _SettingsCategory.timeline => LucideIcons.listOrdered,
        _SettingsCategory.diagnostics => LucideIcons.bug,
        _SettingsCategory.performance => LucideIcons.gauge,
        _SettingsCategory.privacy => LucideIcons.shieldCheck,
        _SettingsCategory.updates => LucideIcons.download,
        _SettingsCategory.developer => LucideIcons.codeXml,
      };
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.title});

  final String title;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _SettingsCategory _category = _SettingsCategory.general;
  late final TextEditingController _customHexController;

  @override
  void initState() {
    super.initState();
    _customHexController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<DiagnosticsController>().refresh());
      final settings = context.read<SettingsController>();
      _syncHexField(settings.customAccentArgb);
    });
  }

  @override
  void dispose() {
    _customHexController.dispose();
    super.dispose();
  }

  void _syncHexField(int argb) {
    final hex = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    if (_customHexController.text.toUpperCase() != hex) {
      _customHexController.text = hex;
    }
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

  int? _parseHexColor(String raw) {
    var s = raw.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 8) s = s.substring(2);
    if (s.length != 6) return null;
    final value = int.tryParse(s, radix: 16);
    if (value == null) return null;
    return 0xFF000000 | value;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              PulseTokens.pagePadX,
              16,
              PulseTokens.pagePadX,
              PulseTokens.pagePadBottom,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 200,
                  child: _CategoryRail(
                    selected: _category,
                    onSelect: (c) => setState(() => _category = c),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(right: 4),
                    children: [
                      PulseSectionHeader(
                        title: _category.label,
                        subtitle: _categorySubtitle(_category),
                      ),
                      const SizedBox(height: PulseTokens.spaceMd),
                      ..._buildCategoryContent(
                        context,
                        category: _category,
                        settings: settings,
                        timeline: timeline,
                        diag: diag,
                        serviceVersion: serviceVersion,
                        windowsLabel: windowsLabel,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _categorySubtitle(_SettingsCategory category) {
    return switch (category) {
      _SettingsCategory.general =>
        'Welcome and onboarding. Density and motion live under Appearance.',
      _SettingsCategory.appearance =>
        'Theme, accent color, density, text size, and motion.',
      _SettingsCategory.systemHealth =>
        'Units and display preferences for System Health.',
      _SettingsCategory.timeline =>
        'In-memory event buffer and live monitoring.',
      _SettingsCategory.diagnostics =>
        'Local logging and advanced diagnostic surfaces.',
      _SettingsCategory.performance =>
        'Balance responsiveness, detail, and battery.',
      _SettingsCategory.privacy =>
        'Everything stays on this PC. No accounts or telemetry.',
      _SettingsCategory.updates => 'App and service version information.',
      _SettingsCategory.developer =>
        'Export, import, and reset local preferences.',
    };
  }

  List<Widget> _buildCategoryContent(
    BuildContext context, {
    required _SettingsCategory category,
    required SettingsController settings,
    required TimelineSessionController timeline,
    required DiagnosticsController diag,
    required String serviceVersion,
    required String windowsLabel,
  }) {
    return switch (category) {
      _SettingsCategory.general => [
          _SettingsGroup(
            title: 'Onboarding',
            children: [
              _SettingsRow(
                icon: LucideIcons.sparkles,
                title: 'Reset onboarding',
                subtitle: 'Show the welcome screen again on next launch',
                trailing: PulseButton(
                  label: 'Reset',
                  icon: LucideIcons.rotateCcw,
                  variant: PulseButtonVariant.secondary,
                  onPressed: () => _confirm(
                    context,
                    title: 'Reset onboarding?',
                    body:
                        'The welcome screen will appear again the next time Pulse starts.',
                    onConfirm: settings.resetOnboarding,
                  ),
                ),
              ),
            ],
          ),
        ],
      _SettingsCategory.appearance => [
          _SettingsGroup(
            title: 'Theme',
            children: [
              _SettingsRow(
                icon: LucideIcons.moon,
                title: 'Theme mode',
                subtitle: 'Follow system, or force light / dark',
                trailing: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'system', label: Text('System')),
                    ButtonSegment(value: 'light', label: Text('Light')),
                    ButtonSegment(value: 'dark', label: Text('Dark')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) async {
                    await settings.setThemeMode(s.first);
                    if (context.mounted) {
                      _snack(context, 'Theme: ${s.first}');
                    }
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: PulseTokens.spaceMd),
          _SettingsGroup(
            title: 'Accent',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final preset in [
                      ('blue', PulseThemeData.accentForPreset('blue', Theme.of(context).brightness)),
                      ('green', PulseThemeData.accentForPreset('green', Theme.of(context).brightness)),
                      ('purple', PulseThemeData.accentForPreset('purple', Theme.of(context).brightness)),
                      ('orange', PulseThemeData.accentForPreset('orange', Theme.of(context).brightness)),
                    ])
                      _AccentChip(
                        label: preset.$1,
                        color: preset.$2,
                        selected: settings.accentPreset == preset.$1,
                        onTap: () async {
                          await settings.setAccentPreset(preset.$1);
                          if (context.mounted) {
                            _snack(context, 'Accent: ${preset.$1}');
                          }
                        },
                      ),
                    _AccentChip(
                      label: 'custom',
                      color: Color(settings.customAccentArgb),
                      selected: settings.accentPreset == 'custom',
                      onTap: () async {
                        await settings.setAccentPreset('custom');
                        _syncHexField(settings.customAccentArgb);
                        if (context.mounted) {
                          _snack(context, 'Accent: custom');
                        }
                      },
                    ),
                  ],
                ),
              ),
              if (settings.accentPreset == 'custom') ...[
                const SoftDivider(indent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(settings.customAccentArgb),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: PulseTokens.stroke),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _customHexController,
                          decoration: const InputDecoration(
                            labelText: 'Custom hex',
                            hintText: '60CDFF',
                            prefixText: '#',
                            isDense: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9a-fA-F]'),
                            ),
                            LengthLimitingTextInputFormatter(6),
                          ],
                          onSubmitted: (raw) async {
                            final argb = _parseHexColor(raw);
                            if (argb == null) {
                              if (context.mounted) {
                                _snack(
                                  context,
                                  'Enter a 6-digit hex color',
                                  error: true,
                                );
                              }
                              return;
                            }
                            await settings.setCustomAccentArgb(argb);
                            if (context.mounted) {
                              _snack(context, 'Custom accent updated');
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      PulseButton(
                        label: 'Apply',
                        variant: PulseButtonVariant.secondary,
                        onPressed: () async {
                          final argb =
                              _parseHexColor(_customHexController.text);
                          if (argb == null) {
                            _snack(
                              context,
                              'Enter a 6-digit hex color',
                              error: true,
                            );
                            return;
                          }
                          await settings.setCustomAccentArgb(argb);
                          if (context.mounted) {
                            _snack(context, 'Custom accent updated');
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: PulseTokens.spaceMd),
          _SettingsGroup(
            title: 'Density & motion',
            children: [
              _SettingsRow(
                icon: LucideIcons.minimize2,
                title: 'Compact mode',
                subtitle: 'Slightly denser typography',
                trailing: Switch(
                  value: settings.compactMode,
                  onChanged: (v) async {
                    await settings.setCompactMode(v);
                    if (context.mounted) {
                      _snack(
                        context,
                        v ? 'Compact mode on' : 'Compact mode off',
                      );
                    }
                  },
                ),
              ),
              const SoftDivider(indent: 52),
              _SettingsRow(
                icon: LucideIcons.type,
                title: 'Text size',
                subtitle: '${settings.textScale.toStringAsFixed(2)}×',
                trailing: _PrefDoubleSlider(
                  value: settings.textScale,
                  min: 0.9,
                  max: 1.3,
                  divisions: 8,
                  labelBuilder: (v) => '${v.toStringAsFixed(2)}×',
                  onCommit: (v) async {
                    await settings.setTextScale(v);
                    if (context.mounted) {
                      _snack(
                        context,
                        'Text size ${v.toStringAsFixed(2)}×',
                      );
                    }
                  },
                ),
              ),
              const SoftDivider(indent: 52),
              _SettingsRow(
                icon: LucideIcons.sparkles,
                title: 'Animations',
                subtitle: settings.performanceMode == 'battery'
                    ? 'Disabled while Performance mode is Battery'
                    : 'Motion for panels and transitions',
                trailing: Switch(
                  value: settings.animationsEnabled,
                  onChanged: settings.performanceMode == 'battery'
                      ? null
                      : (v) async {
                          await settings.setAnimationsEnabled(v);
                          if (context.mounted) {
                            _snack(
                              context,
                              v ? 'Animations on' : 'Animations off',
                            );
                          }
                        },
                ),
              ),
              const SoftDivider(indent: 52),
              _SettingsRow(
                icon: LucideIcons.gauge,
                title: 'Animation speed',
                subtitle: '${settings.animationSpeed.toStringAsFixed(2)}×',
                trailing: _PrefDoubleSlider(
                  value: settings.animationSpeed,
                  min: 0.5,
                  max: 1.5,
                  divisions: 20,
                  labelBuilder: (v) => '${v.toStringAsFixed(2)}×',
                  onCommit: (v) async {
                    await settings.setAnimationSpeed(v);
                    if (context.mounted) {
                      _snack(
                        context,
                        'Animation speed ${v.toStringAsFixed(2)}×',
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      _SettingsCategory.systemHealth => [
          _SettingsGroup(
            title: 'Units',
            children: [
              _SettingsRow(
                icon: LucideIcons.binary,
                title: 'Byte units',
                subtitle: settings.byteUnitBinary
                    ? 'Binary (KiB / MiB, base 1024)'
                    : 'Decimal (KB / MB, base 1000)',
                trailing: Switch(
                  value: settings.byteUnitBinary,
                  onChanged: (v) async {
                    await settings.setByteUnitBinary(v);
                    if (context.mounted) {
                      _snack(
                        context,
                        v ? 'Binary byte units' : 'Decimal byte units',
                      );
                    }
                  },
                ),
              ),
              const SoftDivider(indent: 52),
              _SettingsRow(
                icon: LucideIcons.thermometer,
                title: 'Temperature',
                subtitle: settings.temperatureCelsius
                    ? 'Celsius (°C)'
                    : 'Fahrenheit (°F)',
                trailing: Switch(
                  value: settings.temperatureCelsius,
                  onChanged: (v) async {
                    await settings.setTemperatureCelsius(v);
                    if (context.mounted) {
                      _snack(context, v ? 'Celsius' : 'Fahrenheit');
                    }
                  },
                ),
              ),
              const SoftDivider(indent: 52),
              _SettingsRow(
                icon: LucideIcons.clock,
                title: 'Clock format',
                subtitle: settings.clock24h ? '24-hour' : '12-hour',
                trailing: Switch(
                  value: settings.clock24h,
                  onChanged: (v) async {
                    await settings.setClock24h(v);
                    if (context.mounted) {
                      _snack(context, v ? '24-hour clock' : '12-hour clock');
                    }
                  },
                ),
              ),
              const SoftDivider(indent: 52),
              _SettingsRow(
                icon: LucideIcons.activity,
                title: 'Sample rate',
                subtitle: 'Health metrics refresh ~1 Hz from PulseService',
                trailing: const PulseBadge(
                  label: '~1 Hz',
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      _SettingsCategory.timeline => [
          _SettingsGroup(
            title: 'Buffer',
            children: [
              _SettingsRow(
                icon: LucideIcons.listOrdered,
                title: 'Maximum stored events',
                subtitle:
                    '${settings.maxStoredEvents} in memory · higher limits use more RAM',
                trailing: DropdownButton<int>(
                  value: _nearestTimelineCap(settings.maxStoredEvents),
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 500, child: Text('500')),
                    DropdownMenuItem(value: 2000, child: Text('2,000')),
                    DropdownMenuItem(value: 10000, child: Text('10,000')),
                    DropdownMenuItem(value: 50000, child: Text('50,000')),
                    DropdownMenuItem(value: 100000, child: Text('100,000')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
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
                subtitle: '${settings.startupSnapshotSize} events on connect',
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
        ],
      _SettingsCategory.diagnostics => [
          _SettingsGroup(
            title: 'Logging',
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
                      _snack(
                        context,
                        v ? 'Debug logging on' : 'Debug logging off',
                      );
                    }
                  },
                ),
              ),
              const SoftDivider(indent: 52),
              _SettingsRow(
                icon: LucideIcons.layers,
                title: 'Show advanced diagnostics',
                subtitle:
                    'Show identity, IPC throughput, reconnect history, and developer tools on Diagnostics',
                trailing: Switch(
                  value: settings.showAdvancedDiagnostics,
                  onChanged: (v) async {
                    await settings.setShowAdvancedDiagnostics(v);
                    if (context.mounted) {
                      _snack(
                        context,
                        v
                            ? 'Advanced diagnostics on'
                            : 'Advanced diagnostics off',
                      );
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
        ],
      _SettingsCategory.performance => [
          _SettingsGroup(
            title: 'Mode',
            children: [
              _SettingsRow(
                icon: LucideIcons.gauge,
                title: 'Performance mode',
                subtitle: switch (settings.performanceMode) {
                  'performance' =>
                    'Preference stored for future refresh/history tuning; UI same as Balanced today',
                  'battery' =>
                    'Disables animations (same as turning Animations off)',
                  _ => 'Balanced defaults for everyday use',
                },
                trailing: DropdownButton<String>(
                  value: settings.performanceMode,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: 'balanced',
                      child: Text('Balanced'),
                    ),
                    DropdownMenuItem(
                      value: 'performance',
                      child: Text('Performance'),
                    ),
                    DropdownMenuItem(
                      value: 'battery',
                      child: Text('Battery'),
                    ),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    await settings.setPerformanceMode(v);
                    if (context.mounted) {
                      _snack(context, 'Performance mode: $v');
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      _SettingsCategory.privacy => [
          _SettingsGroup(
            title: 'Local-first',
            children: [
              _SettingsRow(
                icon: LucideIcons.shieldCheck,
                title: 'Local-first',
                subtitle: 'All observation data stays on this PC',
                trailing: Icon(
                  LucideIcons.check,
                  size: 18,
                  color: PulseTokens.success,
                ),
              ),
              const SoftDivider(indent: 52),
              _SettingsRow(
                icon: LucideIcons.eyeOff,
                title: 'No telemetry',
                subtitle: 'Pulse does not send analytics or crash reports',
                trailing: Icon(
                  LucideIcons.check,
                  size: 18,
                  color: PulseTokens.success,
                ),
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
                    body:
                        'Timeline preferences and interface options return to defaults.',
                    onConfirm: () async {
                      await settings.resetAll();
                      await timeline.applyLiveMonitoringPreference();
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      _SettingsCategory.updates => [
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
                icon: LucideIcons.calendar,
                title: 'Build date',
                subtitle: SettingsController.buildDate,
              ),
              const SoftDivider(indent: 52),
              _SettingsRow(
                icon: LucideIcons.server,
                title: 'Service version',
                subtitle: serviceVersion,
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
              const SoftDivider(indent: 52),
              _SettingsRow(
                icon: LucideIcons.externalLink,
                title: 'Releases',
                subtitle: SettingsController.releasesUrl,
                trailing: IconButton(
                  tooltip: 'Copy URL',
                  icon: const Icon(LucideIcons.copy, size: 16),
                  onPressed: () async {
                    await Clipboard.setData(
                      const ClipboardData(
                        text: SettingsController.releasesUrl,
                      ),
                    );
                    if (context.mounted) {
                      _snack(context, 'Release URL copied');
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      _SettingsCategory.developer => [
          _SettingsGroup(
            title: 'Settings data',
            children: [
              _SettingsRow(
                icon: LucideIcons.upload,
                title: 'Export settings',
                subtitle:
                    'Write JSON to Documents/Pulse/settings-export.json',
                trailing: PulseButton(
                  label: 'Export',
                  icon: LucideIcons.download,
                  variant: PulseButtonVariant.secondary,
                  onPressed: () async {
                    try {
                      final path = await settings.exportSettingsJson();
                      if (context.mounted) {
                        _snack(context, 'Saved: $path');
                      }
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
                icon: LucideIcons.import,
                title: 'Restore from last export',
                subtitle: 'Import Documents/Pulse/settings-export.json',
                trailing: PulseButton(
                  label: 'Import',
                  icon: LucideIcons.upload,
                  variant: PulseButtonVariant.secondary,
                  onPressed: () => _confirm(
                    context,
                    title: 'Import settings?',
                    body:
                        'Current preferences will be replaced with the last export file.',
                    onConfirm: () async {
                      await settings.importSettingsFromLastExport();
                      await timeline.applyLiveMonitoringPreference();
                    },
                  ),
                ),
              ),
              const SoftDivider(indent: 52),
              _SettingsRow(
                icon: LucideIcons.folder,
                title: 'Export directory',
                subtitle: settings.exportDirectory.isEmpty
                    ? 'Default: Documents/Pulse'
                    : settings.exportDirectory,
                trailing: PulseButton(
                  label: settings.exportDirectory.isEmpty ? 'Set' : 'Clear',
                  variant: PulseButtonVariant.secondary,
                  onPressed: () async {
                    if (settings.exportDirectory.isNotEmpty) {
                      await settings.setExportDirectory('');
                      if (context.mounted) {
                        _snack(context, 'Export directory reset to default');
                      }
                      return;
                    }
                    final controller = TextEditingController();
                    final path = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: PulseTokens.surfaceElevated,
                        title: const Text('Export directory'),
                        content: TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            hintText: r'C:\path\to\exports',
                          ),
                          autofocus: true,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(ctx, controller.text.trim()),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    );
                    if (path != null && path.isNotEmpty) {
                      await settings.setExportDirectory(path);
                      if (context.mounted) {
                        _snack(context, 'Export directory set');
                      }
                    }
                  },
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
                    body:
                        'Timeline preferences and interface options return to defaults.',
                    onConfirm: () async {
                      await settings.resetAll();
                      await timeline.applyLiveMonitoringPreference();
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
    };
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.selected,
    required this.onSelect,
  });

  final _SettingsCategory selected;
  final ValueChanged<_SettingsCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    return PulseCard(
      elevated: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        children: [
          for (final category in _SettingsCategory.values)
            _CategoryTile(
              category: category,
              selected: category == selected,
              onTap: () => onSelect(category),
            ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatefulWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final _SettingsCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bg = selected
        ? PulseTokens.accentSoft
        : _hover
            ? PulseTokens.surfaceHover
            : Colors.transparent;
    final fg = selected ? PulseTokens.accent : PulseTokens.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        child: InkWell(
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hover = v),
          borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(widget.category.icon, size: 16, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.category.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected
                              ? PulseTokens.textPrimary
                              : PulseTokens.textSecondary,
                        ),
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

class _AccentChip extends StatelessWidget {
  const _AccentChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PulseTokens.radiusPill),
      child: AnimatedContainer(
        duration: PulseTokens.motionFast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? PulseTokens.accentSoft : PulseTokens.surfaceHover,
          borderRadius: BorderRadius.circular(PulseTokens.radiusPill),
          border: Border.all(
            color: selected ? PulseTokens.accent : PulseTokens.stroke,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: PulseTokens.strokeStrong),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label[0].toUpperCase() + label.substring(1),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackTrailing =
              trailing != null && constraints.maxWidth < 440;
          final label = Expanded(
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
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          );
          final iconWell = Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: PulseTokens.surfaceHover,
              borderRadius: BorderRadius.circular(PulseTokens.radiusIconWell),
            ),
            child: Icon(icon, size: 18, color: PulseTokens.textSecondary),
          );

          if (stackTrailing) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconWell,
                    const SizedBox(width: 14),
                    label,
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: trailing!,
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              iconWell,
              const SizedBox(width: 14),
              label,
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          );
        },
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

class _PrefDoubleSlider extends StatefulWidget {
  const _PrefDoubleSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onCommit,
    required this.labelBuilder,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onCommit;
  final String Function(double) labelBuilder;

  @override
  State<_PrefDoubleSlider> createState() => _PrefDoubleSliderState();
}

class _PrefDoubleSliderState extends State<_PrefDoubleSlider> {
  late double _local;

  @override
  void initState() {
    super.initState();
    _local = widget.value;
  }

  @override
  void didUpdateWidget(covariant _PrefDoubleSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _local = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: Slider(
        value: _local.clamp(widget.min, widget.max),
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        label: widget.labelBuilder(_local),
        onChanged: (v) => setState(() => _local = v),
        onChangeEnd: (v) => widget.onCommit(v),
      ),
    );
  }
}
