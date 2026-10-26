import 'dart:async';

import 'package:flutter/widgets.dart';

import 'collision_haptics.dart';
import 'controller_config.dart';
import 'controller_connection.dart';
import 'controller_protocol.dart';
import 'pairing_payload.dart';
import 'room_pairing_payload.dart';
import 'tilt_input.dart';
import '../racing/audio/race_audio.dart';

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
  int? _generation;
  PairingPayload? _pairingPayload;
  RoomPairingPayload? _roomPairingPayload;
  String? _resumeToken;
  bool _readyStageSent = false;
  bool _disposed = false;
  String message = 'Nhập địa chỉ WebSocket của PC rồi kết nối.';

  bool get isConnected => _connection?.isConnected == true && _registered;
  bool get isAttempting => _shouldReconnect;
  bool get isCalibrated => _tilt?.isCalibrated == true;
  bool get isReady =>
      isConnected && isCalibrated && (_tilt?.hasFreshSample ?? false);
  bool get throttlePressed => _throttlePressed;
  bool get reversePressed => _reversePressed;
  bool get vibrationEnabled => AudioSettingsController.shared.vibration;
  double get steering => _steering;
  bool get isPairing => _pairingPayload != null || _roomPairingPayload != null;
  String? get pairingLabel => _roomPairingPayload == null
      ? null
      : '${_roomPairingPayload!.slotId.toUpperCase()} · ${_roomPairingPayload!.slotId == 'p1' ? 'XE ĐỎ' : 'XE XANH'}';

  Future<VibrationResult> testVibration() =>
      _collisionHaptics.test(foreground: !_backgrounded && !_disposed);

  void setVibrationEnabled(bool enabled) {
    if (vibrationEnabled == enabled) return;
    AudioSettingsController.shared.setVibration(enabled);
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
    _pairingPayload = null;
    _roomPairingPayload = null;
    _resumeToken = null;
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

  Future<void> connectPairing(PairingPayload payload) async {
    if (payload.isExpired) {
      message = 'Mã QR đã hết hạn. Hãy tạo mã mới trên PC.';
      notifyListeners();
      return;
    }
    await _closeConnection();
    _pairingPayload = payload;
    _roomPairingPayload = null;
    _resumeToken = null;
    _uriText = payload.relayUrl.toString();
    _shouldReconnect = true;
    _sequence = 0;
    _readyStageSent = false;
    message = 'Đang ghép nối với phiên Practice…';
    _connection = ControllerConnection(
      uri: payload.relayUrl,
      role: ControllerRole.phone,
      registrationData: _pairingRegistrationData(),
      onEvent: _handleMessage,
    )..addListener(_handleConnectionChange);
    _connection!.connect();
    notifyListeners();
  }

  Future<void> resumePairing() async {
    final roomPayload = _roomPairingPayload;
    if (roomPayload != null) {
      await resumeRoomPairing();
      return;
    }
    final payload = _pairingPayload;
    if (payload == null || _resumeToken == null) {
      message = 'Quét mã QR mới để ghép nối lại.';
      notifyListeners();
      return;
    }
    await _closeConnection();
    _uriText = payload.relayUrl.toString();
    _shouldReconnect = true;
    _sequence = 0;
    _readyStageSent = false;
    message = 'Đang khôi phục phiên Practice…';
    _connection = ControllerConnection(
      uri: payload.relayUrl,
      role: ControllerRole.phone,
      registrationData: _pairingRegistrationData(),
      onEvent: _handleMessage,
    )..addListener(_handleConnectionChange);
    _connection!.connect();
    notifyListeners();
  }

  Future<void> connectRoomPairing(RoomPairingPayload payload) async {
    if (payload.isExpired) {
      message = 'Mã QR đã hết hạn. Hãy tạo mã mới trên Web.';
      notifyListeners();
      return;
    }
    await _closeConnection();
    _pairingPayload = null;
    _roomPairingPayload = payload;
    _resumeToken = null;
    _uriText = payload.relayUrl.toString();
    _shouldReconnect = true;
    _sequence = 0;
    _readyStageSent = false;
    message = 'Đang vào ${payload.slotId.toUpperCase()}…';
    _connection = ControllerConnection(
      uri: payload.relayUrl,
      role: ControllerRole.phone,
      registrationData: _roomPairingRegistrationData(),
      onEvent: _handleMessage,
    )..addListener(_handleConnectionChange);
    _connection!.connect();
    notifyListeners();
  }

  Future<void> resumeRoomPairing() async {
    final payload = _roomPairingPayload;
    if (payload == null || _resumeToken == null) {
      message = 'Quét lại QR hoặc yêu cầu Web tạo QR mới.';
      notifyListeners();
      return;
    }
    await _closeConnection();
    _uriText = payload.relayUrl.toString();
    _shouldReconnect = true;
    _sequence = 0;
    _readyStageSent = false;
    message = 'Đang khôi phục ${payload.slotId.toUpperCase()}…';
    _connection = ControllerConnection(
      uri: payload.relayUrl,
      role: ControllerRole.phone,
      registrationData: _roomPairingRegistrationData(),
      onEvent: _handleMessage,
    )..addListener(_handleConnectionChange);
    _connection!.connect();
    notifyListeners();
  }

  Map<String, Object?> _roomPairingRegistrationData() {
    final payload = _roomPairingPayload!;
    final resumeToken = _resumeToken;
    return {
      'role': 'phone',
      'version': 3,
      'action': resumeToken == null ? 'join' : 'resume',
      'roomId': payload.roomId,
      'slotId': payload.slotId,
      if (resumeToken == null)
        'pairingToken': payload.pairingToken
      else
        'resumeToken': resumeToken,
    };
  }

  Map<String, Object?> _pairingRegistrationData() {
    final payload = _pairingPayload!;
    final resumeToken = _resumeToken;
    return {
      'role': 'phone',
      'version': 2,
      if (resumeToken == null) ...{
        'action': 'join',
        'sessionId': payload.sessionId,
        'pairingToken': payload.pairingToken,
      } else ...{
        'action': 'resume',
        'sessionId': payload.sessionId,
        'resumeToken': resumeToken,
      },
    };
  }

  Future<void> disconnect() async {
    final roomPayload = _roomPairingPayload;
    final generation = _generation;
    if (roomPayload != null && generation != null && isConnected) {
      _connection?.send(ControllerEvents.slotLeave, {
        'roomId': roomPayload.roomId,
        'slotId': roomPayload.slotId,
        'generation': generation,
      });
      _roomPairingPayload = null;
      _resumeToken = null;
    }
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
    _readyStageSent = false;
    if (isPairing) _sendControllerState('calibrating');
    message = 'Giữ điện thoại ở tư thế thẳng trong nửa giây…';
    notifyListeners();
    final calibrated = await tilt.calibrate();
    if (_disposed) return false;
    if (calibrated) {
      _sensorUnavailableSent = false;
      if (isPairing) _sendControllerState('checking');
      message = 'Đã cân tâm. Nghiêng để lái và giữ nút để tăng tốc.';
    } else {
      if (isPairing) _sendControllerState('lost');
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
      if (_pairingPayload != null) {
        if (message.data['sessionId'] != _pairingPayload!.sessionId ||
            message.data['resumeToken'] is! String) {
          _shouldReconnect = false;
          this.message = 'Relay không xác nhận phiên Practice đã quét.';
          unawaited(_connection?.disconnect());
          notifyListeners();
          return;
        }
        _resumeToken = message.data['resumeToken'] as String;
        _connection?.registrationData = _pairingRegistrationData();
      } else if (_roomPairingPayload != null) {
        final payload = _roomPairingPayload!;
        if (message.data['roomId'] != payload.roomId ||
            message.data['slotId'] != payload.slotId ||
            message.data['resumeToken'] is! String ||
            message.data['generation'] is! int) {
          _shouldReconnect = false;
          this.message = 'Relay không xác nhận đúng slot Multiplayer.';
          unawaited(_connection?.disconnect());
          notifyListeners();
          return;
        }
        _resumeToken = message.data['resumeToken'] as String;
        _connection?.registrationData = _roomPairingRegistrationData();
      }
      _registered = true;
      _generation = message.data['generation'] is int
          ? message.data['generation'] as int
          : null;
      _sensorUnavailableSent = false;
      _readyStageSent = false;
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
      if (isPairing) {
        if (message.data['code'] == 'resume_pending') {
          this.message = 'Đang chờ relay đóng kết nối cũ rồi thử lại…';
        } else if (message.data['code'] == 'pairing_expired') {
          _shouldReconnect = false;
          this.message = 'Mã ghép nối đã hết hạn. Hãy quét mã mới.';
        } else if (message.data['code'] == 'phone_already_joined') {
          _shouldReconnect = false;
          this.message = 'Mã này đã được một điện thoại khác sử dụng.';
        } else if (message.data['code'] == 'resume_expired') {
          _shouldReconnect = false;
          this.message = _roomPairingPayload != null
              ? 'Slot đã hết thời gian giữ chỗ. Hãy quét QR mới.'
              : 'Không thể khôi phục phiên. Hãy quét mã mới trên PC.';
        } else if (message.data['code'] == 'slot_in_use' ||
            message.data['code'] == 'slot_reserved') {
          _shouldReconnect = false;
          this.message = 'Player slot này đang được điện thoại khác sử dụng.';
        } else if (message.data['code'] == 'slot_not_phone') {
          _shouldReconnect = false;
          this.message = 'Slot này hiện được cấu hình cho bàn phím.';
        } else {
          _shouldReconnect = false;
          this.message = 'Phiên Practice không còn hoạt động.';
        }
        if (!_shouldReconnect) unawaited(_connection?.disconnect());
      }
    } else if (message.event == ControllerEvents.sessionEnded ||
        message.event == ControllerEvents.roomClosed ||
        message.event == ControllerEvents.slotLeft) {
      _shouldReconnect = false;
      _registered = false;
      _setPedals(throttle: false, reverse: false, sendNow: false);
      _sendTimer?.cancel();
      unawaited(_stopTilt());
      this.message = _roomPairingPayload != null
          ? 'Kết nối slot đã kết thúc.'
          : 'Phiên Practice đã kết thúc.';
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
          foreground: isConnected && !_backgrounded && vibrationEnabled,
          currentGeneration: _generation,
          eventGeneration: eventGeneration,
          intensity: message.data['intensity'] is num
              ? (message.data['intensity'] as num).toDouble()
              : 0.5,
          isStillCurrent: () =>
              isConnected &&
              !_backgrounded &&
              vibrationEnabled &&
              _generation == eventGeneration,
        ),
      );
    } else if (message.event == ControllerEvents.haptic) {
      final event = message.data['event'];
      final eventGeneration = message.data['generation'] is int
          ? message.data['generation'] as int
          : null;
      if (event is String) {
        unawaited(
          _collisionHaptics.playCueForSession(
            event: event,
            foreground: isConnected && !_backgrounded && vibrationEnabled,
            currentGeneration: _generation,
            eventGeneration: eventGeneration,
            isStillCurrent: () =>
                isConnected &&
                !_backgrounded &&
                vibrationEnabled &&
                _generation == eventGeneration,
          ),
        );
      }
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
    if (isPairing) {
      _sendControllerState('checking');
    }
    _sendTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!isConnected) return;
      if (!tilt.hasFreshSample) {
        if (!_sensorUnavailableSent) {
          tilt.markUnavailable();
          _markSensorUnavailable();
        }
      } else {
        if (isPairing && _sensorUnavailableSent) {
          _sendControllerState('checking');
          message = 'Cảm biến sẵn sàng · cân tâm trước khi lái.';
        }
        _sensorUnavailableSent = false;
        if (tilt.isCalibrated) {
          _sendInput();
          if (isPairing && !_readyStageSent) {
            _readyStageSent = true;
            _sendControllerState('ready');
          }
        }
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
    if (isPairing) {
      _readyStageSent = false;
      _sendControllerState('lost');
    }
    final room = _roomPairingPayload;
    _connection?.send(ControllerEvents.unavailable, {
      'reason': 'sensor',
      if (room != null) ...{
        'roomId': room.roomId,
        'slotId': room.slotId,
        'generation': _generation,
      },
    });
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
    final room = _roomPairingPayload;
    _connection?.send(ControllerEvents.input, {
      'seq': _sequence++,
      'steering': tilt.steering,
      'throttle': _throttlePressed ? 1.0 : 0.0,
      'reverse': _reversePressed ? 1.0 : 0.0,
      'brake': 0.0,
      if (room != null) ...{
        'roomId': room.roomId,
        'slotId': room.slotId,
        'generation': _generation,
      },
    });
  }

  void _sendControllerState(String stage) {
    if (!isPairing || !isConnected) return;
    final room = _roomPairingPayload;
    _connection?.send(ControllerEvents.controllerState, {
      'stage': stage,
      if (room != null) ...{
        'roomId': room.roomId,
        'slotId': room.slotId,
        'generation': _generation,
      },
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
        state == AppLifecycleState.detached ||
        (isPairing &&
            (state == AppLifecycleState.inactive ||
                state == AppLifecycleState.hidden))) {
      _backgrounded = true;
      unawaited(_collisionHaptics.cancel());
      _setPedals(throttle: false, reverse: false, sendNow: true);
      if (_registered) {
        if (isPairing) _sendControllerState('lost');
        final room = _roomPairingPayload;
        _connection?.send(ControllerEvents.unavailable, {
          'reason': 'phone',
          if (room != null) ...{
            'roomId': room.roomId,
            'slotId': room.slotId,
            'generation': _generation,
          },
        });
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
    final room = _roomPairingPayload;
    if (room != null && _generation != null && isConnected) {
      _connection?.send(ControllerEvents.slotLeave, {
        'roomId': room.roomId,
        'slotId': room.slotId,
        'generation': _generation,
      });
    }
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _shouldReconnect = false;
    _sendTimer?.cancel();
    unawaited(_collisionHaptics.cancel());
    unawaited(_closeConnection());
    super.dispose();
  }
}
