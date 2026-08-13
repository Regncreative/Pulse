import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/application/settings_controller.dart';
import 'package:pulse/assistant/local_ai_chat.dart';
import 'package:pulse/assistant/local_ai_http.dart';
import 'package:pulse/assistant/local_ai_provider.dart';
import 'package:pulse/assistant/local_ai_types.dart';
import 'package:pulse/assistant/providers/lm_studio_provider.dart';
import 'package:pulse/assistant/providers/ollama_provider.dart';
import 'package:pulse/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ScriptedHttp implements LocalAiHttpClient {
  _ScriptedHttp(this._handlers);

  final Map<String, Future<LocalAiHttpResponse> Function()> _handlers;

  @override
  Future<LocalAiHttpResponse> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 2),
    Map<String, String> headers = const {},
  }) {
    DartLocalAiHttpClient.assertLocalhost(uri);
    final key = uri.path;
    final handler = _handlers[key];
    if (handler == null) {
      throw const SocketException('No handler');
    }
    return handler();
  }

  @override
  Future<LocalAiHttpResponse> post(
    Uri uri, {
    required String body,
    Duration timeout = const Duration(seconds: 120),
    Map<String, String> headers = const {},
    void Function(String chunk)? onStreamChunk,
  }) {
    throw UnimplementedError('post not used in probe tests');
  }
}

class _ConnFailHttp implements LocalAiHttpClient {
  @override
  Future<LocalAiHttpResponse> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 2),
    Map<String, String> headers = const {},
  }) async {
    throw const SocketException('Connection refused');
  }

  @override
  Future<LocalAiHttpResponse> post(
    Uri uri, {
    required String body,
    Duration timeout = const Duration(seconds: 120),
    Map<String, String> headers = const {},
    void Function(String chunk)? onStreamChunk,
  }) async {
    throw const SocketException('Connection refused');
  }
}

class _TimeoutHttp implements LocalAiHttpClient {
  @override
  Future<LocalAiHttpResponse> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 2),
    Map<String, String> headers = const {},
  }) async {
    throw TimeoutException('timed out');
  }

  @override
  Future<LocalAiHttpResponse> post(
    Uri uri, {
    required String body,
    Duration timeout = const Duration(seconds: 120),
    Map<String, String> headers = const {},
    void Function(String chunk)? onStreamChunk,
  }) async {
    throw TimeoutException('timed out');
  }
}

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
  Uri get baseUri => Uri.parse('http://127.0.0.1:1');

  @override
  Future<LocalAiProviderStatus> probe() async => status;

  @override
  Future<LocalAiChatTurn> chat(LocalAiChatRequest request) async {
    return const LocalAiChatTurn(content: 'ok');
  }
}

