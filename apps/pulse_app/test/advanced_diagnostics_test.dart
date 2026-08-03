import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pulse/app/theme/pulse_theme.dart';
import 'package:pulse/application/client_frame_metrics.dart';
import 'package:pulse/application/connection_controller.dart';
import 'package:pulse/application/diagnostics_controller.dart';
import 'package:pulse/application/health_navigation.dart';
import 'package:pulse/application/service_lifecycle_controller.dart';
import 'package:pulse/application/settings_controller.dart';
import 'package:pulse/application/timeline_session_controller.dart';
import 'package:pulse/ipc/pulse_ipc_client.dart';
import 'package:pulse/logging/app_logger.dart';
import 'package:pulse/platform/pulse_service_scm.dart';
import 'package:pulse/presentation/diagnostics/diagnostics_page.dart';
import 'package:pulse_protocol/pulse_wire.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RunningScm implements PulseServiceScm {
  @override
  PulseServiceScmSnapshot query() =>
      const PulseServiceScmSnapshot(state: PulseServiceScmState.running);
}

Future<(Widget, SettingsController, DiagnosticsController, PulseIpcClient)>
    _harness({required bool advanced}) async {
  SharedPreferences.setMockInitialValues({
    'diagnostics.show_advanced': advanced,
    'onboarding.welcome_completed': true,
  });
  final ipc = PulseIpcClient();
  ipc.debugSetStatusForTest(
    const IpcStatus(state: IpcConnectionState.connected, message: 'test'),
  );
  final logger = AppLogger();
  final connection = ConnectionController(ipc: ipc, logger: logger);
  final settings = SettingsController(logger: logger);
  await settings.load();
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
  diagnostics.debugSetSnapshotForTest(
    DiagnosticsSnapshot(
      serviceVersion: '1.0.0',
      protocolVersion: 1,
      serviceStartUnixMs: DateTime.now().millisecondsSinceEpoch,
      serviceUptimeMs: 60000,
      runMode: 'Windows Service',
      ipcListening: true,
      liveSubscribed: true,
      liveChannel: 'System',
      liveEventsPushed: 10,
      liveEventsDropped: 0,
      liveSubscriberReconnects: 0,
      liveQueueDepth: 0,
      liveQueueCapacity: 1000,
      servicePid: 1,
      workingSetBytes: 20 * 1024 * 1024,
      threadCount: 8,
      handleCount: 100,
      healthMonitoringActive: true,
      healthSampleRateHz: 1,
      scmState: 'Running',
      scmStartupType: 'Automatic',
    ),
  );
  final lifecycle = ServiceLifecycleController(
    logger: logger,
    scm: _RunningScm(),
  );
  lifecycle.refresh();
  final tree = MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: ipc),
      ChangeNotifierProvider.value(value: connection),
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: timeline),
      ChangeNotifierProvider.value(value: diagnostics),
      ChangeNotifierProvider.value(value: frameMetrics),
      ChangeNotifierProvider.value(value: lifecycle),
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
        body: const DiagnosticsPage(title: 'Diagnostics'),
      ),
    ),
  );
  return (tree, settings, diagnostics, ipc);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('advanced off: budgets visible, identity and tools hidden',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final (tree, settings, _, _) = await _harness(advanced: false);
    expect(settings.showAdvancedDiagnostics, isFalse);

    await tester.pumpWidget(tree);
    await tester.pump(); // allow post-frame startPolling
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Performance budgets'), findsOneWidget);
    expect(find.text('Binary SHA-256'), findsNothing);
    expect(find.textContaining('Inject'), findsNothing);
    expect(find.text('Events dropped (service)'), findsOneWidget);
  });

  testWidgets('advanced on: identity and developer tools visible',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final (tree, settings, diag, ipc) = await _harness(advanced: true);
    expect(settings.showAdvancedDiagnostics, isTrue);
    expect(ipc.status.state, IpcConnectionState.connected);
    expect(diag.snapshot, isNotNull);

    await tester.pumpWidget(tree);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Live Monitoring'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Performance budgets'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Performance budgets'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Binary SHA-256'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Binary SHA-256'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Inject Test Event'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Inject Test Event'), findsOneWidget);
  });
}
