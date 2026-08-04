import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pulse/app/theme/pulse_theme.dart';
import 'package:pulse/application/client_frame_metrics.dart';
import 'package:pulse/application/connection_controller.dart';
import 'package:pulse/application/diagnostics_controller.dart';
import 'package:pulse/application/health_navigation.dart';
import 'package:pulse/application/mcp_integration_controller.dart';
import 'package:pulse/application/service_lifecycle_controller.dart';
import 'package:pulse/application/settings_controller.dart';
import 'package:pulse/application/timeline_session_controller.dart';
import 'package:pulse/ipc/pulse_ipc_client.dart';
import 'package:pulse/logging/app_logger.dart';
import 'package:pulse/platform/pulse_service_scm.dart';
import 'package:pulse/presentation/diagnostics/diagnostics_page.dart';
import 'package:pulse/presentation/health/health_cards.dart';
import 'package:pulse/presentation/health/health_view_models.dart';
import 'package:pulse/presentation/health/system_health_page.dart';
import 'package:pulse/presentation/health/widgets/health_spec_rows.dart';
import 'package:pulse/presentation/health/widgets/process_inventory/process_inventory_list.dart';
import 'package:pulse/presentation/health/widgets/process_inventory/process_inventory_store.dart';
import 'package:pulse/presentation/reports/reports_page.dart';
import 'package:pulse/presentation/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StoppedScm implements PulseServiceScm {
  @override
  PulseServiceScmSnapshot query() =>
      const PulseServiceScmSnapshot(state: PulseServiceScmState.stopped);
}

