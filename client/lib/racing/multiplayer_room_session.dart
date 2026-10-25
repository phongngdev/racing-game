import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controller/controller_connection.dart';
import '../controller/controller_protocol.dart';
import '../controller/room_pairing_payload.dart';
import 'input/car_input.dart';
import 'input/remote_input_source.dart';

enum MultiplayerRoomState { connecting, waiting, ready, disconnected, closed }

class MultiplayerSlotStatus {
  const MultiplayerSlotStatus({
    required this.id,
    required this.player,
    required this.source,
    required this.connected,
    required this.generation,
    required this.stage,
    required this.reservedUntil,
    required this.inviteExpiresAt,
  });

  final String id;
  final PlayerId player;
  final String source;
  final bool connected;
  final int? generation;
  final String stage;
  final DateTime? reservedUntil;
  final DateTime? inviteExpiresAt;

  bool get reserved => reservedUntil != null;
}

class MultiplayerRoomSession extends ChangeNotifier {
  MultiplayerRoomSession({
    required this.relayUrl,
    ControllerConnection Function({
      required Uri uri,
      required ControllerRole role,
      required void Function(ControllerMessage) onEvent,
      Map<String, Object?>? registrationData,
    })?
    connectionFactory,
    RemoteInputSource? redInput,
    RemoteInputSource? blueInput,
  }) : redInput =
           redInput ??
           RemoteInputSource(
             player: PlayerId.red,
             requireNeutralAfterTimeout: true,
           ),
       blueInput =
           blueInput ??
           RemoteInputSource(
             player: PlayerId.blue,
             requireNeutralAfterTimeout: true,
           ) {
    final factory = connectionFactory ?? _defaultConnectionFactory;
    _connection = factory(
      uri: relayUrl,
      role: ControllerRole.game,
      registrationData: const {
        'role': 'game',
        'version': 3,
        'action': 'create',
      },
      onEvent: _handleMessage,
    )..addListener(_handleConnectionChange);
    _connection.connect();
  }

  static ControllerConnection _defaultConnectionFactory({
    required Uri uri,
    required ControllerRole role,
    required void Function(ControllerMessage) onEvent,
    Map<String, Object?>? registrationData,
  }) => ControllerConnection(
    uri: uri,
    role: role,
    onEvent: onEvent,
    registrationData: registrationData,
  );

  final Uri relayUrl;
  final RemoteInputSource redInput;
  final RemoteInputSource blueInput;
  late final ControllerConnection _connection;
  final Map<String, MultiplayerSlotStatus> _slots = {};
  final Map<String, RoomPairingPayload> _invites = {};
  final Map<String, Completer<bool>> _pendingConfig = {};
  final Set<String> _configuringSlots = {};
  MultiplayerRoomState _state = MultiplayerRoomState.connecting;
  String? _roomId;
  String? _error;
  bool _gameRunning = false;
  bool _ended = false;
  bool _disposed = false;
  int _requestSequence = 0;

  MultiplayerRoomState get state => _state;
  String? get roomId => _roomId;
  String? get error => _error;
  bool get isConnected => _connection.isConnected && !_ended;
  bool get isGameRunning => _gameRunning;
  Map<String, MultiplayerSlotStatus> get slots => Map.unmodifiable(_slots);
  MultiplayerSlotStatus? slot(String id) => _slots[id];
  bool isSlotConfiguring(String id) => _configuringSlots.contains(id);
  RemoteInputSource remoteFor(PlayerId player) =>
      player == PlayerId.red ? redInput : blueInput;

  RoomPairingPayload? inviteFor(String slotId) {
    final invite = _invites[slotId];
    return invite != null && !invite.isExpired ? invite : null;
  }

  bool get canStart {
    if (!isConnected ||
        _roomId == null ||
        _state == MultiplayerRoomState.closed) {
      return false;
    }
    for (final slot in _slots.values) {
      if (slot.source == 'keyboard') continue;
      if (slot.source != 'phone' ||
          !slot.connected ||
          slot.stage != 'ready' ||
          !remoteFor(slot.player).readyToStart) {
        return false;
      }
    }
    return _slots.length == 2;
  }

  void setGameRunning(bool value) => _gameRunning = value;

