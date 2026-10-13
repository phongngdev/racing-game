import 'package:flutter/foundation.dart';

import 'chat_message.dart';
import 'lm_studio_service.dart';

class ChatController extends ChangeNotifier {
  ChatController(this._service);

  final ChatService _service;
  final List<ChatMessage> _messages = [];
  bool _loading = false;
  String? _error;
  bool _disposed = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get loading => _loading;
  String? get error => _error;
  bool get canRetry => !_loading && _error != null && _messages.isNotEmpty;

  Future<void> send(String text) async {
    final content = text.trim();
    if (_loading || _error != null || content.isEmpty || _disposed) return;
    _messages.add(ChatMessage(role: ChatRole.user, content: content));
    _error = null;
    await _request();
  }

  Future<void> retry() async {
    if (!canRetry || _disposed) return;
    _error = null;
    await _request();
  }

  Future<void> _request() async {
    _loading = true;
    _notify();
    try {
      final result = await _service.complete(List.unmodifiable(_messages));
      if (_disposed) return;
      _messages.add(
        ChatMessage(
          role: ChatRole.assistant,
          content: result.content,
          truncated: result.truncated,
        ),
      );
    } catch (error) {
      if (_disposed) return;
      _error = error is LMStudioException
          ? error.userMessage
          : 'Chưa gửi được tin nhắn. Hãy kiểm tra kết nối rồi thử lại.';
    } finally {
      _loading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _service.close();
    super.dispose();
  }
}
