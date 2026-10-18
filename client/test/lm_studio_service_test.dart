import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:racing_client/chat/chat_config.dart';
import 'package:racing_client/chat/chat_message.dart';
import 'package:racing_client/chat/lm_studio_service.dart';

void main() {
  test('sends system instruction and only the latest 20 messages', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Xin chào bạn'},
                'finish_reason': 'stop',
              },
            ],
          }),
        ),
        200,
      );
    });
    final service = LMStudioService(
      client: client,
      baseUrl: 'http://127.0.0.1:1234/v1/',
    );
    addTearDown(service.close);
    final history = [
      for (var i = 0; i < 24; i++)
        ChatMessage(
          role: i.isEven ? ChatRole.user : ChatRole.assistant,
          content: 'message-$i',
        ),
    ];

    final result = await service.complete(history);

    expect(
      captured.url.toString(),
      'http://127.0.0.1:1234/v1/chat/completions',
    );
    expect(captured.headers['authorization'], isNull);
    final payload = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(payload['model'], 'google/gemma-4-e2b');
    expect(payload['stream'], isFalse);
    final messages = payload['messages'] as List<dynamic>;
    expect(messages, hasLength(21));
    expect(messages.first['role'], 'system');
    expect(messages.first['content'], ChatConfig.systemInstruction.trim());
    expect(messages[1]['content'], 'message-4');
    expect(messages.last['content'], 'message-23');
    expect(result.content, 'Xin chào bạn');
  });

  test('reports a completion cut off by the token limit', () async {
    final service = LMStudioService(
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Câu trả lời'},
                  'finish_reason': 'length',
                },
              ],
            }),
          ),
          200,
        ),
      ),
    );
    addTearDown(service.close);

    final response = await service.complete([
      const ChatMessage(role: ChatRole.user, content: 'Xin chào'),
    ]);

    expect(response.truncated, isTrue);
  });

  test(
    'sends JPEG and PNG as Base64 data URLs on the attached turn only',
    () async {
      for (final fixture in [
        (mime: 'image/jpeg', bytes: <int>[0xFF, 0xD8, 0xFF, 0x01]),
        (mime: 'image/png', bytes: <int>[137, 80, 78, 71, 13, 10, 26, 10]),
      ]) {
        late http.Request captured;
        final imageService = LMStudioService(
          client: MockClient((request) async {
            captured = request;
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'choices': [
                    {
                      'message': {'content': 'Đã xem ảnh.'},
                      'finish_reason': 'stop',
                    },
                  ],
                }),
              ),
              200,
            );
          }),
        );
        final image = ChatImageAttachment(
          bytes: Uint8List.fromList(fixture.bytes),
          mimeType: fixture.mime,
          fileName: 'test.${fixture.mime == 'image/png' ? 'png' : 'jpg'}',
        );
        await imageService.complete([
          ChatMessage(
            role: ChatRole.user,
            content: 'Phân tích ảnh',
            image: image,
          ),
        ]);
        final requestMessages =
            (jsonDecode(captured.body) as Map<String, dynamic>)['messages']
                as List<dynamic>;
        final content = requestMessages.last['content'] as List<dynamic>;
        final imageUrl = (content.last['image_url'] as Map)['url'] as String;
        expect(
          imageUrl,
          'data:${fixture.mime};base64,${base64Encode(image.bytes)}',
        );
        expect(base64Decode(imageUrl.split(',').last), image.bytes);
        imageService.close();
      }

      final oldImage = ChatImageAttachment(
        bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x01]),
        mimeType: 'image/jpeg',
        fileName: 'old.jpg',
      );
      late http.Request followUpRequest;
      final followUpService = LMStudioService(
        client: MockClient((request) async {
          followUpRequest = request;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'Hãy gửi lại ảnh để xem chi tiết.'},
                    'finish_reason': 'stop',
                  },
                ],
              }),
            ),
            200,
          );
        }),
      );
      addTearDown(followUpService.close);
      await followUpService.complete([
        ChatMessage(
          role: ChatRole.user,
          content: 'Phân tích ảnh',
          image: oldImage,
        ),
        const ChatMessage(
          role: ChatRole.assistant,
          content: 'Một chiếc xe RC.',
        ),
        const ChatMessage(role: ChatRole.user, content: 'Nhãn hiệu nào?'),
      ]);
      final followUpMessages =
          (jsonDecode(followUpRequest.body) as Map<String, dynamic>)['messages']
              as List<dynamic>;
      expect(followUpMessages[1]['content'], 'Phân tích ảnh');
      expect(followUpMessages[3]['content'], 'Nhãn hiệu nào?');
      expect(followUpRequest.body, isNot(contains('data:image/')));
    },
  );

  test('classifies malformed responses and server failures', () async {
    final malformed = LMStudioService(
      client: MockClient((_) async => http.Response('not-json', 200)),
    );
    addTearDown(malformed.close);
    await expectLater(
      malformed.complete([
        const ChatMessage(role: ChatRole.user, content: 'Xin chào'),
      ]),
      throwsA(
        isA<LMStudioException>().having(
          (error) => error.kind,
          'kind',
          LMStudioFailure.invalidResponse,
        ),
      ),
    );

    final serverError = LMStudioService(
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );
    addTearDown(serverError.close);
    await expectLater(
      serverError.complete([
        const ChatMessage(role: ChatRole.user, content: 'Xin chào'),
      ]),
      throwsA(
        isA<LMStudioException>().having(
          (error) => error.statusCode,
          'status code',
          503,
        ),
      ),
    );
  });

  test('explains the CORS setting for browser network failures', () async {
    final service = LMStudioService(
      client: MockClient(
        (_) async => throw http.ClientException('XMLHttpRequest error.'),
      ),
    );
    addTearDown(service.close);

    await expectLater(
      service.complete([
        const ChatMessage(role: ChatRole.user, content: 'Xin chào'),
      ]),
      throwsA(
        isA<LMStudioException>().having(
          (error) => error.kind,
          'kind',
          LMStudioFailure.network,
        ),
      ),
    );
    expect(
      const LMStudioException(
        LMStudioFailure.network,
        'browser request blocked',
        isWeb: true,
      ).userMessage,
      contains('Enable CORS'),
    );
  });
}
