import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controller/controller_connection.dart';
import '../controller/controller_protocol.dart';
import '../controller/pairing_payload.dart';
import 'input/remote_input_source.dart';

enum PracticeControllerState {
  connectingRelay,
  waitingForPhone,
  checking,
  calibrating,
  neutralRequired,
  ready,
  lost,
  relayLost,
  ended,
  expired,
  error,
}

typedef PracticeSessionConnectionFactory = ControllerConnection Function({
  required Uri uri,
  required ControllerRole role,
  required void Function(ControllerMessage) onEvent,
  required Map<String, Object?> registrationData,
});

class PracticeControllerSession extends ChangeNotifier {
  PracticeControllerSession({
    required this.relayUrl,
    PracticeSessionConnectionFactory? connectionFactory,
    RemoteInputSource? remoteInput,
    DateTime Function()? now,
  }) : remoteInput = remoteInput ?? RemoteInputSource(),
       _now = now ?? DateTime.now {
    final factory = connectionFactory ?? _defaultConnectionFactory;
    _connection = factory(
      uri: relayUrl,
      role: ControllerRole.game,
      onEvent: _handleMessage,
      registrationData: const {
        'role': 'game',
        'version': 2,
        'action': 'create',
      },
    )..addListener(_handleConnectionChange);
    _connection.connect();
    _watchdog = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_ended) return;
      final previousState = _state;
      if (_pairing != null && !_phoneConnected && _pairing!.isExpired) {
        _state = PracticeControllerState.expired;
      } else if (_phoneConnected &&
          _stage == 'ready' &&
          !this.remoteInput.hasFreshInput) {
        _state = PracticeControllerState.lost;
      } else if (_phoneConnected &&
          _stage == 'ready' &&
          this.remoteInput.readyToStart) {
        _state = PracticeControllerState.ready;
      }
      if (_state != previousState) notifyListeners();
    });
  }

  static ControllerConnection _defaultConnectionFactory({
    required Uri uri,
    required ControllerRole role,
    required void Function(ControllerMessage) onEvent,
    required Map<String, Object?> registrationData,
  }) => ControllerConnection(
    uri: uri,
    role: role,
    onEvent: onEvent,
    registrationData: registrationData,
  );

  final Uri relayUrl;
  final RemoteInputSource remoteInput;
  final DateTime Function() _now;
  late final ControllerConnection _connection;
  Timer? _watchdog;
  Timer? _expiryTimer;
  PairingPayload? _pairing;
  PracticeControllerState _state = PracticeControllerState.connectingRelay;
  String? _error;
  String? _stage;
  int? _generation;
  bool _phoneConnected = false;
  bool _everPhoneConnected = false;
  bool _ended = false;
  bool _disposed = false;

  PairingPayload? get pairing => _pairing;
  PracticeControllerState get state => _state;
  String? get error => _error;
  bool get isRelayConnected => _connection.isConnected;
  bool get isPhoneConnected => _phoneConnected;
  bool get canStart =>
      !_ended &&
      _phoneConnected &&
      _stage == 'ready' &&
      remoteInput.readyToStart;

  void _handleConnectionChange() {
    if (_ended) return;
    if (_connection.isConnected) {
      if (_pairing == null) _state = PracticeControllerState.connectingRelay;
    } else if (_connection.state == ControllerConnectionState.connecting) {
      _state = PracticeControllerState.connectingRelay;
    } else {
      remoteInput.setConnected(false);
      _phoneConnected = false;
      _generation = null;
      _state = _pairing != null
          ? PracticeControllerState.relayLost
          : PracticeControllerState.connectingRelay;
    }
    notifyListeners();
  }

  void _handleMessage(ControllerMessage message) {
    if (_ended) return;
    final data = message.data;
    switch (message.event) {
      case ControllerEvents.registered:
        if (data['role'] != 'game' ||
            data['sessionId'] is! String ||
            data['pairingToken'] is! String ||
            data['expiresAt'] is! int) {
          _error = 'Relay không trả về thông tin ghép nối hợp lệ.';
          _state = PracticeControllerState.error;
          break;
        }
        _connection.autoReconnect = false;
        final parsedUrl = _parseQrRelayUrl(relayUrl);
        if (parsedUrl == null) {
          _error =
              'Địa chỉ relay phải là IP trong mạng LAN, không phải localhost.';
          _state = PracticeControllerState.error;
          unawaited(end());
          break;
        }
        _pairing = PairingPayload(
          relayUrl: parsedUrl,
          sessionId: data['sessionId'] as String,
          pairingToken: data['pairingToken'] as String,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            data['expiresAt'] as int,
          ),
        );
        _state = PracticeControllerState.waitingForPhone;
        _expiryTimer?.cancel();
        _expiryTimer = Timer(
          _pairing!.expiresAt.difference(_now()).isNegative
              ? Duration.zero
              : _pairing!.expiresAt.difference(_now()),
          () {
            if (!_phoneConnected && !_ended) {
              _state = PracticeControllerState.expired;
              notifyListeners();
            }
          },
        );
        break;
      case ControllerEvents.status:
        if (data['phoneConnected'] is bool) {
          _phoneConnected = data['phoneConnected'] as bool;
          if (_phoneConnected) _everPhoneConnected = true;
          if (data['generation'] is int) {
            final nextGeneration = data['generation'] as int;
            if (!_phoneConnected || nextGeneration != _generation) {
              remoteInput.setConnected(
                _phoneConnected,
                generation: _phoneConnected ? nextGeneration : null,
              );
            }
            _generation = _phoneConnected ? nextGeneration : null;
          }
          final stage = data['controllerStage'];
          if (stage is String) _stage = stage;
          _state = !_phoneConnected
              ? (_everPhoneConnected
                    ? PracticeControllerState.lost
                    : PracticeControllerState.waitingForPhone)
              : _stateForStage(_stage);
        }
        break;
      case ControllerEvents.input:
        final seq = data['seq'];
        final generation = data['generation'];
        final steering = data['steering'];
        final throttle = data['throttle'];
        final brake = data['brake'];
        final reverse = data['reverse'] ?? 0;
        if (seq is int &&
            generation is int &&
            steering is num &&
            throttle is num &&
            brake is num &&
            reverse is num) {
          remoteInput.accept(
            sequence: seq,
            generation: generation,
            steering: steering.toDouble(),
            throttle: throttle.toDouble(),
            brake: brake.toDouble(),
            reverse: reverse.toDouble(),
          );
          if (_stage == 'ready') _state = _stateForStage(_stage);
        }
        break;
      case ControllerEvents.unavailable:
        if (data['generation'] == _generation) {
          remoteInput.markUnavailable();
          _stage = 'lost';
          _state = PracticeControllerState.lost;
        }
        break;
      case ControllerEvents.error:
        _error = switch (data['code']) {
          'pairing_expired' => 'Mã ghép nối đã hết hạn. Tạo mã mới để thử lại.',
          'session_ended' => 'Phiên Practice đã kết thúc.',
          'invalid_pairing' => 'Điện thoại không ghép được vào phiên này.',
          _ => 'Relay từ chối tạo phiên Practice.',
        };
        _state = data['code'] == 'pairing_expired'
            ? PracticeControllerState.expired
            : PracticeControllerState.error;
        break;
      case ControllerEvents.sessionEnded:
        _ended = true;
        _state = data['code'] == 'pairing_expired'
            ? PracticeControllerState.expired
            : PracticeControllerState.ended;
        remoteInput.setConnected(false);
        _phoneConnected = false;
        _generation = null;
        break;
    }
    notifyListeners();
  }

  PracticeControllerState _stateForStage(String? stage) => switch (stage) {
    'ready' =>
      remoteInput.readyToStart
          ? PracticeControllerState.ready
          : remoteInput.hasFreshInput
          ? PracticeControllerState.neutralRequired
          : PracticeControllerState.checking,
    'calibrating' => PracticeControllerState.calibrating,
    'lost' => PracticeControllerState.lost,
    _ => PracticeControllerState.checking,
  };

  void sendCollision() {
    final generation = _generation;
    if (!_ended && _phoneConnected && generation != null) {
      _connection.send(ControllerEvents.collision, {'generation': generation});
    }
  }

  Future<void> end() async {
    if (_ended) return;
    _ended = true;
    _state = PracticeControllerState.ended;
    _expiryTimer?.cancel();
    _watchdog?.cancel();
    remoteInput.setConnected(false);
    _phoneConnected = false;
    _generation = null;
    if (_connection.isConnected) {
      _connection.send(ControllerEvents.sessionEnd, const {});
    }
    await _connection.disconnect();
    if (!_disposed) notifyListeners();
  }

  static Uri? _parseQrRelayUrl(Uri uri) {
    return PairingPayload.parseRelayUrl(uri.toString());
  }

  @override
  void dispose() {
    _disposed = true;
    _expiryTimer?.cancel();
    _watchdog?.cancel();
    if (!_ended) {
      _ended = true;
      _state = PracticeControllerState.ended;
      remoteInput.setConnected(false);
      _phoneConnected = false;
      _generation = null;
      if (_connection.isConnected) {
        _connection.send(ControllerEvents.sessionEnd, const {});
      }
    }
    _connection.removeListener(_handleConnectionChange);
    _connection.dispose();
    super.dispose();
  }
}
