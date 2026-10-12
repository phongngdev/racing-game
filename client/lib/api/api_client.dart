import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

typedef AccessTokenReader = String? Function();
typedef UnauthorizedHandler = Future<void> Function(String token);

class ApiClient {
  ApiClient({
    required this.baseUri,
    required AccessTokenReader readAccessToken,
    required http.Client client,
    UnauthorizedHandler? onUnauthorized,
    this.timeout = const Duration(seconds: 15),
  }) {
    _readAccessToken = readAccessToken;
    _client = client;
    _onUnauthorized = onUnauthorized;
  }

  final Uri baseUri;
  late final AccessTokenReader _readAccessToken;
  late final http.Client _client;
  late final UnauthorizedHandler? _onUnauthorized;
  final Duration timeout;

  void close() => _client.close();

  Future<Object?> get(String path) => _send('GET', path);

  Future<Object?> post(String path, Map<String, Object?> body) =>
      _send('POST', path, body: body);

  Future<Object?> put(String path, Map<String, Object?> body) =>
      _send('PUT', path, body: body);

  Future<Object?> delete(String path) => _send('DELETE', path);

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final token = _readAccessToken();
    final request = http.Request(method, _resolve(path))
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    try {
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed)
          .timeout(timeout);
      final decoded = _decode(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final exception = ApiException(
          kind: ApiFailureKind.http,
          statusCode: response.statusCode,
          message: _messageFrom(decoded, response.reasonPhrase),
        );
        if (response.statusCode == 401 && token != null) {
          await _onUnauthorized?.call(token);
        }
        throw exception;
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        kind: ApiFailureKind.timeout,
        message: 'The request timed out.',
      );
    } on http.ClientException catch (error) {
      throw ApiException(kind: ApiFailureKind.network, message: error.message);
    } on FormatException catch (error) {
      throw ApiException(
        kind: ApiFailureKind.invalidResponse,
        message: error.message,
      );
    }
  }

  Uri _resolve(String path) {
    final relative = path.startsWith('/') ? path.substring(1) : path;
    return baseUri.resolve(relative);
  }

  Object? _decode(http.Response response) {
    if (response.statusCode == 204 || response.bodyBytes.isEmpty) return null;
    final body = utf8.decode(response.bodyBytes);
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  }

  String _messageFrom(Object? body, String? fallback) {
    if (body is Map<String, dynamic>) {
      final value = body['message'];
      if (value is String && value.isNotEmpty) return value;
      if (value is List) return value.map((item) => '$item').join(' ');
    }
    return fallback ?? 'The request failed.';
  }
}