void main() {
  group('OllamaProvider', () {
    test('not running → notFound', () async {
      final p = OllamaProvider(http: _ConnFailHttp());
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.notFound);
    });

    test('timeout → notFound', () async {
      final p = OllamaProvider(http: _TimeoutHttp());
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.notFound);
    });

    test('running with no models', () async {
      final p = OllamaProvider(
        http: _ScriptedHttp({
          '/api/tags': () async => const LocalAiHttpResponse(
                statusCode: 200,
                body: '{"models":[]}',
              ),
        }),
      );
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.noModels);
    });

    test('running with one model', () async {
      final p = OllamaProvider(
        http: _ScriptedHttp({
          '/api/tags': () async => const LocalAiHttpResponse(
                statusCode: 200,
                body:
                    '{"models":[{"name":"llama3.2:latest","size":123,"details":{"family":"llama","parameter_size":"3B"}}]}',
              ),
        }),
      );
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.ready);
      expect(s.models, hasLength(1));
      expect(s.models.first.id, 'llama3.2:latest');
      expect(s.models.first.metadata['family'], 'llama');
    });

    test('running with multiple models', () async {
      final p = OllamaProvider(
        http: _ScriptedHttp({
          '/api/tags': () async => const LocalAiHttpResponse(
                statusCode: 200,
                body:
                    '{"models":[{"name":"a"},{"name":"b"},{"model":"c"}]}',
              ),
        }),
      );
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.ready);
      expect(s.models.map((m) => m.id), ['a', 'b', 'c']);
    });

    test('malformed response → error', () async {
      final p = OllamaProvider(
        http: _ScriptedHttp({
          '/api/tags': () async => const LocalAiHttpResponse(
                statusCode: 200,
                body: '{"models":"nope"}',
              ),
        }),
      );
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.error);
    });

    test('HTTP failure → error', () async {
      final p = OllamaProvider(
        http: _ScriptedHttp({
          '/api/tags': () async => const LocalAiHttpResponse(
                statusCode: 500,
                body: 'err',
              ),
        }),
      );
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.error);
    });
  });

  group('LmStudioProvider', () {
    test('not running → notFound', () async {
      final p = LmStudioProvider(http: _ConnFailHttp());
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.notFound);
    });

    test('timeout → notFound', () async {
      final p = LmStudioProvider(http: _TimeoutHttp());
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.notFound);
    });

    test('verified /v1/models response discovers Gemma and excludes embedding',
        () async {
      const verifiedBody = '''
{
  "data": [
    {
      "id": "google/gemma-4-12b-qat",
      "object": "model",
      "owned_by": "organization_owner"
    },
    {
      "id": "text-embedding-nomic-embed-text-v1.5",
      "object": "model",
      "owned_by": "organization_owner"
    }
  ],
  "object": "list"
}''';
      final p = LmStudioProvider(
        http: _ScriptedHttp({
          '/v1/models': () async => const LocalAiHttpResponse(
                statusCode: 200,
                body: verifiedBody,
              ),
        }),
      );
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.ready);
      expect(s.models, hasLength(1));
      expect(s.models.single.id, 'google/gemma-4-12b-qat');
      expect(
        s.models.any((m) => m.id.contains('embedding')),
        isFalse,
      );
    });

    test('parseOpenAiModelsResponse: missing type does not reject chat models',
        () {
      final s = LmStudioProvider.parseOpenAiModelsResponse('''
{
  "data": [
    {"id": "google/gemma-4-12b-qat", "object": "model"},
    {"id": "text-embedding-nomic-embed-text-v1.5", "object": "model"}
  ],
  "object": "list"
}''');
      expect(s.state, LocalAiConnectionState.ready);
      expect(s.models.map((m) => m.id), ['google/gemma-4-12b-qat']);
    });

    test('parseOpenAiModelsResponse: empty data → noModels', () {
      final s = LmStudioProvider.parseOpenAiModelsResponse(
        '{"data":[],"object":"list"}',
      );
      expect(s.state, LocalAiConnectionState.noModels);
    });

    test('parseOpenAiModelsResponse: only embeddings → noModels', () {
      final s = LmStudioProvider.parseOpenAiModelsResponse('''
{"data":[{"id":"text-embedding-nomic-embed-text-v1.5"}],"object":"list"}''');
      expect(s.state, LocalAiConnectionState.noModels);
    });

    test('running with no models (openai empty, native empty)', () async {
      final p = LmStudioProvider(
        http: _ScriptedHttp({
          '/v1/models': () async => const LocalAiHttpResponse(
                statusCode: 200,
                body: '{"data":[],"object":"list"}',
              ),
          '/api/v1/models': () async => const LocalAiHttpResponse(
                statusCode: 200,
                body: '{"models":[]}',
              ),
        }),
      );
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.noModels);
    });

    test('running with models (native fallback when openai 404)', () async {
      final p = LmStudioProvider(
        http: _ScriptedHttp({
          '/v1/models': () async => const LocalAiHttpResponse(
                statusCode: 404,
                body: 'missing',
              ),
          '/api/v1/models': () async => const LocalAiHttpResponse(
                statusCode: 200,
                body: '''
{
  "models": [
    {"type":"llm","key":"google/gemma","display_name":"Gemma","params_string":"2B"},
    {"type":"embedding","key":"embed","display_name":"Embed"}
  ]
}''',
              ),
        }),
      );
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.ready);
      expect(s.models, hasLength(1));
      expect(s.models.first.id, 'google/gemma');
      expect(s.models.first.displayName, 'Gemma');
    });

    test('native missing type still accepts chat model', () {
      final s = LmStudioProvider.parseNativeModelsResponse('''
{"models":[{"key":"google/gemma-4-12b-qat","display_name":"Gemma 4 12B QAT"}]}''');
      expect(s.state, LocalAiConnectionState.ready);
      expect(s.models.single.id, 'google/gemma-4-12b-qat');
    });

    test('malformed openai response → error', () async {
      final p = LmStudioProvider(
        http: _ScriptedHttp({
          '/v1/models': () async => const LocalAiHttpResponse(
                statusCode: 200,
                body: '{"data":123}',
              ),
        }),
      );
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.error);
    });

    test('auth required → unavailable', () async {
      final p = LmStudioProvider(
        http: _ScriptedHttp({
          '/v1/models': () async => const LocalAiHttpResponse(
                statusCode: 401,
                body: 'auth',
              ),
        }),
      );
      final s = await p.probe();
      expect(s.state, LocalAiConnectionState.unavailable);
    });

    test('isEmbeddingModelId heuristics', () {
      expect(
        LmStudioProvider.isEmbeddingModelId(
          'text-embedding-nomic-embed-text-v1.5',
        ),
        isTrue,
      );
      expect(
        LmStudioProvider.isEmbeddingModelId('google/gemma-4-12b-qat'),
        isFalse,
      );
    });
  });

  group('selection', () {
    test('no provider available', () {
      final snap = LocalAiProviderRegistry.resolveSelection(
        providers: [
          _FakeProvider(
            id: 'ollama',
            displayName: 'Ollama',
            status: LocalAiProviderStatus.notFound(),
          ),
        ],
        statuses: {
          'ollama': LocalAiProviderStatus.notFound(),
        },
      );
      expect(snap.state, LocalAiConnectionState.notFound);
    });

    test('previously selected model still exists', () {
      final models = [
        const LocalAiModel(id: 'a', displayName: 'A'),
        const LocalAiModel(id: 'b', displayName: 'B'),
      ];
      final snap = LocalAiProviderRegistry.resolveSelection(
        providers: [
          _FakeProvider(
            id: 'ollama',
            displayName: 'Ollama',
            status: LocalAiProviderStatus.ready(models: models),
          ),
        ],
        statuses: {
          'ollama': LocalAiProviderStatus.ready(models: models),
        },
        preferredProviderId: 'ollama',
        preferredModelId: 'b',
      );
      expect(snap.selectedModelId, 'b');
    });

    test('previously selected model no longer exists', () {
      final models = [const LocalAiModel(id: 'a', displayName: 'A')];
      final snap = LocalAiProviderRegistry.resolveSelection(
        providers: [
          _FakeProvider(
            id: 'ollama',
            displayName: 'Ollama',
            status: LocalAiProviderStatus.ready(models: models),
          ),
        ],
        statuses: {
          'ollama': LocalAiProviderStatus.ready(models: models),
        },
        preferredProviderId: 'ollama',
        preferredModelId: 'gone',
      );
      expect(snap.selectedProviderId, 'ollama');
      expect(snap.selectedModelId, isNull); // cleared — never auto-pick
    });

    test('one provider one model without preference stays unselected', () {
      final models = [const LocalAiModel(id: 'm', displayName: 'M')];
      final snap = LocalAiProviderRegistry.resolveSelection(
        providers: [
          _FakeProvider(
            id: 'ollama',
            displayName: 'Ollama',
            status: LocalAiProviderStatus.ready(models: models),
          ),
        ],
        statuses: {
          'ollama': LocalAiProviderStatus.ready(models: models),
        },
      );
      expect(snap.state, LocalAiConnectionState.ready);
      expect(snap.selectedProviderId, isNull);
      expect(snap.selectedModelId, isNull);
    });

    test('multiple providers available without preference', () {
      final models = [const LocalAiModel(id: 'm', displayName: 'M')];
      final snap = LocalAiProviderRegistry.resolveSelection(
        providers: [
          _FakeProvider(
            id: 'ollama',
            displayName: 'Ollama',
            status: LocalAiProviderStatus.ready(models: models),
          ),
          _FakeProvider(
            id: 'lm_studio',
            displayName: 'LM Studio',
            status: LocalAiProviderStatus.ready(models: models),
          ),
        ],
        statuses: {
          'ollama': LocalAiProviderStatus.ready(models: models),
          'lm_studio': LocalAiProviderStatus.ready(models: models),
        },
      );
      expect(snap.state, LocalAiConnectionState.ready);
      expect(snap.selectedProviderId, isNull);
    });

    test('multiple models without preference leaves model unset', () {
      final models = [
        const LocalAiModel(id: 'a', displayName: 'A'),
        const LocalAiModel(id: 'b', displayName: 'B'),
      ];
      final snap = LocalAiProviderRegistry.resolveSelection(
        providers: [
          _FakeProvider(
            id: 'ollama',
            displayName: 'Ollama',
            status: LocalAiProviderStatus.ready(models: models),
          ),
        ],
        statuses: {
          'ollama': LocalAiProviderStatus.ready(models: models),
        },
        preferredProviderId: 'ollama',
      );
      expect(snap.selectedProviderId, 'ollama');
      expect(snap.selectedModelId, isNull);
    });

    test('explicit persisted selection restored', () {
      final models = [
        const LocalAiModel(id: 'a', displayName: 'A'),
        const LocalAiModel(id: 'b', displayName: 'B'),
      ];
      final snap = LocalAiProviderRegistry.resolveSelection(
        providers: [
          _FakeProvider(
            id: 'lm_studio',
            displayName: 'LM Studio',
            status: LocalAiProviderStatus.ready(models: models),
          ),
        ],
        statuses: {
          'lm_studio': LocalAiProviderStatus.ready(models: models),
        },
        preferredProviderId: 'lm_studio',
        preferredModelId: 'b',
      );
      expect(snap.selectedProviderId, 'lm_studio');
      expect(snap.selectedModelId, 'b');
    });
  });

  group('settings persistence', () {
    test('selected provider and model persist', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsController(logger: AppLogger());
      await settings.load();
      await settings.setAssistantLocalAiSelection(
        providerId: 'ollama',
        modelId: 'llama3.2:latest',
      );
      expect(settings.assistantLocalAiProviderId, 'ollama');
      expect(settings.assistantLocalAiModelId, 'llama3.2:latest');

      final again = SettingsController(logger: AppLogger());
      await again.load();
      expect(again.assistantLocalAiProviderId, 'ollama');
      expect(again.assistantLocalAiModelId, 'llama3.2:latest');
    });
  });

  test('localhost guard rejects remote hosts', () {
    expect(
      () => DartLocalAiHttpClient.assertLocalhost(
        Uri.parse('http://example.com/api'),
      ),
      throwsArgumentError,
    );
  });
}
