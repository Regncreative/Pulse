import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimal HTTP GET for localhost-only local AI runtimes.
///
/// Refuses any non-loopback host. Does not bind sockets or expose ports.
class LocalAiHttpResponse {
  const LocalAiHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

abstract class LocalAiHttpClient {
  Future<LocalAiHttpResponse> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 2),
    Map<String, String> headers = const {},
  });

  Future<LocalAiHttpResponse> post(
    Uri uri, {
    required String body,
    Duration timeout = const Duration(seconds: 120),
    Map<String, String> headers = const {},
    void Function(String chunk)? onStreamChunk,
  });
}

class DartLocalAiHttpClient implements LocalAiHttpClient {
  const DartLocalAiHttpClient();

  static void assertLocalhost(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError('Only http(s) localhost URIs are allowed: $uri');
    }
    final host = uri.host.toLowerCase();
    const allowed = {'127.0.0.1', 'localhost', '::1'};
    if (!allowed.contains(host)) {
      throw ArgumentError(
        'Refusing non-localhost AI endpoint: ${uri.host}',
      );
    }
  }

  @override
  Future<LocalAiHttpResponse> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 2),
    Map<String, String> headers = const {},
  }) async {
    return _send('GET', uri, timeout: timeout, headers: headers);
  }

  @override
  Future<LocalAiHttpResponse> post(
    Uri uri, {
    required String body,
    Duration timeout = const Duration(seconds: 120),
    Map<String, String> headers = const {},
    void Function(String chunk)? onStreamChunk,
  }) async {
    return _send(
      'POST',
      uri,
      timeout: timeout,
      headers: {
        'Content-Type': 'application/json',
        ...headers,
      },
      body: body,
      onStreamChunk: onStreamChunk,
    );
  }

  Future<LocalAiHttpResponse> _send(
    String method,
    Uri uri, {
    required Duration timeout,
    Map<String, String> headers = const {},
    String? body,
    void Function(String chunk)? onStreamChunk,
  }) async {
    assertLocalhost(uri);
    final client = HttpClient();
    client.connectionTimeout = timeout;
    client.idleTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      headers.forEach(request.headers.set);
      if (body != null) {
        final bytes = utf8.encode(body);
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(timeout);
      if (onStreamChunk != null) {
        final buffer = StringBuffer();
        await for (final chunk in response.transform(utf8.decoder)) {
          buffer.write(chunk);
          onStreamChunk(chunk);
        }
        return LocalAiHttpResponse(
          statusCode: response.statusCode,
          body: buffer.toString(),
        );
      }
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return LocalAiHttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
      );
    } finally {
      client.close(force: true);
    }
  }
}

/// Connection failures that mean “runtime not listening”.
bool isLocalAiConnectionFailure(Object error) {
  if (error is TimeoutException) return true;
  if (error is SocketException) return true;
  if (error is HttpException) return true;
  if (error is HandshakeException) return true;
  return false;
}
