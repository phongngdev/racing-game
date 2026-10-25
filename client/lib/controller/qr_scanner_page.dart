import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'room_pairing_payload.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage>
    with WidgetsBindingObserver {
  final MobileScannerController _camera = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startCamera();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_stopCamera());
    }
  }

  Future<void> _startCamera() async {
    if (_starting || _handled || !mounted) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      setState(() => _error = 'Quét QR hiện chỉ hỗ trợ trên Android.');
      return;
    }
    _starting = true;
    try {
      await _camera.start();
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) {
        final detail = error is MobileScannerException
            ? error.errorDetails?.message
            : null;
        setState(() {
          _error = detail?.isNotEmpty == true
              ? 'Không mở được camera: $detail'
              : 'Không mở được camera. Hãy cho phép quyền camera trong cài đặt ứng dụng rồi thử lại.';
        });
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _stopCamera() async {
    try {
      await _camera.stop();
    } catch (_) {
      // The camera can already be stopped while the route is leaving.
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    String? raw;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null) {
        raw = barcode.rawValue;
        break;
      }
    }
    if (raw == null) return;
    final payload = ScannedControllerPayload.tryParse(raw);
    if (payload == null) {
      setState(
        () => _error = 'Mã QR không phải mã phòng hoặc tay cầm Apex RC.',
      );
      return;
    }
    final expiresAt = switch (payload) {
      PracticeControllerPayload(:final payload) => payload.expiresAt,
      RoomControllerPayload(:final payload) => payload.expiresAt,
    };
    if (!DateTime.now().isBefore(expiresAt)) {
      setState(() => _error = 'Mã QR đã hết hạn. Hãy tạo mã mới trên PC.');
      return;
    }
    _handled = true;
    unawaited(_stopCamera());
    Navigator.of(context).pop(payload);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopCamera());
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final androidSupported =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return Scaffold(
      backgroundColor: const Color(0xFF111916),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111916),
        foregroundColor: Colors.white,
        title: const Text('Quét mã Apex RC'),
        actions: [
          IconButton(
            tooltip: 'Thử mở camera lại',
            onPressed: _startCamera,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !androidSupported
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Máy này chưa hỗ trợ quét QR bằng camera. Bạn vẫn có thể nhập WebSocket URL thủ công để debug.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: MobileScanner(
                          controller: _camera,
                          onDetect: _onDetect,
                          errorBuilder: (context, error) => ColoredBox(
                            color: const Color(0xFF1B2620),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  _error ??
                                      'Camera chưa sẵn sàng: ${error.errorCode.name}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
                  child: Column(
                    children: [
                      Text(
                        _error ?? 'Đưa camera vào mã QR đang hiển thị trên PC.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _error == null
                              ? Colors.white70
                              : const Color(0xFFFF9C92),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: _startCamera,
                          icon: const Icon(Icons.camera_alt_rounded),
                          label: const Text('Thử camera lại'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
