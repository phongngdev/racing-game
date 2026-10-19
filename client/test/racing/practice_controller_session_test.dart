import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/controller/controller_connection.dart';
import 'package:racing_client/controller/controller_protocol.dart';
import 'package:racing_client/racing/practice_controller_session.dart';

void main() {
  test('Practice session creates one v2 game connection and QR payload', () {
    final factory = _SessionConnectionFactory();
    final session = PracticeControllerSession(
      relayUrl: Uri.parse('ws://192.168.1.20:3000/controller'),
      connectionFactory: factory.create,
    );
    addTearDown(session.dispose);

    expect(factory.connection?.connectCalls, 1);
    expect(factory.registrationData, {
      'role': 'game',
      'version': 2,
      'action': 'create',
    });
    expect(session.pairing, isNull);

    factory.connection!.markConnected();
    factory.connection!.emit(ControllerEvents.registered, {
      'role': 'game',
      'sessionId': 'practice-01',
      'pairingToken': List.filled(48, 't').join(),
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch,
    });
    expect(session.pairing?.sessionId, 'practice-01');
    expect(session.state, PracticeControllerState.waitingForPhone);
  });

  test('connected status alone is not Practice controller readiness', () {
    final factory = _SessionConnectionFactory();
    final session = PracticeControllerSession(
      relayUrl: Uri.parse('ws://192.168.1.20:3000/controller'),
      connectionFactory: factory.create,
    );
    addTearDown(session.dispose);
    final connection = factory.connection!;
    connection.markConnected();
    connection.emit(ControllerEvents.registered, {
      'role': 'game',
      'sessionId': 'practice-01',
      'pairingToken': List.filled(48, 't').join(),
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch,
    });
    connection.emit(ControllerEvents.status, {
      'phoneConnected': true,
      'generation': 1,
      'controllerStage': 'checking',
    });

    expect(session.isPhoneConnected, isTrue);
    expect(session.canStart, isFalse);

    connection.emit(ControllerEvents.input, {
      'seq': 1,
      'generation': 1,
      'steering': 0,
      'throttle': 1,
      'reverse': 0,
      'brake': 0,
    });
    connection.emit(ControllerEvents.status, {
      'phoneConnected': true,
      'generation': 1,
      'controllerStage': 'ready',
    });
    expect(session.canStart, isFalse);
    expect(session.state, PracticeControllerState.neutralRequired);

    connection.emit(ControllerEvents.input, {
      'seq': 2,
      'generation': 1,
      'steering': 0,
      'throttle': 0,
      'reverse': 0,
      'brake': 0,
    });
    expect(session.canStart, isTrue);
    expect(session.state, PracticeControllerState.ready);
  });

  test('ends the pairing exactly once when setup exits', () async {
    final factory = _SessionConnectionFactory();
    final session = PracticeControllerSession(
      relayUrl: Uri.parse('ws://192.168.1.20:3000/controller'),
      connectionFactory: factory.create,
    );
    final connection = factory.connection!;
    connection.markConnected();
    connection.emit(ControllerEvents.registered, {
      'role': 'game',
      'sessionId': 'practice-01',
      'pairingToken': List.filled(48, 't').join(),
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch,
    });

    await session.end();
    await session.end();
    expect(connection.sentEvents, [ControllerEvents.sessionEnd]);
    expect(connection.disconnectCalls, 1);
    session.dispose();
  });
}

class _SessionConnectionFactory {
  _RecordingConnection? connection;
  Map<String, Object?>? registrationData;

  ControllerConnection create({
    required Uri uri,
    required ControllerRole role,
    required void Function(ControllerMessage) onEvent,
    required Map<String, Object?> registrationData,
  }) {
    this.registrationData = registrationData;
    return connection = _RecordingConnection(
      uri: uri,
      role: role,
      onEvent: onEvent,
    );
  }
}

class _RecordingConnection extends ControllerConnection {
  _RecordingConnection({
    required super.uri,
    required super.role,
    required super.onEvent,
  });

  int connectCalls = 0;
  int disconnectCalls = 0;
  final List<String> sentEvents = [];

  @override
  void connect() => connectCalls++;

  void markConnected() {
    state = ControllerConnectionState.connected;
    notifyListeners();
  }

  void emit(String event, Map<String, Object?> data) =>
      onEvent(ControllerMessage(event, data));

  @override
  void send(String event, Map<String, Object?> data) => sentEvents.add(event);

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    state = ControllerConnectionState.disconnected;
    notifyListeners();
  }
}
