import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/application/assistant_controller.dart';
import 'package:pulse/application/settings_controller.dart';
import 'package:pulse/assistant/local_ai_http.dart';
import 'package:pulse/assistant/local_ai_types.dart';
import 'package:pulse/assistant/providers/lm_studio_provider.dart';
import 'package:pulse/assistant/providers/ollama_provider.dart';
import 'package:pulse/logging/app_logger.dart';
import 'package:pulse/platform/local_ai_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsController> _loadSettings([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final settings = SettingsController(logger: AppLogger());
  await settings.load();
  return settings;
}

/// A local runtime stand-in on 127.0.0.1 that records request headers.
class _FakeRuntime {
  _FakeRuntime._(this._server, this.requiredToken);

  final HttpServer _server;
  final String? requiredToken;
  final authorizationHeaders = <String?>[];

  int get port => _server.port;

  static Future<_FakeRuntime> start({String? requiredToken}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final runtime = _FakeRuntime._(server, requiredToken);
    server.listen(runtime._handle);
    return runtime;
  }

  void _handle(HttpRequest request) {
    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    authorizationHeaders.add(auth);
    final response = request.response;
    if (requiredToken != null && auth != 'Bearer $requiredToken') {
      response.statusCode = HttpStatus.unauthorized;
    } else if (request.uri.path == '/api/tags') {
      response.write(jsonEncode({
        'models': [
          {'name': 'llama3.2:latest'},
        ],
      }));
    } else if (request.uri.path == '/v1/models') {
      response.write(jsonEncode({
        'data': [
          {'id': 'google/gemma-4-12b-qat'},
        ],
      }));
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    response.close();
  }

  Future<void> close() => _server.close(force: true);
}

LocalAiProviderStatus? _status(AssistantController c, String id) =>
    c.snapshot.statusFor(id);

void main() {
  group('port settings', () {
    test('default to the runtimes\' standard ports', () async {
      final settings = await _loadSettings();
      expect(settings.assistantOllamaPort, LocalAiLoopback.ollamaDefaultPort);
      expect(
        settings.assistantLmStudioPort,
        LocalAiLoopback.lmStudioDefaultPort,
      );
    });

    test('valid ports persist; invalid ones are rejected', () async {
      final settings = await _loadSettings();
      expect(await settings.setAssistantOllamaPort(11500), isTrue);
      expect(await settings.setAssistantLmStudioPort(0), isFalse);
      expect(await settings.setAssistantLmStudioPort(65536), isFalse);
      expect(
        settings.assistantLmStudioPort,
        LocalAiLoopback.lmStudioDefaultPort,
      );

      final again = SettingsController(logger: AppLogger());
      await again.load();
      expect(again.assistantOllamaPort, 11500);
    });

    test('a corrupt stored port falls back to the default', () async {
      final settings = await _loadSettings({'assistant.ollama.port': 70000});
      expect(settings.assistantOllamaPort, LocalAiLoopback.ollamaDefaultPort);
    });

    test('the settings export carries ports but nothing token-like', () async {
      final settings = await _loadSettings();
      await settings.setAssistantLmStudioPort(4321);
      final map = settings.toMap();
      expect(map['assistant_lm_studio_port'], 4321);
      expect(
        map.keys.where((k) => k.contains('token') || k.contains('key')),
        isEmpty,
      );

      final imported = await _loadSettings();
      await imported.applyFromMap({
        'assistant_ollama_port': 'not a port',
        'assistant_lm_studio_port': 4321,
      });
      expect(imported.assistantOllamaPort, LocalAiLoopback.ollamaDefaultPort);
      expect(imported.assistantLmStudioPort, 4321);
    });

    test('reset restores the default ports', () async {
      final settings = await _loadSettings();
      await settings.setAssistantOllamaPort(11500);
      await settings.resetAll();
      expect(settings.assistantOllamaPort, LocalAiLoopback.ollamaDefaultPort);
    });
  });

  group('providers', () {
    test('a new port stays on 127.0.0.1', () {
      final ollama = OllamaProvider()..useLoopbackPort(11500);
      expect(ollama.baseUri.toString(), 'http://127.0.0.1:11500');
      expect(
        () => LmStudioProvider().useLoopbackPort(0),
        throwsArgumentError,
      );
    });

    test('"not running" says where Pulse looked', () async {
      // Bind and release a port so nothing listens on it.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final lmStudio = LmStudioProvider()..useLoopbackPort(port);
      final status = await lmStudio.probe();
      expect(status.state, LocalAiConnectionState.notFound);
      expect(status.detail, contains('127.0.0.1:$port'));
      expect(status.detail, contains('Developer'));
    });

    test('an API key prompt points to Settings, a wrong key says so',
        () async {
      final runtime = await _FakeRuntime.start(requiredToken: 'right');
      addTearDown(runtime.close);

      final lmStudio = LmStudioProvider()..useLoopbackPort(runtime.port);
      final missing = await lmStudio.probe();
      expect(missing.state, LocalAiConnectionState.unavailable);
      expect(missing.detail, contains('Settings → Privacy'));

      lmStudio.apiToken = 'wrong';
      final rejected = await lmStudio.probe();
      expect(rejected.detail, contains('rejected'));
    });
  });

  group('AssistantController', () {
    test('finds Ollama on the port saved in Settings', () async {
      final runtime = await _FakeRuntime.start();
      addTearDown(runtime.close);
      final settings = await _loadSettings();
      await settings.setAssistantOllamaPort(runtime.port);

      final controller = AssistantController(settings: settings);
      await controller.load();

      expect(_status(controller, 'ollama')?.state,
          LocalAiConnectionState.ready);
      expect(
        controller.registry.providerById('ollama')!.baseUri.port,
        runtime.port,
      );
    });

    test('sends the saved LM Studio key and nothing without one', () async {
      final runtime = await _FakeRuntime.start(requiredToken: 'secret-key');
      addTearDown(runtime.close);
      final settings = await _loadSettings();
      await settings.setAssistantLmStudioPort(runtime.port);
      final tokens = MemoryLocalAiTokenStore();

      final controller =
          AssistantController(settings: settings, tokenStore: tokens);
      await controller.load();
      expect(_status(controller, 'lm_studio')?.state,
          LocalAiConnectionState.unavailable);
      expect(runtime.authorizationHeaders.whereType<String>(), isEmpty);

      tokens.write('secret-key');
      await controller.refreshConnection();
      expect(_status(controller, 'lm_studio')?.state,
          LocalAiConnectionState.ready);
      expect(runtime.authorizationHeaders.last, 'Bearer secret-key');
    });

    test('the empty state lists what each runtime reported', () async {
      final settings = await _loadSettings();
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final unused = probe.port;
      await probe.close();
      await settings.setAssistantOllamaPort(unused);
      await settings.setAssistantLmStudioPort(unused);

      final controller = AssistantController(settings: settings);
      await controller.load();

      expect(controller.showNotFoundState, isTrue);
      expect(controller.providerStatusLines, hasLength(2));
      expect(
        controller.providerStatusLines,
        everyElement(contains('127.0.0.1:$unused')),
      );
    });
  });

  group('WindowsCredentialTokenStore', () {
    test('round-trips a key in Credential Manager', () {
      // A throwaway credential name, so the user's saved key is untouched.
      final store = WindowsCredentialTokenStore(
        logger: AppLogger(),
        targetName: 'Pulse/Test/${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(store.delete);

      expect(store.read(), isNull);
      expect(store.write('sk-local-ünicode'), isTrue);
      expect(store.read(), 'sk-local-ünicode');
      expect(store.delete(), isTrue);
      expect(store.read(), isNull);
      expect(store.delete(), isTrue, reason: 'deleting twice is not an error');
    }, skip: !Platform.isWindows);

    test('refuses an empty or oversized key', () {
      final store = WindowsCredentialTokenStore(
        logger: AppLogger(),
        targetName: 'Pulse/Test/${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(store.delete);
      expect(store.write(''), isFalse);
      expect(
        store.write('x' * (WindowsCredentialTokenStore.maxTokenBytes + 1)),
        isFalse,
      );
      expect(store.read(), isNull);
    }, skip: !Platform.isWindows);
  });
}
