import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pulse/app/theme/pulse_theme.dart';
import 'package:pulse/application/assistant_controller.dart';
import 'package:pulse/application/connection_controller.dart';
import 'package:pulse/application/settings_controller.dart';
import 'package:pulse/application/shell_navigation.dart';
import 'package:pulse/assistant/local_ai_chat.dart';
import 'package:pulse/assistant/local_ai_provider.dart';
import 'package:pulse/assistant/local_ai_types.dart';
import 'package:pulse/ipc/pulse_ipc_client.dart';
import 'package:pulse/logging/app_logger.dart';
import 'package:pulse/presentation/assistant/assistant_host.dart';
import 'package:pulse/presentation/assistant/assistant_page.dart';
import 'package:pulse/presentation/settings/settings_category.dart';
import 'package:pulse/presentation/shell/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeProvider implements LocalAiProvider {
  _FakeProvider({
    required this.id,
    required this.displayName,
    required this.status,
  });

  @override
  final String id;
  @override
  final String displayName;
  LocalAiProviderStatus status;

  @override
  bool get isLocal => true;

  @override
  Uri get baseUri => Uri.parse('http://127.0.0.1:9');

  @override
  Future<LocalAiProviderStatus> probe() async => status;

  @override
  Future<LocalAiChatTurn> chat(LocalAiChatRequest request) async {
    return const LocalAiChatTurn(content: 'ok');
  }
}

class _BlockingChatProvider implements LocalAiProvider {
  _BlockingChatProvider({
    required this.status,
    required this.nextTurn,
  });

  LocalAiProviderStatus status;
  final Future<LocalAiChatTurn> nextTurn;

  @override
  String get id => 'ollama';

  @override
  String get displayName => 'Ollama';

  @override
  bool get isLocal => true;

  @override
  Uri get baseUri => Uri.parse('http://127.0.0.1:9');

  @override
  Future<LocalAiProviderStatus> probe() async => status;

  @override
  Future<LocalAiChatTurn> chat(LocalAiChatRequest request) => nextTurn;
}

