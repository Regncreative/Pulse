import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pulse/app/theme/pulse_theme.dart';
import 'package:pulse/application/connection_controller.dart';
import 'package:pulse/application/diagnostics_controller.dart';
import 'package:pulse/application/settings_controller.dart';
import 'package:pulse/application/timeline_session_controller.dart';
import 'package:pulse/ipc/pulse_ipc_client.dart';
import 'package:pulse/logging/app_logger.dart';
import 'package:pulse/presentation/diagnostics/diagnostics_page.dart';
import 'package:pulse/presentation/health/health_cards.dart';
import 'package:pulse/presentation/health/health_view_models.dart';
import 'package:pulse/presentation/health/system_health_page.dart';
import 'package:pulse/presentation/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final diagnostics = DiagnosticsController(
    ipc: ipc,
    timeline: timeline,
    settings: settings,
    logger: logger,
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: ipc),
      ChangeNotifierProvider.value(value: connection),
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: timeline),
      ChangeNotifierProvider.value(value: diagnostics),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: PulseTheme.dark(),
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
    expect(find.text('Preferences'), findsOneWidget);
  });

  testWidgets('Diagnostics offline empty state explains next step',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await _harness(const DiagnosticsPage(title: 'Diagnostics')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Diagnostics needs PulseService'), findsOneWidget);
    expect(find.textContaining('Start PulseService'), findsOneWidget);
  });

  testWidgets('Diagnostics offline empty state at very narrow width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await _harness(const DiagnosticsPage(title: 'Diagnostics')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Diagnostics needs PulseService'), findsOneWidget);
  });

  testWidgets('System Health shows offline empty state when disconnected',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await _harness(const SystemHealthPage(title: 'System Health')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ready when Windows is'), findsOneWidget);
    expect(find.textContaining('Start PulseService'), findsOneWidget);
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
}
