import 'dart:async';

import 'package:flutter/widgets.dart';

import 'collision_haptics.dart';
import 'controller_config.dart';
import 'controller_connection.dart';
import 'controller_protocol.dart';
import 'tilt_input.dart';

class PhoneController extends ChangeNotifier with WidgetsBindingObserver {
  final CollisionHaptics _collisionHaptics = CollisionHaptics();

  PhoneController() {
    WidgetsBinding.instance.addObserver(this);
  }

  ControllerConnection? _connection;
  TiltInput? _tilt;
  Timer? _sendTimer;
  String? _uriText;
  int _sequence = 0;
  double _steering = 0;
  bool _registered = false;
  bool _sensorUnavailableSent = false;
  bool _backgrounded = false;
  bool _shouldReconnect = false;
  bool _throttlePressed = false;
  bool _reversePressed = false;
  bool _vibrationEnabled = true;
  int? _generation;
  bool _disposed = false;
  String message = 'Nhập địa chỉ WebSocket của PC rồi kết nối.';

  bool get isConnected => _connection?.isConnected == true && _registered;
  bool get isAttempting => _shouldReconnect;
  bool get isCalibrated => _tilt?.isCalibrated == true;
  bool get isReady =>
      isConnected && isCalibrated && (_tilt?.hasFreshSample ?? false);
  bool get throttlePressed => _throttlePressed;
  bool get reversePressed => _reversePressed;
  bool get vibrationEnabled => _vibrationEnabled;
  double get steering => _steering;

  Future<VibrationResult> testVibration() =>
      _collisionHaptics.test(foreground: !_backgrounded && !_disposed);

  void setVibrationEnabled(bool enabled) {
    if (_vibrationEnabled == enabled) return;
    _vibrationEnabled = enabled;
    if (!enabled) unawaited(_collisionHaptics.cancel());
    notifyListeners();
  }

  Future<void> connect(String value) async {
    final uri = ControllerConfig.parse(value);
    if (uri == null) {
      message = 'Địa chỉ phải bắt đầu bằng ws:// hoặc wss://.';
      notifyListeners();
      return;
    }
    await _closeConnection();
    _uriText = uri.toString();
    _shouldReconnect = true;
    _sequence = 0;
    message = 'Đang kết nối đến relay…';
    _connection = ControllerConnection(
      uri: uri,
      role: ControllerRole.phone,
      onEvent: _handleMessage,
    )..addListener(_handleConnectionChange);
    _connection!.connect();
    notifyListeners();
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _registered = false;
    _setPedals(throttle: false, reverse: false, sendNow: false);
    message = 'Đã ngắt kết nối.';
    await _closeConnection();
    notifyListeners();
  }

  Future<bool> calibrate() async {
    final tilt = _tilt;
    if (!isConnected || tilt == null || !tilt.hasFreshSample) {
      message = 'Chưa nhận được dữ liệu cảm biến.';
      notifyListeners();
      return false;
    }
    _setPedals(throttle: false, reverse: false, sendNow: false);
    message = 'Giữ điện thoại ở tư thế thẳng trong nửa giây…';
    notifyListeners();
    final calibrated = await tilt.calibrate();
    if (_disposed) return false;
    if (calibrated) {
      _sensorUnavailableSent = false;
      message = 'Đã cân tâm. Nghiêng để lái và giữ nút để tăng tốc.';
    } else {
      message = 'Không cân tâm được. Kiểm tra cảm biến rồi thử lại.';
    }
    notifyListeners();
    return calibrated;
  }

  void setThrottle(bool pressed) => _setPedals(
    throttle: pressed,
    reverse: pressed ? false : _reversePressed,
    sendNow: true,
  );

  void setReverse(bool pressed) => _setPedals(
    throttle: pressed ? false : _throttlePressed,
    reverse: pressed,
    sendNow: true,
  );

  void _setPedals({
    required bool throttle,
    required bool reverse,
    required bool sendNow,
  }) {
    if (!isReady && (throttle || reverse)) return;
    _throttlePressed = throttle;
    _reversePressed = reverse;
    if (sendNow) _sendInput();
    notifyListeners();
  }

  void _handleConnectionChange() {
    if (_disposed) return;
    if (_connection?.isConnected != true) {
      _registered = false;
      unawaited(_collisionHaptics.cancel());
      _sendTimer?.cancel();
      _sendTimer = null;
      unawaited(_stopTilt());
      _setPedals(throttle: false, reverse: false, sendNow: false);
      if (_shouldReconnect) {
        message = 'Relay ngắt kết nối · đang thử kết nối lại…';
      }
    }
    notifyListeners();
  }

