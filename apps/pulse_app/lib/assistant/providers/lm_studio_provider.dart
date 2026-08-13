import 'dart:convert';

import '../local_ai_chat.dart';
import '../local_ai_http.dart';
import '../local_ai_provider.dart';
import '../local_ai_types.dart';

/// LM Studio localhost API (models + OpenAI-compatible chat completions).
///
/// Probes OpenAI-compatible `GET /v1/models` first (verified local path),
/// then native `GET /api/v1/models`. Chat uses `POST /v1/chat/completions`.
/// Default base: `http://127.0.0.1:1234`
class LmStudioProvider implements LocalAiProvider {
  LmStudioProvider({
    LocalAiHttpClient? http,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 2),
    this.apiToken,
  })  : _http = http ?? const DartLocalAiHttpClient(),
        baseUri = baseUri ?? Uri.parse('http://127.0.0.1:1234') {
    DartLocalAiHttpClient.assertLocalhost(this.baseUri);
  }

  final LocalAiHttpClient _http;
  final Duration timeout;

  /// Optional Bearer token when LM Studio auth is enabled.
  final String? apiToken;

  @override
  final Uri baseUri;

  @override
  String get id => 'lm_studio';

  @override
  String get displayName => 'LM Studio';

  @override
  bool get isLocal => true;

  Map<String, String> get _headers {
    final token = apiToken?.trim();
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  @override
  Future<LocalAiProviderStatus> probe() async {
    try {
      // Prefer the verified OpenAI-compatible endpoint.
      final openAi = await _probeOpenAiCompat();
      if (openAi.state == LocalAiConnectionState.ready ||
          openAi.state == LocalAiConnectionState.unavailable) {
        return openAi;
      }

      // Fall back to native when OpenAI is missing/empty/errored.
      try {
        final native = await _probeNative();
        if (native != null) {
          if (native.state == LocalAiConnectionState.ready) return native;
          if (openAi.state == LocalAiConnectionState.noModels ||
              openAi.state == LocalAiConnectionState.notFound) {
            return native;
          }
        }
      } catch (_) {
        // Keep OpenAI result when native probe is unreachable.
      }
      return openAi;
    } catch (e) {
      if (isLocalAiConnectionFailure(e)) {
        return LocalAiProviderStatus.notFound(
          detail: 'LM Studio local server is not running',
        );
      }
      return LocalAiProviderStatus.error(
        message: e.toString(),
        detail: 'LM Studio probe failed',
      );
    }
  }

  Future<LocalAiProviderStatus?> _probeNative() async {
    final uri = baseUri.replace(path: '/api/v1/models');
    final response = await _http.get(uri, timeout: timeout, headers: _headers);
    if (response.statusCode == 404) return null;
    if (response.statusCode == 401 || response.statusCode == 403) {
      return LocalAiProviderStatus.unavailable(
        detail: 'LM Studio API requires authentication',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return LocalAiProviderStatus.error(
        message: 'HTTP ${response.statusCode}',
        detail: 'LM Studio returned HTTP ${response.statusCode}',
      );
    }

    return parseNativeModelsResponse(response.body);
  }

  Future<LocalAiProviderStatus> _probeOpenAiCompat() async {
    final uri = baseUri.replace(path: '/v1/models');
    final response = await _http.get(uri, timeout: timeout, headers: _headers);
    if (response.statusCode == 401 || response.statusCode == 403) {
      return LocalAiProviderStatus.unavailable(
        detail: 'LM Studio API requires authentication',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404) {
        return LocalAiProviderStatus.notFound(
          detail: 'LM Studio local server is not running',
        );
      }
      return LocalAiProviderStatus.error(
        message: 'HTTP ${response.statusCode}',
        detail: 'LM Studio returned HTTP ${response.statusCode}',
      );
    }

    return parseOpenAiModelsResponse(response.body);
  }

  /// Parses native `GET /api/v1/models` JSON.
  ///
  /// Skips entries with `type: "embedding"`. Missing `type` is allowed.
  static LocalAiProviderStatus parseNativeModelsResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return LocalAiProviderStatus.error(
        message: 'Malformed LM Studio response',
        detail: 'Expected a JSON object from /api/v1/models',
      );
    }
    final rawModels = decoded['models'];
    if (rawModels is! List) {
      return LocalAiProviderStatus.error(
        message: 'Malformed LM Studio response',
        detail: 'Missing "models" array',
      );
    }

    final models = <LocalAiModel>[];
    for (final item in rawModels) {
      if (item is! Map) continue;
      final type = item['type']?.toString();
      if (type == 'embedding') continue;
      // Missing type is OK — do not require type == "llm".
      if (type != null && type != 'llm') continue;

      final key = (item['key'] ?? item['modelKey'])?.toString().trim();
      if (key == null || key.isEmpty) continue;
      if (isEmbeddingModelId(key)) continue;

      final display =
          item['display_name']?.toString().trim().isNotEmpty == true
              ? item['display_name'].toString().trim()
              : key;
      final quant = item['quantization'];
      final meta = <String, Object?>{
        'type': ?type,
        'publisher': ?item['publisher'],
        'architecture': ?item['architecture'],
        'params_string': ?item['params_string'],
        'size_bytes': ?item['size_bytes'],
        'format': ?item['format'],
        if (quant is Map) 'quantization': ?quant['name'],
        'api': 'native',
      };
      models.add(LocalAiModel(id: key, displayName: display, metadata: meta));
    }

    if (models.isEmpty) {
      return LocalAiProviderStatus.noModels(
        detail: 'LM Studio is running but no LLM models are available',
      );
    }
    return LocalAiProviderStatus.ready(
      models: models,
      detail: 'LM Studio · ${models.length} model(s)',
    );
  }

  /// Parses OpenAI-compatible `GET /v1/models` JSON (`data[].id`).
  ///
  /// Does not require a `type` field. Excludes embedding IDs via heuristics.
  static LocalAiProviderStatus parseOpenAiModelsResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return LocalAiProviderStatus.error(
        message: 'Malformed LM Studio response',
        detail: 'Expected a JSON object from /v1/models',
      );
    }
    final data = decoded['data'];
    if (data is! List) {
      return LocalAiProviderStatus.error(
        message: 'Malformed LM Studio response',
        detail: 'Missing "data" array',
      );
    }

    final models = <LocalAiModel>[];
    for (final item in data) {
      if (item is! Map) continue;
      final id = item['id']?.toString().trim();
      if (id == null || id.isEmpty) continue;
      if (isEmbeddingModelId(id)) continue;
      models.add(
        LocalAiModel(
          id: id,
          displayName: id,
          metadata: {
            if (item['owned_by'] != null) 'owned_by': item['owned_by'],
            'api': 'openai_compat',
          },
        ),
      );
    }

    if (models.isEmpty) {
      return LocalAiProviderStatus.noModels(
        detail: 'LM Studio is running but no models are available',
      );
    }
    return LocalAiProviderStatus.ready(
      models: models,
      detail: 'LM Studio · ${models.length} model(s)',
    );
  }

  /// Heuristic for OpenAI-compat IDs that are embeddings (no `type` field).
  static bool isEmbeddingModelId(String id) {
    final n = id.toLowerCase();
    if (n.contains('text-embedding')) return true;
    if (n.contains('embedding')) return true;
    if (n.contains('-embed-') || n.contains('_embed_')) return true;
    if (n.startsWith('embed-') || n.startsWith('embed_')) return true;
    if (n.endsWith('-embed') || n.endsWith('_embed')) return true;
    return false;
  }

  @override
  Future<LocalAiChatTurn> chat(LocalAiChatRequest request) async {
    request.cancelToken?.throwIfCancelled();
    final uri = baseUri.replace(path: '/v1/chat/completions');
    final body = <String, Object?>{
      'model': request.modelId,
      'stream': request.stream,
      'messages': [
        for (final m in request.messages) _encodeMessage(m),
      ],
      if (request.tools.isNotEmpty)
        'tools': [
          for (final t in request.tools)
            {
              'type': 'function',
              'function': {
                'name': t.name,
                'description': t.description,
                'parameters': t.parameters,
              },
            },
        ],
    };

    try {
      if (request.stream) {
        return await _chatStreaming(uri, body, request);
      }
      final response = await _http.post(
        uri,
        body: jsonEncode(body),
        timeout: request.timeout,
        headers: _headers,
      );
      request.cancelToken?.throwIfCancelled();
      return _parseNonStream(response);
    } on LocalAiCancelledException {
      rethrow;
    } on LocalAiChatException {
      rethrow;
    } catch (e) {
      if (isLocalAiConnectionFailure(e)) {
        throw LocalAiChatException(
          'LM Studio is not available on localhost.',
          code: 'PROVIDER_UNAVAILABLE',
        );
      }
      throw LocalAiChatException(
        'Could not complete the LM Studio chat request.',
        code: 'PROVIDER_ERROR',
      );
    }
  }

  Future<LocalAiChatTurn> _chatStreaming(
    Uri uri,
    Map<String, Object?> body,
    LocalAiChatRequest request,
  ) async {
    final contentBuf = StringBuffer();
    final toolCallBuf = <int, _ToolCallAccum>{};
    String? finishReason;

    final response = await _http.post(
      uri,
      body: jsonEncode(body),
      timeout: request.timeout,
      headers: _headers,
      onStreamChunk: (chunk) {
        request.cancelToken?.throwIfCancelled();
        for (final line in chunk.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed == 'data: [DONE]') continue;
          final payload =
              trimmed.startsWith('data:') ? trimmed.substring(5).trim() : trimmed;
          if (payload.isEmpty || payload == '[DONE]') continue;
          Map? decoded;
          try {
            final obj = jsonDecode(payload);
            if (obj is Map) decoded = obj;
          } catch (_) {
            continue;
          }
          if (decoded == null) continue;
          final choices = decoded['choices'];
          if (choices is! List || choices.isEmpty) continue;
          final choice = choices.first;
          if (choice is! Map) continue;
          finishReason = choice['finish_reason']?.toString() ?? finishReason;
          final delta = choice['delta'];
          if (delta is! Map) continue;
          final text = delta['content']?.toString();
          if (text != null && text.isNotEmpty) {
            contentBuf.write(text);
            request.onTextDelta?.call(text);
          }
          final calls = delta['tool_calls'];
          if (calls is List) {
            for (final c in calls) {
              if (c is! Map) continue;
              final index = (c['index'] is int)
                  ? c['index'] as int
                  : int.tryParse('${c['index']}') ?? toolCallBuf.length;
              final acc = toolCallBuf.putIfAbsent(index, _ToolCallAccum.new);
              if (c['id'] != null) acc.id = c['id'].toString();
              final fn = c['function'];
              if (fn is Map) {
                if (fn['name'] != null) acc.name = fn['name'].toString();
                if (fn['arguments'] != null) {
                  acc.argsJson.write(fn['arguments'].toString());
                }
              }
            }
          }
        }
      },
    );

    request.cancelToken?.throwIfCancelled();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LocalAiChatException(
        'LM Studio returned HTTP ${response.statusCode}.',
        code: 'HTTP_ERROR',
      );
    }

    final toolCalls = <LocalAiToolCall>[];
    final keys = toolCallBuf.keys.toList()..sort();
    for (final k in keys) {
      final acc = toolCallBuf[k]!;
      if (acc.name == null || acc.name!.isEmpty) continue;
      toolCalls.add(
        LocalAiToolCall(
          id: acc.id ?? 'call_$k',
          name: acc.name!,
          arguments: _parseArgs(acc.argsJson.toString()),
        ),
      );
    }

    return LocalAiChatTurn(
      content: contentBuf.isEmpty ? null : contentBuf.toString(),
      toolCalls: toolCalls,
      finishReason: finishReason,
    );
  }

  LocalAiChatTurn _parseNonStream(LocalAiHttpResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LocalAiChatException(
        'LM Studio returned HTTP ${response.statusCode}.',
        code: 'HTTP_ERROR',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const LocalAiChatException(
        'Malformed response from LM Studio.',
        code: 'MALFORMED_RESPONSE',
      );
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const LocalAiChatException(
        'Malformed response from LM Studio.',
        code: 'MALFORMED_RESPONSE',
      );
    }
    final choice = choices.first;
    if (choice is! Map) {
      throw const LocalAiChatException(
        'Malformed response from LM Studio.',
        code: 'MALFORMED_RESPONSE',
      );
    }
    final message = choice['message'];
    if (message is! Map) {
      throw const LocalAiChatException(
        'Malformed response from LM Studio.',
        code: 'MALFORMED_RESPONSE',
      );
    }
    final content = message['content']?.toString();
    final calls = message['tool_calls'];
    return LocalAiChatTurn(
      content: content,
      toolCalls: calls is List ? _parseToolCalls(calls) : const [],
      finishReason: choice['finish_reason']?.toString(),
    );
  }

  Map<String, Object?> _encodeMessage(LocalAiChatMessage m) {
    switch (m.role) {
      case LocalAiMessageRole.system:
        return {'role': 'system', 'content': m.content ?? ''};
      case LocalAiMessageRole.user:
        return {'role': 'user', 'content': m.content ?? ''};
      case LocalAiMessageRole.assistant:
        return {
          'role': 'assistant',
          'content': m.content ?? '',
          if (m.toolCalls.isNotEmpty)
            'tool_calls': [
              for (final c in m.toolCalls)
                {
                  'id': c.id,
                  'type': 'function',
                  'function': {
                    'name': c.name,
                    'arguments': jsonEncode(c.arguments),
                  },
                },
            ],
        };
      case LocalAiMessageRole.tool:
        return {
          'role': 'tool',
          'content': m.content ?? '',
          'tool_call_id': m.toolCallId ?? '',
        };
    }
  }

  List<LocalAiToolCall> _parseToolCalls(List<dynamic> raw) {
    final out = <LocalAiToolCall>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) continue;
      final id = item['id']?.toString() ?? 'call_$i';
      final fn = item['function'];
      if (fn is! Map) continue;
      final name = fn['name']?.toString();
      if (name == null || name.isEmpty) continue;
      out.add(
        LocalAiToolCall(
          id: id,
          name: name,
          arguments: _parseArgs(fn['arguments']),
        ),
      );
    }
    return out;
  }

  Map<String, Object?> _parseArgs(Object? raw) {
    if (raw == null) return const {};
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return const {};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        return const {};
      }
    }
    return const {};
  }
}

class _ToolCallAccum {
  String? id;
  String? name;
  final StringBuffer argsJson = StringBuffer();
}
