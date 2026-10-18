import 'package:flutter/foundation.dart';

import 'chat_config.dart';
import 'chat_image_picker.dart';
import 'chat_message.dart';
import 'lm_studio_service.dart';

class ChatController extends ChangeNotifier {
  ChatController(
    this._service, {
    ChatImagePicker? imagePicker,
    Future<ChatImageAttachment?> Function()? imageSelector,
  }) : _imageSelector =
           imageSelector ?? (imagePicker ?? ChatImagePicker()).pick;

  final ChatService _service;
  final Future<ChatImageAttachment?> Function() _imageSelector;
  final List<ChatMessage> _messages = [];
  ChatImageAttachment? _pendingImage;
  bool _loading = false;
  bool _selectingImage = false;
  String? _error;
  String? _imageError;
  bool _disposed = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get loading => _loading;
  bool get selectingImage => _selectingImage;
  String? get error => _error;
  String? get imageError => _imageError;
  ChatImageAttachment? get pendingImage => _pendingImage;
  bool get canRetry => !_loading && _error != null && _messages.isNotEmpty;

  Future<void> selectImage() async {
    if (_loading || _selectingImage || _disposed) return;
    _selectingImage = true;
    _imageError = null;
    _notify();
    try {
      final image = await _imageSelector();
      if (_disposed) return;
      if (image != null) _pendingImage = image;
    } on ChatImageSelectionException catch (error) {
      if (_disposed) return;
      _imageError = error.message;
    } catch (_) {
      if (_disposed) return;
      _imageError = 'Không thể chọn ảnh. Hãy thử lại.';
    } finally {
      _selectingImage = false;
      _notify();
    }
  }

  void removePendingImage() {
    if (_loading || _disposed) return;
    _pendingImage = null;
    _imageError = null;
    _notify();
  }

  Future<void> send(String text) async {
    final content = text.trim();
    if (_loading ||
        _selectingImage ||
        _error != null ||
        (content.isEmpty && _pendingImage == null) ||
        _disposed) {
      return;
    }
    _messages.add(
      ChatMessage(
        role: ChatRole.user,
        content: content.isEmpty ? ChatConfig.defaultImagePrompt : content,
        image: _pendingImage,
      ),
    );
    _pendingImage = null;
    _imageError = null;
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
