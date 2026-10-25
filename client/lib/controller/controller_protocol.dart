import 'dart:convert';

class ControllerMessage {
  const ControllerMessage(this.event, this.data);

  final String event;
  final Map<String, Object?> data;

  static ControllerMessage? decode(Object? raw) {
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! Map<String, dynamic> ||
          decoded['event'] is! String ||
          decoded['data'] is! Map<String, dynamic>) {
        return null;
      }
      return ControllerMessage(
        decoded['event'] as String,
        Map<String, Object?>.from(decoded['data'] as Map<String, dynamic>),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  String encode() => jsonEncode({'event': event, 'data': data});
}

abstract final class ControllerEvents {
  static const register = 'register';
  static const registered = 'registered';
  static const input = 'input';
  static const collision = 'collision';
  static const status = 'status';
  static const unavailable = 'unavailable';
  static const ping = 'ping';
  static const pong = 'pong';
  static const error = 'error';
  static const controllerState = 'controller_state';
  static const sessionEnd = 'session_end';
  static const sessionEnded = 'session_ended';
  static const roomState = 'room_state';
  static const roomClosed = 'room_closed';
  static const slotConfig = 'slot_config';
  static const slotConfigured = 'slot_configured';
  static const slotReset = 'slot_reset';
  static const slotInvite = 'slot_invite';
  static const slotLeave = 'slot_leave';
  static const slotLeft = 'slot_left';
  static const roomClose = 'room_close';
}
