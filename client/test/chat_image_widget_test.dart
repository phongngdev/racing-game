import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/chat/chat_controller.dart';
import 'package:racing_client/chat/chat_message.dart';
import 'package:racing_client/chat/chat_widgets.dart';
import 'package:racing_client/chat/lm_studio_service.dart';

void main() {
  testWidgets('shows the selected image preview and allows removing it', (
    tester,
  ) async {
    final attachment = _attachment();
    final controller = ChatController(
      _FakeChatService(),
      imageSelector: () async => attachment,
    );
    final draft = TextEditingController(text: 'What is this?');
    addTearDown(controller.dispose);
    addTearDown(draft.dispose);
    await tester.pumpWidget(_chatApp(controller, draft));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Chọn ảnh'));
    await tester.pumpAndSettle();
    expect(find.text('buggy.png'), findsOneWidget);
    expect(find.byTooltip('Xóa ảnh đính kèm'), findsOneWidget);

    await tester.tap(find.byTooltip('Xóa ảnh đính kèm'));
    await tester.pumpAndSettle();
    expect(find.text('buggy.png'), findsNothing);
    expect(controller.pendingImage, isNull);
    expect(draft.text, 'What is this?');
  });

  testWidgets('sends an image-only message and shows it in the transcript', (
    tester,
  ) async {
    final attachment = _attachment();
    final service = _FakeChatService();
    final controller = ChatController(
      service,
      imageSelector: () async => attachment,
    );
    final draft = TextEditingController();
    addTearDown(controller.dispose);
    addTearDown(draft.dispose);
    await tester.pumpWidget(_chatApp(controller, draft));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Chọn ảnh'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Gửi tin nhắn'));
    await tester.pumpAndSettle();

    expect(controller.messages.first.image, same(attachment));
    expect(service.lastHistory!.first.image, same(attachment));
    expect(find.textContaining('Hãy phân tích ảnh này'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(draft.text, isEmpty);
  });
}

Widget _chatApp(ChatController controller, TextEditingController draft) =>
    MaterialApp(
      home: Scaffold(
        body: ChatConversationView(
          controller: controller,
          draftController: draft,
        ),
      ),
    );

ChatImageAttachment _attachment() => ChatImageAttachment(
  bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
  mimeType: 'image/png',
  fileName: 'buggy.png',
);

class _FakeChatService implements ChatService {
  List<ChatMessage>? lastHistory;

  @override
  Future<ChatCompletion> complete(List<ChatMessage> history) async {
    lastHistory = List.of(history);
    return const ChatCompletion(content: 'Looks like an RC car.');
  }

  @override
  void close() {}
}
