import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/chat/chat_controller.dart';
import 'package:racing_client/chat/chat_message.dart';
import 'package:racing_client/chat/lm_studio_service.dart';

void main() {
  test('keeps full conversation and sends multi-turn history', () async {
    final service = _FakeChatService();
    final controller = ChatController(service);
    addTearDown(controller.dispose);

    await controller.send('Cách kết nối xe thế nào?');
    await controller.send('Còn nếu mất kết nối?');

    expect(controller.messages, hasLength(4));
    expect(controller.messages.last.content, 'Câu trả lời 2');
    expect(service.calls, hasLength(2));
    expect(service.calls.last.map((message) => message.content), [
      'Cách kết nối xe thế nào?',
      'Câu trả lời 1',
      'Còn nếu mất kết nối?',
    ]);
  });

  test('retry repeats the failed user turn without duplicating it', () async {
    final service = _FakeChatService()
      ..nextError = const LMStudioException(LMStudioFailure.network, 'offline');
    final controller = ChatController(service);
    addTearDown(controller.dispose);

    await controller.send('Hướng dẫn tinh chỉnh');
    expect(controller.messages, hasLength(1));
    expect(controller.canRetry, isTrue);
    expect(controller.error, contains('kết nối'));

    await controller.retry();
    expect(controller.messages, hasLength(2));
    expect(controller.messages.first.content, 'Hướng dẫn tinh chỉnh');
    expect(controller.messages.last.role, ChatRole.assistant);
    expect(service.calls, hasLength(2));
    expect(service.calls.first, service.calls.last);
  });

  test('does not append an empty message or submit while waiting', () async {
    final service = _FakeChatService()..pending = Completer<ChatCompletion>();
    final controller = ChatController(service);
    addTearDown(controller.dispose);

    await controller.send('   ');
    expect(controller.messages, isEmpty);

    final first = controller.send('Một câu hỏi');
    await controller.send('Câu hỏi thứ hai');
    expect(controller.messages, hasLength(1));
    expect(service.calls, hasLength(1));
    service.pending!.complete(const ChatCompletion(content: 'Xong'));
    await first;
    expect(controller.messages, hasLength(2));
  });
}

class _FakeChatService implements ChatService {
  final List<List<ChatMessage>> calls = [];
  Object? nextError;
  Completer<ChatCompletion>? pending;
  var _count = 0;
  bool closed = false;

  @override
  Future<ChatCompletion> complete(List<ChatMessage> history) async {
    calls.add(List.of(history));
    if (nextError case final error?) {
      nextError = null;
      throw error;
    }
    if (pending != null) return pending!.future;
    _count++;
    return ChatCompletion(content: 'Câu trả lời $_count');
  }

  @override
  void close() => closed = true;
}
