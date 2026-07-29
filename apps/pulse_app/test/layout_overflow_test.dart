import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pulse/app/theme/pulse_theme.dart';
import 'package:pulse/application/connection_controller.dart';
import 'package:pulse/ipc/pulse_ipc_client.dart';
import 'package:pulse/logging/app_logger.dart';
import 'package:pulse/presentation/diagnostics/diagnostics_page.dart';
import 'package:pulse/presentation/health/health_cards.dart';
import 'package:pulse/presentation/health/health_view_models.dart';
import 'package:pulse/presentation/health/system_health_page.dart';
import 'package:pulse/presentation/settings/settings_page.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _harness(Widget page) {
  final ipc = PulseIpcClient();
  final logger = AppLogger();
  final connection = ConnectionController(ipc: ipc, logger: logger);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: ipc),
      ChangeNotifierProvider.value(value: connection),
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

    await tester.pumpWidget(_harness(const SettingsPage(title: 'Settings')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Preferences'), findsOneWidget);
  });

  testWidgets('Diagnostics page has no overflow at narrow width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness(const DiagnosticsPage(title: 'Diagnostics')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('IPC health'), findsOneWidget);
    expect(find.text('Ping / Pong'), findsOneWidget);
  });

  testWidgets('Diagnostics page has no overflow at very narrow width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness(const DiagnosticsPage(title: 'Diagnostics')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('System Health shows offline empty state when disconnected',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness(const SystemHealthPage(title: 'System Health')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Pulse Service is not running.'), findsOneWidget);
    expect(
      find.textContaining('Live monitoring is unavailable'),
      findsOneWidget,
    );
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
