import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'chat_config.dart';
import 'chat_message.dart';

enum LMStudioFailure { configuration, network, timeout, http, invalidResponse }

class LMStudioException implements Exception {
  const LMStudioException(
    this.kind,
    this.message, {
    this.statusCode,
    this.isWeb = kIsWeb,
  });

  final LMStudioFailure kind;
  final String message;
  final int? statusCode;
  final bool isWeb;

  String get userMessage => switch (kind) {
    LMStudioFailure.configuration => 'Cấu hình LM Studio chưa hợp lệ. Hãy kiểm tra LM_STUDIO_URL và LM_STUDIO_MODEL.',
    LMStudioFailure.network =>
      isWeb
          ? 'Không gọi được LM Studio. Hãy kiểm tra IP, cổng 1234 và máy chủ đang chạy. Nếu Console báo CORS, bật “Enable CORS” trong LM Studio rồi khởi động lại server.'
          : 'Không kết nối được LM Studio. Hãy kiểm tra địa chỉ mạng và trạng thái server.',
    LMStudioFailure.timeout =>
      'LM Studio phản hồi quá lâu. Hãy kiểm tra model đang chạy rồi thử lại.',
    LMStudioFailure.http =>
      'LM Studio trả về lỗi HTTP ${statusCode ?? ''}. Hãy kiểm tra model và server.',
    LMStudioFailure.invalidResponse =>
      'LM Studio trả về dữ liệu không hợp lệ. Hãy thử gửi lại.',
  };

  @override
  String toString() => 'LMStudioException($kind, $statusCode): $message';
}

abstract interface class ChatService {
  Future<ChatCompletion> complete(List<ChatMessage> history);

  void close();
}

typedef ChatServiceFactory = ChatService Function();

class LMStudioService implements ChatService {
  LMStudioService({
    http.Client? client,
    this.baseUrl = ChatConfig.baseUrl,
    this.model = ChatConfig.model,
    this.timeout = ChatConfig.requestTimeout,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final String model;
  final Duration timeout;

  @override
  void close() => _client.close();

  @override
  Future<ChatCompletion> complete(List<ChatMessage> history) async {
    final endpoint = _endpoint;
    if (model.trim().isEmpty) {
      throw const LMStudioException(
        LMStudioFailure.configuration,
        'LM_STUDIO_MODEL is empty.',
      );
    }

    final recentMessages = history.length <= ChatConfig.maxContextMessages
        ? history
        : history.skip(history.length - ChatConfig.maxContextMessages).toList();
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': ChatConfig.systemInstruction.trim()},
      for (final message in recentMessages)
        {'role': message.apiRole, 'content': message.content},
    ];

    try {
      final response = await _client
          .post(
            endpoint,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'max_tokens': ChatConfig.maxTokens,
              'temperature': 0.7,
              'stream': false,
            }),
          )
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LMStudioException(
          LMStudioFailure.http,
          'HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic> ||
          decoded['choices'] is! List ||
          (decoded['choices'] as List).isEmpty) {
        throw const LMStudioException(
          LMStudioFailure.invalidResponse,
          'Missing choices.',
        );
      }
      final choice = (decoded['choices'] as List).first;
      if (choice is! Map<String, dynamic> ||
          choice['message'] is! Map<String, dynamic>) {
        throw const LMStudioException(
          LMStudioFailure.invalidResponse,
          'Missing assistant message.',
        );
      }
      final message = choice['message'] as Map<String, dynamic>;
      final content = message['content'];
      if (content is! String || content.trim().isEmpty) {
        throw const LMStudioException(
          LMStudioFailure.invalidResponse,
          'Assistant content is empty.',
        );
      }
      final truncated =
          choice['finish_reason'] == 'length' ||
          choice['finish_reason'] == 'max_tokens';
      return ChatCompletion(content: content.trim(), truncated: truncated);
    } on LMStudioException {
      rethrow;
    } on TimeoutException catch (error) {
      throw LMStudioException(LMStudioFailure.timeout, error.message ?? '');
    } on http.ClientException catch (error) {
      throw LMStudioException(
        LMStudioFailure.network,
        error.message,
        isWeb: kIsWeb,
      );
    } on FormatException catch (error) {
      throw LMStudioException(LMStudioFailure.invalidResponse, error.message);
    } catch (error) {
      throw LMStudioException(LMStudioFailure.network, '$error', isWeb: kIsWeb);
    }
  }

  Uri get _endpoint {
    final value = baseUrl.trim();
    final parsed = Uri.tryParse(value);
    final path = parsed?.path.endsWith('/') == true
        ? parsed!.path.substring(0, parsed.path.length - 1)
        : parsed?.path;
    if (parsed == null ||
        !const {'http', 'https'}.contains(parsed.scheme) ||
        parsed.host.isEmpty ||
        parsed.query.isNotEmpty ||
        parsed.fragment.isNotEmpty ||
        parsed.userInfo.isNotEmpty ||
        (path!.isNotEmpty && path != '/' && path != '/v1')) {
      throw const LMStudioException(
        LMStudioFailure.configuration,
        'LM_STUDIO_URL must be an HTTP(S) origin with optional /v1 path.',
      );
    }
    return parsed.replace(path: '/v1/chat/completions');
  }
}
