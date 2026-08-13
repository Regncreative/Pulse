import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app/pulse_app.dart';
import 'app/theme/pulse_theme.dart';
import 'di/app_services.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  await Window.initialize();

  final launchHidden = args.contains('--background');

  const windowOptions = WindowOptions(
    size: Size(PulseTokens.windowDefaultWidth, PulseTokens.windowDefaultHeight),
    minimumSize: Size(PulseTokens.windowMinWidth, PulseTokens.windowMinHeight),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'Pulse',
    windowButtonVisibility: false,
  );
  await windowManager.setTitle('Pulse');
  await windowManager.waitUntilReadyToShow(windowOptions);

  final services = await AppServices.create();
  runApp(PulseRoot(services: services));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await Window.setEffect(effect: WindowEffect.mica, dark: true);
    } catch (_) {
      try {
        await Window.setEffect(effect: WindowEffect.acrylic, dark: true);
      } catch (_) {
        // Theme solid fill remains.
      }
    }

    await services.backgroundMode.start(launchHidden: launchHidden);

    final hideOnLaunch =
        launchHidden && services.settingsController.backgroundMode;
    if (!hideOnLaunch) {
      await windowManager.show();
      await windowManager.focus();
    }
  });
}

class PulseRoot extends StatelessWidget {
  const PulseRoot({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: services.ipcClient),
        Provider.value(value: services.logger),
        ChangeNotifierProvider.value(value: services.connectionController),
        ChangeNotifierProvider.value(value: services.settingsController),
        ChangeNotifierProvider.value(value: services.timelineSession),
        ChangeNotifierProvider.value(value: services.timelineLibrary),
        ChangeNotifierProvider.value(value: services.diagnosticsController),
        ChangeNotifierProvider.value(value: services.serviceLifecycle),
        ChangeNotifierProvider.value(value: services.clientFrameMetrics),
        ChangeNotifierProvider.value(value: services.healthNavigation),
        ChangeNotifierProvider.value(value: services.mcpIntegration),
        ChangeNotifierProvider.value(value: services.shellNavigation),
        ChangeNotifierProvider.value(value: services.backgroundMode),
        ChangeNotifierProvider.value(value: services.assistant),
      ],
      child: PulseApp(),
    );
  }
}
