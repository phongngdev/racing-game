import 'dart:typed_data';

enum ChatRole { user, assistant }

class ChatImageAttachment {
  const ChatImageAttachment({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileName;
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.image,
    this.truncated = false,
  });

  final ChatRole role;
  final String content;
  final ChatImageAttachment? image;
  final bool truncated;

  String get apiRole => switch (role) {
    ChatRole.user => 'user',
    ChatRole.assistant => 'assistant',
  };
}

class ChatCompletion {
  const ChatCompletion({required this.content, this.truncated = false});

  final String content;
  final bool truncated;
}
