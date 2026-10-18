import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'chat_config.dart';
import 'chat_message.dart';

typedef SelectImageFile = Future<XFile?> Function();

class ChatImageSelectionException implements Exception {
  const ChatImageSelectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ChatImagePicker {
  // The public name makes this test seam usable without exposing a private field.
  ChatImagePicker({ImagePicker? picker, SelectImageFile? selectFile})
    : _picker = picker ?? ImagePicker(),
      // ignore: prefer_initializing_formals
      _selectFile = selectFile;

  final ImagePicker _picker;
  final SelectImageFile? _selectFile;

  Future<ChatImageAttachment?> pick() async {
    try {
      final file = await (_selectFile ?? _pickFromGallery)();
      if (file == null) return null;

      late final int fileSize;
      try {
        fileSize = await file.length();
      } on Object {
        throw const ChatImageSelectionException(
          'Không đọc được kích thước ảnh. Hãy thử chọn lại file.',
        );
      }
      if (fileSize > ChatConfig.maxSourceImageBytes) {
        throw const ChatImageSelectionException(
          'Ảnh gốc quá lớn. Hãy chọn ảnh nhỏ hơn 10 MB.',
        );
      }

      late final Uint8List sourceBytes;
      try {
        sourceBytes = await file.readAsBytes();
      } on Object {
        throw const ChatImageSelectionException(
          'Không đọc được dữ liệu ảnh. Hãy thử chọn lại file.',
        );
      }
      final sourceMimeType = _mimeType(sourceBytes);
      if (sourceMimeType == null) {
        throw const ChatImageSelectionException(
          'Định dạng chưa được hỗ trợ. Hãy chọn ảnh JPEG hoặc PNG.',
        );
      }

      final dimensions = _readDimensions(sourceBytes, sourceMimeType);
      if (dimensions == null) {
        throw const ChatImageSelectionException(
          'Ảnh không có cấu trúc JPEG hoặc PNG hợp lệ. Hãy chọn ảnh khác.',
        );
      }
      if (dimensions.width * dimensions.height > 60 * 1000 * 1000) {
        throw const ChatImageSelectionException(
          'Độ phân giải ảnh quá lớn. Hãy chọn ảnh có tối đa 60 megapixel.',
        );
      }

      final processed =
          dimensions.width <= ChatConfig.maxImageDimension &&
              dimensions.height <= ChatConfig.maxImageDimension
          ? sourceBytes
          : await _resizeIfNeeded(
              sourceBytes,
              width: dimensions.width,
              height: dimensions.height,
            );
      if (processed.length > ChatConfig.maxImageBytes) {
        throw const ChatImageSelectionException(
          'Ảnh vẫn quá lớn sau khi thu nhỏ. Hãy chọn ảnh khác có dung lượng dưới 5 MB.',
        );
      }
      final mimeType = _mimeType(processed);
      if (mimeType == null) {
        throw const ChatImageSelectionException(
          'Không thể xử lý ảnh này. Hãy chọn ảnh JPEG hoặc PNG khác.',
        );
      }

      return ChatImageAttachment(
        bytes: processed,
        mimeType: mimeType,
        fileName: _fileName(file.name, mimeType),
      );
    } on ChatImageSelectionException {
      rethrow;
    } on PlatformException catch (error) {
      throw ChatImageSelectionException(
        error.code == 'photo_access_denied'
            ? 'Chưa được cấp quyền chọn ảnh.'
            : 'Không mở hoặc đọc được ảnh. Hãy thử chọn lại.',
      );
    } on Object {
      throw const ChatImageSelectionException(
        'Không đọc hoặc giải mã được ảnh. Hãy chọn một ảnh JPEG hoặc PNG hợp lệ.',
      );
    }
  }

  Future<XFile?> _pickFromGallery() => _picker.pickImage(
    source: ImageSource.gallery,
    requestFullMetadata: false,
  );

  Future<Uint8List> _resizeIfNeeded(
    Uint8List bytes, {
    required int width,
    required int height,
  }) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale =
          ChatConfig.maxImageDimension / (width > height ? width : height);
      final targetWidth = (width * scale)
          .round()
          .clamp(1, ChatConfig.maxImageDimension)
          .toInt();
      final targetHeight = (height * scale)
          .round()
          .clamp(1, ChatConfig.maxImageDimension)
          .toInt();
      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw const ChatImageSelectionException(
          'Không thể thu nhỏ ảnh này trong ứng dụng. Hãy chọn ảnh có cạnh dài tối đa 1280 px.',
        );
      }
      return data.buffer.asUint8List();
    } on ChatImageSelectionException {
      rethrow;
    } on Object {
      throw const ChatImageSelectionException(
        'Ảnh cần thu nhỏ nhưng trình duyệt hoặc thiết bị không thể xử lý ảnh này. Hãy chọn ảnh có cạnh dài tối đa 1280 px.',
      );
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static ({int width, int height})? _readDimensions(
    Uint8List bytes,
    String mimeType,
  ) => switch (mimeType) {
    'image/png' => _readPngDimensions(bytes),
    'image/jpeg' => _readJpegDimensions(bytes),
    _ => null,
  };

  static ({int width, int height})? _readPngDimensions(Uint8List bytes) {
    if (bytes.length < 33 ||
        _readUint32(bytes, 8) != 13 ||
        !_hasAsciiAt(bytes, 12, 'IHDR')) {
      return null;
    }
    final width = _readUint32(bytes, 16);
    final height = _readUint32(bytes, 20);
    if (width <= 0 || height <= 0) return null;

    var offset = 8;
    var sawImageData = false;
    while (offset <= bytes.length - 12) {
      final chunkLength = _readUint32(bytes, offset);
      if (chunkLength > bytes.length - offset - 12) return null;
      final typeOffset = offset + 4;
      if (offset == 8) {
        if (chunkLength != 13 || !_hasAsciiAt(bytes, typeOffset, 'IHDR')) {
          return null;
        }
      } else if (_hasAsciiAt(bytes, typeOffset, 'IHDR')) {
        return null;
      }

      if (_hasAsciiAt(bytes, typeOffset, 'IDAT')) sawImageData = true;
      if (_hasAsciiAt(bytes, typeOffset, 'IEND')) {
        if (chunkLength != 0 || !sawImageData || offset + 12 != bytes.length) {
          return null;
        }
        return (width: width, height: height);
      }
      offset += chunkLength + 12;
    }
    return null;
  }

  static ({int width, int height})? _readJpegDimensions(Uint8List bytes) {
    if (bytes.length < 4 ||
        bytes[0] != 0xFF ||
        bytes[1] != 0xD8 ||
        bytes[bytes.length - 2] != 0xFF ||
        bytes.last != 0xD9) {
      return null;
    }

    var offset = 2;
    while (offset < bytes.length) {
      if (bytes[offset] != 0xFF) return null;
      while (offset < bytes.length && bytes[offset] == 0xFF) {
        offset++;
      }
      if (offset >= bytes.length) return null;

      final marker = bytes[offset++];
      if (marker == 0x00 || marker == 0xD9 || marker == 0xDA) return null;
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        continue;
      }
      if (offset + 2 > bytes.length) return null;

      final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
      if (segmentLength < 2 || segmentLength > bytes.length - offset) {
        return null;
      }
      if (_isStartOfFrame(marker)) {
        if (segmentLength < 7) return null;
        final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
        final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
        if (width <= 0 || height <= 0) return null;
        return (width: width, height: height);
      }
      offset += segmentLength;
    }
    return null;
  }

  static bool _isStartOfFrame(int marker) => const {
    0xC0,
    0xC1,
    0xC2,
    0xC3,
    0xC5,
    0xC6,
    0xC7,
    0xC9,
    0xCA,
    0xCB,
    0xCD,
    0xCE,
    0xCF,
  }.contains(marker);

  static int _readUint32(Uint8List bytes, int offset) =>
      bytes[offset] * 0x1000000 +
      bytes[offset + 1] * 0x10000 +
      bytes[offset + 2] * 0x100 +
      bytes[offset + 3];

  static bool _hasAsciiAt(Uint8List bytes, int offset, String value) {
    if (offset + value.length > bytes.length) return false;
    for (var index = 0; index < value.length; index++) {
      if (bytes[offset + index] != value.codeUnitAt(index)) return false;
    }
    return true;
  }

  static String? _mimeType(Uint8List bytes) {
    const pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length >= pngSignature.length) {
      var isPng = true;
      for (var i = 0; i < pngSignature.length; i++) {
        if (bytes[i] != pngSignature[i]) {
          isPng = false;
          break;
        }
      }
      if (isPng) return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    return null;
  }

  static String _fileName(String name, String mimeType) {
    final extension = mimeType == 'image/png' ? 'png' : 'jpg';
    final base = name.trim().isEmpty ? 'image' : name.trim();
    final dot = base.lastIndexOf('.');
    return '${dot <= 0 ? base : base.substring(0, dot)}.$extension';
  }
}
