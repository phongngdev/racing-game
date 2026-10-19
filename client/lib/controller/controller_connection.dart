import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'controller_protocol.dart';

enum ControllerRole { game, phone }

enum ControllerConnectionState { disconnected, connecting, connected }

class ControllerConnection extends ChangeNotifier {
  ControllerConnection({
    required this.uri,
    required this.role,
    required this.onEvent,
    this.registrationData,
  });

  final Uri uri;
  final ControllerRole role;
  final void Function(ControllerMessage message) onEvent;
  Map<String, Object?>? registrationData;
  bool autoReconnect = true;
  ControllerConnectionState state = ControllerConnectionState.disconnected;
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _retryTimer;
  Timer? _pingTimer;
  Timer? _connectTimer;
  final Stopwatch _clock = Stopwatch()..start();
  int _lastPongMs = 0;
  int _retryAttempt = 0;
  int _pingId = 0;
  bool _closed = false;

  bool get isConnected => state == ControllerConnectionState.connected;

  void connect() {
    if (state != ControllerConnectionState.disconnected) return;
    _closed = false;
    _retryTimer?.cancel();
    unawaited(_connectOnce());
  }

  Future<void> _connectOnce() async {
    if (_closed || state == ControllerConnectionState.connecting) return;
    state = ControllerConnectionState.connecting;
    notifyListeners();
    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _connectTimer?.cancel();
      _connectTimer = Timer(const Duration(seconds: 5), () {
        if (state != ControllerConnectionState.connected &&
            identical(channel, _channel)) {
          unawaited(channel.sink.close());
          _handleDisconnect(channel);
        }
      });
      _subscription = channel.stream.listen(
        _handleRawMessage,
        onError: (_) => _handleDisconnect(channel),
        onDone: () => _handleDisconnect(channel),
        cancelOnError: true,
      );
      await channel.ready;
      if (_closed || !identical(channel, _channel)) return;
      _send(
        ControllerEvents.register,
        registrationData ?? {'role': role.name, 'version': 1},
      );
    } catch (_) {
      _handleDisconnect(_channel);
    }
  }

  void _handleRawMessage(Object? raw) {
    final message = ControllerMessage.decode(raw);
    if (message == null) return;
    if (message.event == ControllerEvents.registered) {
      _connectTimer?.cancel();
      _connectTimer = null;
      _retryAttempt = 0;
      _lastPongMs = _clock.elapsedMilliseconds;
      state = ControllerConnectionState.connected;
      _startPing();
      notifyListeners();
    } else if (message.event == ControllerEvents.pong) {
      _lastPongMs = _clock.elapsedMilliseconds;
    } else if (message.event == ControllerEvents.sessionEnded) {
      _stopRetrying();
      final channel = _channel;
      if (channel != null) unawaited(channel.sink.close());
    } else if (message.event == ControllerEvents.error &&
        _isTerminalPairingError(message.data['code'])) {
      _stopRetrying();
    }
    onEvent(message);
  }

  bool _isTerminalPairingError(Object? code) => const {
    'invalid_pairing',
    'pairing_expired',
    'resume_expired',
    'phone_already_joined',
    'session_ended',
  }.contains(code);

  void _stopRetrying() {
    _closed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _startPing() {
    _pingTimer?.cancel();
    _connectTimer?.cancel();
    _connectTimer = null;
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isConnected) return;
      if (_clock.elapsedMilliseconds - _lastPongMs > 3000) {
        final channel = _channel;
        if (channel != null) unawaited(channel.sink.close());
        _handleDisconnect(channel);
        return;
      }
      _send(ControllerEvents.ping, {'id': ++_pingId});
    });
  }

  void _handleDisconnect(WebSocketChannel? channel) {
    if (channel != null && !identical(channel, _channel)) return;
    _pingTimer?.cancel();
    _connectTimer?.cancel();
    _connectTimer = null;
    _channel = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    if (state != ControllerConnectionState.disconnected) {
      state = ControllerConnectionState.disconnected;
      notifyListeners();
    }
    if (_closed || !autoReconnect || _retryTimer?.isActive == true) return;
    const delays = [500, 1000, 2000, 4000, 5000];
    final delay = delays[_retryAttempt.clamp(0, delays.length - 1)];
    _retryAttempt++;
    _retryTimer = Timer(Duration(milliseconds: delay), _connectOnce);
  }

  void send(String event, Map<String, Object?> data) => _send(event, data);

  void _send(String event, Map<String, Object?> data) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(ControllerMessage(event, data).encode());
    } catch (_) {
      _handleDisconnect(channel);
    }
  }

  Future<void> disconnect() async {
    _closed = true;
    _retryTimer?.cancel();
    _connectTimer?.cancel();
    _pingTimer?.cancel();
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
    if (state != ControllerConnectionState.disconnected) {
      state = ControllerConnectionState.disconnected;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _retryTimer?.cancel();
    _connectTimer?.cancel();
    _pingTimer?.cancel();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(channel.sink.close());
    state = ControllerConnectionState.disconnected;
    super.dispose();
  }
}
