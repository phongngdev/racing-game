import 'package:racing_client/controller/controller_connection.dart';
import 'package:racing_client/controller/controller_protocol.dart';
import 'package:racing_client/racing/multiplayer_room_session.dart';

class RoomFixture {
  RoomFixture() {
    session = MultiplayerRoomSession(
      relayUrl: Uri.parse('ws://192.168.1.20:3000/controller'),
      connectionFactory:
          ({required uri, required role, required onEvent, registrationData}) {
            return connection = RecordingRoomConnection(
              uri: uri,
              role: role,
              onEvent: onEvent,
              registrationData: registrationData,
            );
          },
    );
    connection.state = ControllerConnectionState.connected;
    connection.notifyListeners();
    connection.emit(ControllerEvents.registered, {
      'role': 'game',
      'version': 3,
      'roomId': 'room-test-01',
      'invites': <Object>[],
    });
    connection.emit(ControllerEvents.roomState, {
      'roomId': 'room-test-01',
      'slots': [
        {
          'slotId': 'p1',
          'player': 'red',
          'source': 'keyboard',
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
  }
  late final MultiplayerRoomSession session;
  late final RecordingRoomConnection connection;
}

class RecordingRoomConnection extends ControllerConnection {
  RecordingRoomConnection({
    required super.uri,
    required super.role,
    required super.onEvent,
    super.registrationData,
  });
  final List<String> sentEvents = [];
  @override
  void connect() {}
  void emit(String event, Map<String, Object?> data) =>
      onEvent(ControllerMessage(event, data));
  @override
  void send(String event, Map<String, Object?> data) => sentEvents.add(event);
  @override
  Future<void> disconnect() async {
    state = ControllerConnectionState.disconnected;
    notifyListeners();
  }
}