Future<AssistantController> _controller({
  required List<LocalAiProvider> providers,
  String? preferredProviderId,
  String? preferredModelId,
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsController(logger: AppLogger());
  await settings.load();
  if (preferredProviderId != null || preferredModelId != null) {
    await settings.setAssistantLocalAiSelection(
      providerId: preferredProviderId,
      modelId: preferredModelId,
    );
  }
  return AssistantController(
    settings: settings,
    registry: LocalAiProviderRegistry(
      providers: providers,
      preferredProviderId: settings.assistantLocalAiProviderId,
      preferredModelId: settings.assistantLocalAiModelId,
    ),
  );
}

Widget _wrapAssistantPage({
  required AssistantController assistant,
  required ShellNavigation shellNav,
}) {
  final ipc = PulseIpcClient();
  final connection = ConnectionController(ipc: ipc, logger: AppLogger());
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: assistant),
      ChangeNotifierProvider.value(value: shellNav),
      ChangeNotifierProvider.value(value: ipc),
      ChangeNotifierProvider.value(value: connection),
    ],
    child: MaterialApp(
      theme: PulseTheme.dark(),
      builder: (context, child) {
        PulseThemeScope.current =
            Theme.of(context).extension<PulseThemeData>()!;
        return child ?? const SizedBox.shrink();
      },
      home: Scaffold(
        body: AssistantHost(
          child: const AssistantPage(title: 'Assistant'),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Assistant page shows connection state without floating button',
      (tester) async {
    final assistant = await _controller(providers: const []);
    final shellNav = ShellNavigation();
    await tester.pumpWidget(
      _wrapAssistantPage(assistant: assistant, shellNav: shellNav),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Assistant'), findsWidgets);
    expect(find.text('Local AI not found'), findsWidgets);
    expect(find.text('Install a local AI'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('Explore MCP integrations opens AI Integration settings',
      (tester) async {
    final assistant = await _controller(providers: const []);
    final shellNav = ShellNavigation();
    await tester.pumpWidget(
      _wrapAssistantPage(assistant: assistant, shellNav: shellNav),
    );
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(find.text('Explore MCP integrations'));
    await tester.tap(find.text('Explore MCP integrations'));
    await tester.pump();

    expect(
      shellNav.pendingSettingsCategory,
      SettingsCategoryId.aiIntegration,
    );
    expect(shellNav.pendingShellPage, PulseShellPages.settings);
  });

  testWidgets('no models state shows guidance', (tester) async {
    final assistant = await _controller(
      providers: [
        _FakeProvider(
          id: 'ollama',
          displayName: 'Ollama',
          status: LocalAiProviderStatus.noModels(),
        ),
      ],
    );
    await assistant.load();
    await tester.pumpWidget(
      _wrapAssistantPage(assistant: assistant, shellNav: ShellNavigation()),
    );
    await tester.pump();

    expect(find.text('Local AI connected'), findsWidgets);
    expect(find.text('No local models found'), findsOneWidget);
  });

  testWidgets('ready without selection shows model picker, not chat',
      (tester) async {
    final models = [
      const LocalAiModel(id: 'a', displayName: 'Model A'),
      const LocalAiModel(id: 'b', displayName: 'Model B'),
    ];
    final assistant = await _controller(
      providers: [
        _FakeProvider(
          id: 'ollama',
          displayName: 'Ollama',
          status: LocalAiProviderStatus.ready(models: models),
        ),
      ],
    );
    await assistant.load();
    await tester.pumpWidget(
      _wrapAssistantPage(assistant: assistant, shellNav: ShellNavigation()),
    );
    await tester.pump();

    expect(assistant.selectedProvider, isNull);
    expect(assistant.selectedModel, isNull);
    expect(assistant.showChatUi, isFalse);
    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Select a provider'), findsOneWidget);
    expect(find.text('Ask about this PC…'), findsNothing);
  });

  testWidgets('explicit model selection enables chat; input clears after send',
      (tester) async {
    final gate = Completer<LocalAiChatTurn>();
    final provider = _BlockingChatProvider(
      status: LocalAiProviderStatus.ready(
        models: const [LocalAiModel(id: 'm', displayName: 'Model')],
      ),
      nextTurn: gate.future,
    );
    final assistant = await _controller(
      providers: [provider],
      preferredProviderId: 'ollama',
      preferredModelId: 'm',
    );
    await assistant.load();
    await tester.pumpWidget(
      _wrapAssistantPage(assistant: assistant, shellNav: ShellNavigation()),
    );
    await tester.pump();

    expect(assistant.showChatUi, isTrue);
    expect(find.text('Ask about this PC…'), findsOneWidget);
    // Chat-ready still exposes provider/model pickers for changing selection.
    expect(find.text('Provider'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();

    expect(find.text('hello'), findsWidgets); // user bubble (+ maybe brief field)
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    expect(assistant.awaitingReply, isTrue);

    gate.complete(const LocalAiChatTurn(content: 'world'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('world'), findsOneWidget);
  });

  testWidgets('persisted model can be changed from chat header', (tester) async {
    final models = [
      const LocalAiModel(id: 'a', displayName: 'Model A'),
      const LocalAiModel(id: 'b', displayName: 'Model B'),
    ];
    final assistant = await _controller(
      providers: [
        _FakeProvider(
          id: 'ollama',
          displayName: 'Ollama',
          status: LocalAiProviderStatus.ready(models: models),
        ),
      ],
      preferredProviderId: 'ollama',
      preferredModelId: 'a',
    );
    await assistant.load();
    await tester.pumpWidget(
      _wrapAssistantPage(assistant: assistant, shellNav: ShellNavigation()),
    );
    await tester.pump();

    expect(assistant.selectedModel?.id, 'a');
    expect(assistant.showChatUi, isTrue);

    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model B').last);
    await tester.pumpAndSettle();

    expect(assistant.selectedModel?.id, 'b');
    expect(assistant.showChatUi, isTrue);
  });

  testWidgets('single available model stays unselected until chosen',
      (tester) async {
    final assistant = await _controller(
      providers: [
        _FakeProvider(
          id: 'lm_studio',
          displayName: 'LM Studio',
          status: LocalAiProviderStatus.ready(
            models: const [
              LocalAiModel(id: 'google/gemma-4-12b-qat', displayName: 'Gemma'),
            ],
          ),
        ),
      ],
    );
    await assistant.load();
    expect(assistant.selectedProviderIdOrNull, isNull);
    expect(assistant.selectedModel, isNull);
    expect(assistant.showChatUi, isFalse);
  });
}

extension on AssistantController {
  String? get selectedProviderIdOrNull => snapshot.selectedProviderId;
}
