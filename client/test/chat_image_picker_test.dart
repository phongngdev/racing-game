import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:racing_client/chat/chat_config.dart';
import 'package:racing_client/chat/chat_image_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps the original bytes for small JPEG and PNG files', () async {
    final png = await _createPng(2, 2);
    final jpeg = base64Decode(
      '/9j/4AAQSkZJRgABAgAAAQABAAD//gAPTGF2YzYzLjEuMTAyAP/bAEMACAQEBAQEBQUFBQUFBgYGBgYGBgYGBgYGBgcHBwgICAcHBwYGBwcICAgICQkJCAgICAkJCgoKDAwLCw4ODhERFP/EAEwAAQEAAAAAAAAAAAAAAAAAAAAHAQEBAAAAAAAAAAAAAAAAAAAFBxABAAAAAAAAAAAAAAAAAAAAABEBAAAAAAAAAAAAAAAAAAAAAP/AABEIAAIAAgMBIgACEQADEQD/2gAMAwEAAhEDEQA/AI4Av4p//9k=',
    );
    final files = [
      (name: 'car.png', bytes: png, mime: 'image/png'),
      (name: 'car.jpg', bytes: jpeg, mime: 'image/jpeg'),
    ];

    for (final file in files) {
      final picker = ChatImagePicker(
        selectFile: () async {
          return XFile.fromData(
            file.bytes,
            name: file.name,
            mimeType: file.mime,
          );
        },
      );
      final image = await picker.pick();
      expect(image, isNotNull);
      expect(image!.mimeType, file.mime);
      expect(image.bytes, orderedEquals(file.bytes));
    }
  });

  test('resizes large images to a 1280 pixel maximum edge', () async {
    final source = await _createPng(1600, 800);
    final picker = ChatImagePicker(
      selectFile: () async =>
          XFile.fromData(source, name: 'large.png', mimeType: 'image/png'),
    );

    final image = await picker.pick();
    expect(image, isNotNull);
    expect(image!.mimeType, 'image/png');
    expect(image.bytes.length, lessThan(ChatConfig.maxImageBytes));

    final buffer = await ui.ImmutableBuffer.fromUint8List(image.bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    expect(descriptor.width, 1280);
    expect(descriptor.height, 640);
    descriptor.dispose();
    buffer.dispose();
  });

  test('rejects unsupported, corrupt and oversized files', () async {
    final unsupported = ChatImagePicker(
      selectFile: () async => XFile.fromData(
        Uint8List.fromList('GIF89a'.codeUnits),
        name: 'animation.gif',
      ),
    );
    await expectLater(
      unsupported.pick(),
      throwsA(isA<ChatImageSelectionException>()),
    );

    final corrupt = ChatImagePicker(
      selectFile: () async => XFile.fromData(
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00]),
        name: 'broken.jpg',
      ),
    );
    await expectLater(
      corrupt.pick(),
      throwsA(isA<ChatImageSelectionException>()),
    );

    final oversized = ChatImagePicker(
      selectFile: () async => XFile.fromData(
        Uint8List(ChatConfig.maxSourceImageBytes + 1),
        name: 'large.png',
      ),
    );
    await expectLater(
      oversized.pick(),
      throwsA(isA<ChatImageSelectionException>()),
    );
  });
}

Future<Uint8List> _createPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFF3267E3), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}
