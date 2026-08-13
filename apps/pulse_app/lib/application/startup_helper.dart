import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';

import '../logging/app_logger.dart';

/// User-session autostart for Pulse.exe (not PulseService).
///
/// Uses the OS-supported startup registration provided by `launch_at_startup`
/// (Windows Run-key / equivalent). Does not modify SCM or the service.
Future<void> configureLaunchAtStartup({
  required bool enabled,
  required AppLogger logger,
}) async {
  if (!Platform.isWindows) return;
  try {
    launchAtStartup.setup(
      appName: 'Pulse Diagnostics',
      appPath: Platform.resolvedExecutable,
      args: const ['--background'],
    );
    final isEnabled = await launchAtStartup.isEnabled();
    if (enabled && !isEnabled) {
      await launchAtStartup.enable();
      logger.info('Startup', 'Enabled Start Pulse with Windows');
    } else if (!enabled && isEnabled) {
      await launchAtStartup.disable();
      logger.info('Startup', 'Disabled Start Pulse with Windows');
    }
  } catch (e) {
    logger.warn('Startup', 'configureLaunchAtStartup failed: $e');
  }
}
