enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.truncated = false,
  });

  final ChatRole role;
  final String content;
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
