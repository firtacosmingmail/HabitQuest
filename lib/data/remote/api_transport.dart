import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/backend_config.dart';
import 'api_exception.dart';

/// Sends JSON requests to the Edge Functions and maps failures to
/// [ApiException]. Knows nothing about sessions: callers pass the bearer
/// token they want to use.
class ApiTransport {
  final http.Client client;
  final BackendConfig config;
  final Duration timeout;

  ApiTransport({
    required this.client,
    required this.config,
    this.timeout = const Duration(seconds: 20),
  });

  /// Sends a request and returns the decoded JSON body (`null` for 204 or an
  /// empty body).
  Future<Object?> send(
    String method,
    String function, {
    List<String> path = const [],
    Map<String, String>? query,
    Object? body,
    String? accessToken,
  }) async {
    if (!config.isConfigured) {
      throw const ApiException(
        code: ApiException.notConfigured,
        message: 'SUPABASE_ANON_KEY is not configured for this build.',
      );
    }
    final request = http.Request(
      method,
      config.function(function, path: path, query: query),
    );
    request.headers['apikey'] = config.anonKey;
    request.headers['accept'] = 'application/json';
    if (accessToken != null) {
      request.headers['authorization'] = 'Bearer $accessToken';
    }
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await client.send(request),
      ).timeout(timeout);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        code: ApiException.networkError,
        message: 'The server took too long to answer.',
      );
    } catch (e) {
      // http.ClientException, SocketException, XMLHttpRequest errors (web)...
      throw ApiException(
        code: ApiException.networkError,
        message: 'Could not reach the server ($e).',
      );
    }

    final status = response.statusCode;
    final text = response.body;
    Object? decoded;
    if (text.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
        if (status >= 200 && status < 300) {
          throw ApiException(
            status: status,
            code: ApiException.badResponse,
            message: 'The server sent invalid JSON.',
          );
        }
      }
    }

    if (status >= 200 && status < 300) return decoded;
    throw _errorFrom(status, decoded);
  }

  /// Like [send] but requires a JSON object body.
  Future<Map<String, dynamic>> sendForObject(
    String method,
    String function, {
    List<String> path = const [],
    Map<String, String>? query,
    Object? body,
    String? accessToken,
  }) async {
    final result = await send(
      method,
      function,
      path: path,
      query: query,
      body: body,
      accessToken: accessToken,
    );
    if (result is Map<String, dynamic>) return result;
    throw const ApiException(
      code: ApiException.badResponse,
      message: 'Expected a JSON object from the server.',
    );
  }

  static ApiException _errorFrom(int status, Object? body) {
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map<String, dynamic>) {
        return ApiException(
          status: status,
          code: error['code'] as String? ?? _fallbackCode(status),
          message: error['message'] as String? ?? 'HTTP $status',
        );
      }
    }
    return ApiException(
      status: status,
      code: _fallbackCode(status),
      message: 'HTTP $status',
    );
  }

  static String _fallbackCode(int status) => switch (status) {
    401 => ApiException.unauthorized,
    404 => ApiException.notFound,
    429 => ApiException.rateLimited,
    >= 500 => ApiException.internalError,
    _ => 'http_$status',
  };
}