Future<Widget> _harness(Widget page) async {
  SharedPreferences.setMockInitialValues({});
  final ipc = PulseIpcClient();
  final logger = AppLogger();
  final connection = ConnectionController(ipc: ipc, logger: logger);
  final settings = SettingsController(logger: logger);
  await settings.load();
  await settings.completeWelcome();
  final timeline = TimelineSessionController(
    ipc: ipc,
    settings: settings,
    logger: logger,
  );
  final frameMetrics = ClientFrameMetrics();
  final diagnostics = DiagnosticsController(
    ipc: ipc,
    timeline: timeline,
    settings: settings,
    logger: logger,
    frameMetrics: frameMetrics,
  );
  final lifecycle = ServiceLifecycleController(
    logger: logger,
    scm: _StoppedScm(),
  );
  lifecycle.refresh();
  // Provide MCP without load(); Diagnostics polls refreshStatus via Timer and
  // must not be paired with pumpAndSettle (never settles).
  final mcp = McpIntegrationController(logger: logger);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: ipc),
      ChangeNotifierProvider.value(value: connection),
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: timeline),
      ChangeNotifierProvider.value(value: diagnostics),
      ChangeNotifierProvider.value(value: frameMetrics),
      ChangeNotifierProvider.value(value: lifecycle),
      ChangeNotifierProvider.value(value: mcp),
      ChangeNotifierProvider(create: (_) => HealthNavigation()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: PulseTheme.dark(),
      darkTheme: PulseTheme.dark(),
      themeMode: ThemeMode.dark,
      builder: (context, child) {
        final pulse = Theme.of(context).extension<PulseThemeData>();
        if (pulse != null) {
          PulseThemeScope.current = pulse;
        }
        return child ?? const SizedBox.shrink();
      },
      home: Scaffold(
        backgroundColor: PulseTokens.canvas,
        body: page,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Settings page has no overflow at narrow width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(await _harness(const SettingsPage(title: 'Settings')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('General'), findsWidgets);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Reset onboarding'), findsOneWidget);
  });

  testWidgets('Settings categories render at narrow width without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(await _harness(const SettingsPage(title: 'Settings')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    const categories = [
      'Appearance',
      'System Health',
      'Timeline',
      'Diagnostics',
      'Performance',
      'Privacy',
      'Updates',
      'Developer',
    ];
    for (final label in categories) {
      await tester.ensureVisible(find.text(label).first);
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow in $label');
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text('Appearance').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Text size'), findsOneWidget);
  });

  testWidgets('Reports page has no overflow at narrow width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await _harness(const ReportsPage(title: 'Reports')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Export Report'), findsOneWidget);
    expect(find.text('System Health snapshot'), findsWidgets);
  });

  testWidgets('Diagnostics offline recovery offers Start PulseService',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await _harness(const DiagnosticsPage(title: 'Diagnostics')),
    );
    // Diagnostics starts a 2s MCP status timer — do not pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('PulseService is stopped'), findsOneWidget);
    expect(find.text('Start PulseService'), findsWidgets);
  });

  testWidgets('Diagnostics offline recovery at very narrow width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await _harness(const DiagnosticsPage(title: 'Diagnostics')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('PulseService is stopped'), findsOneWidget);
  });

  testWidgets('System Health shows offline recovery when disconnected',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await _harness(const SystemHealthPage(title: 'System Health')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('PulseService is stopped'), findsOneWidget);
    expect(find.text('Start PulseService'), findsOneWidget);
  });

  testWidgets('Reports page shows templates and export controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await _harness(const ReportsPage(title: 'Reports')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Reports'), findsWidgets);
    expect(find.text('Export Report'), findsOneWidget);
    expect(find.text('System Health snapshot'), findsWidgets);
  });

  testWidgets('Health hero grid reflows without overflow at 2-column width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: PulseTheme.dark(),
        home: Scaffold(
          backgroundColor: PulseTokens.canvas,
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: HealthCardGrid(
              children: [
                HealthHeroCard(
                  metric: HealthMetric(
                    id: 'cpu',
                    title: 'CPU',
                    value: '18',
                    unit: '%',
                    description: '',
                    status: HealthStatus.good,
                    icon: LucideIcons.cpu,
                  ),
                ),
                HealthHeroCard(
                  metric: HealthMetric(
                    id: 'memory',
                    title: 'Memory',
                    value: '9.4',
                    unit: 'GB',
                    description: '',
                    status: HealthStatus.good,
                    icon: LucideIcons.memoryStick,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
  });

  testWidgets('Storage card scrolls many volumes without RenderFlex overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final rows = <HealthDetailRow>[
      for (var i = 0; i < 10; i++)
        HealthDetailRow(
          label: '${String.fromCharCode(67 + i)}:',
          value: '${i + 1}.0 GB of 100 GB',
          available: true,
          progress: (i + 1) / 12,
        ),
      const HealthDetailRow(
        label: 'Read Speed',
        value: '12 MB/s',
        available: true,
      ),
      const HealthDetailRow(
        label: 'Write Speed',
        value: '4 MB/s',
        available: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: PulseTheme.dark(),
        home: Scaffold(
          backgroundColor: PulseTokens.canvas,
          body: SizedBox(
            width: 320,
            height: 220,
            child: HealthGroupedCard(
              title: 'Storage',
              icon: LucideIcons.hardDrive,
              rows: rows,
              compact: true,
              scrollBody: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('C:'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Write Speed'), findsWidgets);
  });

  testWidgets('HealthSpecSection truncates long values without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: PulseTheme.dark(),
        home: Scaffold(
          backgroundColor: PulseTokens.canvas,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: HealthSpecSection(
              title: 'Adapter',
              compact: true,
              rows: const [
                HealthSpecRow(
                  label: 'Description',
                  value:
                      'Intel(R) Wi-Fi 6E AX211 160MHz Network Adapter with a very long product name',
                ),
                HealthSpecRow(
                  label: 'Dedicated Used',
                  value: '1.25 GB',
                  description: '42% of capacity',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Description'), findsOneWidget);
    expect(find.byType(Tooltip), findsWidgets);
  });

  testWidgets('Health hero card exposes semantics and truncates value',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: PulseTheme.dark(),
        home: Scaffold(
          backgroundColor: PulseTokens.canvas,
          body: SizedBox(
            width: 200,
            child: HealthHeroCard(
              compact: true,
              metric: HealthMetric(
                id: 'cpu',
                title: 'CPU Utilization Across All Cores',
                value: '18.4',
                unit: '%',
                description: 'Base clock 3.60 GHz with turbo boost enabled',
                status: HealthStatus.good,
                icon: LucideIcons.cpu,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final semantics = tester.getSemantics(find.byType(HealthHeroCard));
    expect(semantics.label, contains('CPU Utilization Across All Cores: 18.4 %'));
  });

  testWidgets('Process inventory empty state is friendly copy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = ProcessInventoryStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: PulseTheme.dark(),
        home: Scaffold(
          backgroundColor: PulseTokens.canvas,
          body: SizedBox(
            height: 240,
            child: ProcessInventoryList(store: store, compact: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Waiting for process inventory'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('Health section expand prefs roundtrip via SettingsController',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final logger = AppLogger();
    final settings = SettingsController(logger: logger);
    await settings.load();

    expect(settings.isHealthSectionExpanded('cpu', 'overview'), isTrue);
    expect(
      settings.isHealthSectionExpanded('cpu', 'history', defaultExpanded: false),
      isFalse,
    );

    await settings.setHealthSectionExpanded('cpu', 'overview', false);
    expect(settings.isHealthSectionExpanded('cpu', 'overview'), isFalse);
    expect(settings.toMap()['health_sections_expanded'], containsPair('cpu.overview', false));

    final reloaded = SettingsController(logger: logger);
    await reloaded.load();
    expect(reloaded.isHealthSectionExpanded('cpu', 'overview'), isFalse);
  });
}