  Future<bool> configureSlot(String slotId, String source) async {
    if (_gameRunning) {
      throw StateError('Pause the game before changing a slot.');
    }
    if (!const {'p1', 'p2'}.contains(slotId) ||
        !const {'phone', 'keyboard'}.contains(source) ||
        !isConnected ||
        _roomId == null ||
        _configuringSlots.contains(slotId)) {
      return false;
    }
    final requestId = 'slot-${++_requestSequence}';
    final completer = Completer<bool>();
    _pendingConfig[requestId] = completer;
    _configuringSlots.add(slotId);
    notifyListeners();
    _connection.send(ControllerEvents.slotConfig, {
      'roomId': _roomId,
      'slotId': slotId,
      'source': source,
      'requestId': requestId,
    });
    try {
      final configured = await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => false,
      );
      if (!configured) return false;
      _error = null;
      final slot = _slots[slotId];
      if (slot != null) {
        _slots[slotId] = MultiplayerSlotStatus(
          id: slot.id,
          player: slot.player,
          source: source,
          connected: false,
          generation: slot.generation,
          stage: 'lost',
          reservedUntil: null,
          inviteExpiresAt: null,
        );
        remoteFor(slot.player).setConnected(false);
      }
      return true;
    } finally {
      _pendingConfig.remove(requestId);
      _configuringSlots.remove(slotId);
      if (!_disposed) notifyListeners();
    }
  }

  bool resetSlot(String slotId) {
    if (_gameRunning || !isConnected || _roomId == null) return false;
    if (_slots[slotId]?.source != 'phone') return false;
    remoteFor(_playerForSlot(slotId)).setConnected(false);
    _connection.send(ControllerEvents.slotReset, {
      'roomId': _roomId,
      'slotId': slotId,
    });
    return true;
  }

  void sendCollision(String slotId) {
    final slot = _slots[slotId];
    if (slot == null ||
        slot.source != 'phone' ||
        !slot.connected ||
        slot.generation == null ||
        !isConnected) {
      return;
    }
    _connection.send(ControllerEvents.collision, {
      'roomId': _roomId,
      'slotId': slotId,
      'generation': slot.generation,
    });
  }

  void clearInputs() {
    redInput.lockUntilNeutral();
    blueInput.lockUntilNeutral();
  }

  Future<void> close() async {
    if (_ended) return;
    _ended = true;
    _state = MultiplayerRoomState.closed;
    clearInputs();
    if (_connection.isConnected && _roomId != null) {
      _connection.send(ControllerEvents.roomClose, {'roomId': _roomId});
    }
    for (final pending in _pendingConfig.values) {
      if (!pending.isCompleted) pending.complete(false);
    }
    await _connection.disconnect();
    if (!_disposed) notifyListeners();
  }

  void _handleConnectionChange() {
    if (_disposed || _ended) return;
    if (!_connection.isConnected &&
        _connection.state == ControllerConnectionState.disconnected &&
        _roomId != null) {
      _state = MultiplayerRoomState.closed;
      _error = 'Relay đã ngắt · phòng đã kết thúc. Hãy tạo phòng mới.';
      redInput.setConnected(false);
      blueInput.setConnected(false);
      _ended = true;
    } else if (_connection.state == ControllerConnectionState.connecting) {
      _state = MultiplayerRoomState.connecting;
    }
    notifyListeners();
  }

  void _handleMessage(ControllerMessage message) {
    if (_disposed || _ended) return;
    final data = message.data;
    switch (message.event) {
      case ControllerEvents.registered:
        if (data['role'] != 'game' ||
            data['version'] != 3 ||
            data['roomId'] is! String) {
          _error = 'Relay không trả về thông tin phòng hợp lệ.';
          _state = MultiplayerRoomState.closed;
          _ended = true;
          _connection.autoReconnect = false;
          unawaited(_connection.disconnect());
          break;
        }
        _roomId = data['roomId'] as String;
        _connection.autoReconnect = false;
        final invites = data['invites'];
        if (invites is List) {
          for (final value in invites) {
            if (value is Map<String, Object?>) _readInvite(value);
          }
        }
        _state = MultiplayerRoomState.waiting;
        break;
      case ControllerEvents.roomState:
        if (data['roomId'] != _roomId || data['slots'] is! List) break;
        for (final value in data['slots'] as List) {
          if (value is Map<String, Object?>) _readSlot(value);
        }
        _state = _slots.values.any((slot) => slot.connected)
            ? MultiplayerRoomState.ready
            : MultiplayerRoomState.waiting;
        break;
      case ControllerEvents.slotInvite:
        if (data['roomId'] == _roomId) _readInvite(data);
        break;
      case ControllerEvents.slotConfigured:
        final requestId = data['requestId'];
        if (requestId is String) {
          final pending = _pendingConfig[requestId];
          if (pending != null && !pending.isCompleted) pending.complete(true);
        }
        break;
      case ControllerEvents.input:
        _readInput(data);
        return;
      case ControllerEvents.unavailable:
        final slotId = data['slotId'];
        final slot = slotId is String ? _slots[slotId] : null;
        if (data['roomId'] == _roomId &&
            slot != null &&
            data['generation'] == slot.generation) {
          remoteFor(slot.player).markUnavailable();
          _state = MultiplayerRoomState.waiting;
        }
        break;
      case ControllerEvents.roomClosed:
        _ended = true;
        _state = MultiplayerRoomState.closed;
        _error = 'Phòng đã đóng. Hãy tạo phòng mới.';
        redInput.setConnected(false);
        blueInput.setConnected(false);
        for (final pending in _pendingConfig.values) {
          if (!pending.isCompleted) pending.complete(false);
        }
        _connection.autoReconnect = false;
        break;
      case ControllerEvents.error:
        _error = _errorFor(data['code']);
        break;
    }
    if (!_disposed) notifyListeners();
  }

  void _readSlot(Map<String, Object?> data) {
    final id = data['slotId'];
    final playerName = data['player'];
    final source = data['source'];
    if (!const {'p1', 'p2'}.contains(id) ||
        !const {'red', 'blue'}.contains(playerName) ||
        !const {'phone', 'keyboard'}.contains(source)) {
      return;
    }
    final player = playerName == 'red' ? PlayerId.red : PlayerId.blue;
    final generation = data['generation'] is int
        ? data['generation'] as int
        : null;
    final connected = data['connected'] == true;
    final old = _slots[id as String];
    final slot = MultiplayerSlotStatus(
      id: id,
      player: player,
      source: source as String,
      connected: connected,
      generation: generation,
      stage: data['stage'] is String ? data['stage'] as String : 'lost',
      reservedUntil: _date(data['reservedUntil']),
      inviteExpiresAt: _date(data['inviteExpiresAt']),
    );
    _slots[slot.id] = slot;
    if (connected ||
        slot.reserved ||
        slot.source != 'phone' ||
        slot.inviteExpiresAt == null) {
      _invites.remove(slot.id);
    }
    final remote = remoteFor(player);
    if (source != 'phone' || !connected || generation == null) {
      remote.setConnected(false);
    } else if (old?.generation != generation || !remote.connected) {
      remote.setConnected(true, generation: generation);
    }
  }

  void _readInvite(Map<String, Object?> data) {
    final slotId = data['slotId'];
    final token = data['pairingToken'];
    final expiresAt = _date(data['expiresAt']);
    final roomId = data['roomId'] ?? _roomId;
    if (!const {'p1', 'p2'}.contains(slotId) ||
        token is! String ||
        expiresAt == null ||
        roomId is! String ||
        _roomId == null) {
      return;
    }
    _invites[slotId as String] = RoomPairingPayload(
      relayUrl: _qrRelayUrl(relayUrl),
      roomId: roomId,
      slotId: slotId,
      pairingToken: token,
      expiresAt: expiresAt,
    );
  }

  void _readInput(Map<String, Object?> data) {
    final slotId = data['slotId'];
    final slot = slotId is String ? _slots[slotId] : null;
    final seq = data['seq'];
    final generation = data['generation'];
    final steering = data['steering'];
    final throttle = data['throttle'];
    final reverse = data['reverse'] ?? 0;
    final brake = data['brake'];
    if (data['roomId'] != _roomId ||
        slot == null ||
        !slot.connected ||
        slot.source != 'phone' ||
        generation != slot.generation ||
        seq is! int ||
        steering is! num ||
        throttle is! num ||
        reverse is! num ||
        brake is! num) {
      return;
    }
    remoteFor(slot.player).accept(
      sequence: seq,
      generation: generation as int,
      steering: steering.toDouble(),
      throttle: throttle.toDouble(),
      reverse: reverse.toDouble(),
      brake: brake.toDouble(),
    );
  }

  PlayerId _playerForSlot(String slotId) =>
      slotId == 'p1' ? PlayerId.red : PlayerId.blue;

  DateTime? _date(Object? value) =>
      value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

  String _errorFor(Object? code) => switch (code) {
    'slot_in_use' => 'Slot đang được một controller khác sử dụng.',
    'slot_reserved' => 'Slot đang được giữ cho phone vừa mất kết nối.',
    'room_closed' => 'Phòng đã đóng hoặc relay đã khởi động lại.',
    _ => 'Relay từ chối thao tác phòng ($code).',
  };

  Uri _qrRelayUrl(Uri uri) => Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: '/controller',
  );

  @override
  void dispose() {
    _disposed = true;
    if (!_ended) {
      _ended = true;
      if (_connection.isConnected && _roomId != null) {
        _connection.send(ControllerEvents.roomClose, {'roomId': _roomId});
      }
      redInput.setConnected(false);
      blueInput.setConnected(false);
    }
    for (final pending in _pendingConfig.values) {
      if (!pending.isCompleted) pending.complete(false);
    }
    _connection.removeListener(_handleConnectionChange);
    _connection.dispose();
    super.dispose();
  }
}