  void _handleMessage(ControllerMessage message) {
    if (_disposed) return;
    if (message.event == ControllerEvents.registered &&
        message.data['role'] == 'phone') {
      _registered = true;
      _generation = message.data['generation'] is int
          ? message.data['generation'] as int
          : null;
      _sensorUnavailableSent = false;
      _sequence = 0;
      this.message = 'Đã nối relay · đang khởi động cảm biến…';
      unawaited(_startTilt());
    } else if (message.event == ControllerEvents.error) {
      this.message = message.data['code'] == 'role_in_use'
          ? 'Đã có điện thoại khác kết nối relay.'
          : 'Relay từ chối kết nối.';
      if (message.data['code'] == 'role_in_use') {
        _shouldReconnect = false;
        unawaited(_connection?.disconnect());
      }
    } else if (message.event == ControllerEvents.collision) {
      final eventGeneration = message.data['generation'] is int
          ? message.data['generation'] as int
          : null;
      debugPrint(
        '[ApexRC] Received collision vibration request '
        '(generation=$eventGeneration, current=$_generation).',
      );
      unawaited(
        _collisionHaptics.playForSession(
          foreground: isConnected && !_backgrounded && _vibrationEnabled,
          currentGeneration: _generation,
          eventGeneration: eventGeneration,
          isStillCurrent: () =>
              isConnected &&
              !_backgrounded &&
              _vibrationEnabled &&
              _generation == eventGeneration,
        ),
      );
    }
    notifyListeners();
  }

  Future<void> _startTilt() async {
    await _stopTilt();
    if (_disposed || !_registered) return;
    final tilt = TiltInput(
      shouldAutoCenter: () => !_throttlePressed && !_reversePressed,
      onSteering: (value) {
        _steering = value;
        if (!_disposed) notifyListeners();
      },
      onUnavailable: () {
        _markSensorUnavailable();
      },
    );
    _tilt = tilt;
    await tilt.start();
    if (_disposed || !_registered) {
      await _stopTilt();
      return;
    }
    _sendTimer?.cancel();
    _sendTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!isConnected) return;
      if (!tilt.hasFreshSample) {
        if (!_sensorUnavailableSent) {
          tilt.markUnavailable();
          _markSensorUnavailable();
        }
      } else {
        _sensorUnavailableSent = false;
        if (tilt.isCalibrated) _sendInput();
      }
      notifyListeners();
    });
    message = 'Cảm biến sẵn sàng · cân tâm trước khi lái.';
    notifyListeners();
  }

  void _markSensorUnavailable() {
    if (_disposed || _sensorUnavailableSent || !_registered) return;
    _sensorUnavailableSent = true;
    _setPedals(throttle: false, reverse: false, sendNow: false);
    _connection?.send(ControllerEvents.unavailable, {'reason': 'sensor'});
    message = 'Cảm biến chưa sẵn sàng.';
    notifyListeners();
  }

  void _sendInput() {
    final tilt = _tilt;
    if (!isConnected ||
        tilt == null ||
        !tilt.isCalibrated ||
        !tilt.hasFreshSample) {
      return;
    }
    _connection?.send(ControllerEvents.input, {
      'seq': _sequence++,
      'steering': tilt.steering,
      'throttle': _throttlePressed ? 1.0 : 0.0,
      'reverse': _reversePressed ? 1.0 : 0.0,
      'brake': 0.0,
    });
  }

  Future<void> _stopTilt() async {
    _sendTimer?.cancel();
    _sendTimer = null;
    final tilt = _tilt;
    _tilt = null;
    await tilt?.stop();
    _steering = 0;
  }

  Future<void> _closeConnection() async {
    _registered = false;
    _generation = null;
    await _collisionHaptics.cancel();
    await _stopTilt();
    final connection = _connection;
    _connection = null;
    connection?.removeListener(_handleConnectionChange);
    await connection?.disconnect();
    connection?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _backgrounded = true;
      unawaited(_collisionHaptics.cancel());
      _setPedals(throttle: false, reverse: false, sendNow: true);
      if (_registered) {
        _connection?.send(ControllerEvents.unavailable, {'reason': 'phone'});
      }
      _registered = false;
      _sendTimer?.cancel();
      unawaited(_stopTilt());
      unawaited(_connection?.disconnect());
      message = 'Controller tạm dừng khi ứng dụng ở nền.';
      notifyListeners();
    } else if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      if (_shouldReconnect && _uriText != null) {
        _connection?.connect();
        message = 'Đang kết nối lại · cần cân tâm lại.';
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _shouldReconnect = false;
    _sendTimer?.cancel();
    unawaited(_collisionHaptics.cancel());
    unawaited(_closeConnection());
    super.dispose();
  }
}
