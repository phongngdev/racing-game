import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/controller/controller_connection.dart';
import 'package:racing_client/controller/controller_protocol.dart';
import 'package:racing_client/racing/multiplayer_room_session.dart';

void main() {
  test(
    'creates protocol v3 room and becomes ready only after neutral phone input',
    () {
      final factory = _RoomConnectionFactory();
      final session = MultiplayerRoomSession(
        relayUrl: Uri.parse('ws://192.168.1.20:3000/controller'),
        connectionFactory: factory.create,
      );
      addTearDown(session.dispose);
      expect(factory.registrationData, {
        'role': 'game',
        'version': 3,
        'action': 'create',
      });

      final connection = factory.connection!;
      connection.markConnected();
      connection.emit(ControllerEvents.registered, {
        'role': 'game',
        'version': 3,
        'roomId': 'room-01',
        'invites': [
          {
            'slotId': 'p1',
            'pairingToken': List.filled(32, 'A').join(),
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
          },
        ],
      });
      connection.emit(ControllerEvents.roomState, {
        'roomId': 'room-01',
        'slots': [
          {
            'slotId': 'p1',
            'player': 'red',
            'source': 'phone',
            'connected': false,
            'stage': 'lost',
          },
          {
            'slotId': 'p2',
            'player': 'blue',
            'source': 'keyboard',
            'connected': false,
            'stage': 'lost',
          },
        ],
      });
      expect(session.inviteFor('p1')?.roomId, 'room-01');
      expect(session.inviteFor('p2'), isNull);
      expect(session.canStart, isFalse);

      connection.emit(ControllerEvents.roomState, {
        'roomId': 'room-01',
        'slots': [
          {
            'slotId': 'p1',
            'player': 'red',
            'source': 'phone',
            'connected': true,
            'generation': 2,
            'stage': 'ready',
          },
          {
            'slotId': 'p2',
            'player': 'blue',
            'source': 'keyboard',
            'connected': false,
            'stage': 'lost',
          },
        ],
      });
      connection.emit(ControllerEvents.input, {
        'roomId': 'room-01',
        'slotId': 'p1',
        'generation': 2,
        'seq': 1,
        'steering': 0,
        'throttle': 0,
        'reverse': 0,
        'brake': 0,
      });
      expect(session.canStart, isTrue);
    },
  );

  test('refuses slot changes while running and applies them after server acknowledgement', () async {
    final factory = _RoomConnectionFactory();
    final session = MultiplayerRoomSession(
      relayUrl: Uri.parse('ws://192.168.1.20:3000/controller'),
      connectionFactory: factory.create,
    );
    final connection = factory.connection!;
    connection.markConnected();
    connection.emit(ControllerEvents.registered, {
      'role': 'game',
      'version': 3,
      'roomId': 'room-02',
      'invites': const [],
    });
    connection.emit(ControllerEvents.roomState, {
      'roomId': 'room-02',
      'slots': [
        {
          'slotId': 'p1',
          'player': 'red',
          'source': 'phone',
          'connected': false,
        },
        {
          'slotId': 'p2',
          'player': 'blue',
          'source': 'keyboard',
          'connected': false,
        },
      ],
    });

    session.setGameRunning(true);
    await expectLater(
      session.configureSlot('p1', 'keyboard'),
      throwsStateError,
    );
    session.setGameRunning(false);
    final pending = session.configureSlot('p1', 'keyboard');
    final sent = connection.sentData.last;
    expect(sent['event'], ControllerEvents.slotConfig);
    final configData = sent['data'] as Map<String, Object?>;
    connection.emit(ControllerEvents.slotConfigured, {
      'requestId': configData['requestId'],
      'slotId': 'p1',
      'source': 'keyboard',
    });
    expect(await pending, isTrue);
    expect(session.slot('p1')?.source, 'keyboard');
    await session.close();
    session.dispose();
  });
}

class _RoomConnectionFactory {
  _RecordingRoomConnection? connection;
  Map<String, Object?>? registrationData;

  ControllerConnection create({
    required Uri uri,
    required ControllerRole role,
    required void Function(ControllerMessage) onEvent,
    Map<String, Object?>? registrationData,
  }) {
    this.registrationData = registrationData;
    return connection = _RecordingRoomConnection(
      uri: uri,
      role: role,
      onEvent: onEvent,
      registrationData: registrationData,
    );
  }
}

class _RecordingRoomConnection extends ControllerConnection {
  _RecordingRoomConnection({
    required super.uri,
    required super.role,
    required super.onEvent,
    super.registrationData,
  });

  final List<Map<String, Object?>> sentData = [];

  @override
  void connect() {}

  void markConnected() {
    state = ControllerConnectionState.connected;
    notifyListeners();
  }

  void emit(String event, Map<String, Object?> data) =>
      onEvent(ControllerMessage(event, data));

  @override
  void send(String event, Map<String, Object?> data) =>
      sentData.add({'event': event, 'data': data});

  @override
  Future<void> disconnect() async {
    state = ControllerConnectionState.disconnected;
    notifyListeners();
  }
}
