import '../application/connection_controller.dart';
import '../application/diagnostics_controller.dart';
import '../application/settings_controller.dart';
import '../application/timeline_session_controller.dart';
import '../ipc/pulse_ipc_client.dart';
import '../logging/app_logger.dart';

class AppServices {
  AppServices({
    required this.ipcClient,
    required this.logger,
    required this.connectionController,
    required this.settingsController,
    required this.timelineSession,
    required this.diagnosticsController,
  });

  final PulseIpcClient ipcClient;
  final AppLogger logger;
  final ConnectionController connectionController;
  final SettingsController settingsController;
  final TimelineSessionController timelineSession;
  final DiagnosticsController diagnosticsController;

  static Future<AppServices> create() async {
    final logger = AppLogger();
    final settings = SettingsController(logger: logger);
    await settings.load();

    final ipc = PulseIpcClient();
    final connection = ConnectionController(ipc: ipc, logger: logger);
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

    await ipc.start();
    timeline.attach();

    return AppServices(
      ipcClient: ipc,
      logger: logger,
      connectionController: connection,
      settingsController: settings,
      timelineSession: timeline,
      diagnosticsController: diagnostics,
    );
  }
}
