import 'dart:convert';

import 'pairing_payload.dart';

class RoomPairingPayload {
  const RoomPairingPayload({
    required this.relayUrl,
    required this.roomId,
    required this.slotId,
    required this.pairingToken,
    required this.expiresAt,
  });

  static const qrType = 'apex-rc-room';
  static const qrVersion = 1;

  final Uri relayUrl;
  final String roomId;
  final String slotId;
  final String pairingToken;
  final DateTime expiresAt;

  bool get isExpired => !DateTime.now().isBefore(expiresAt);

  String toQrValue() => jsonEncode({
    'type': qrType,
    'version': qrVersion,
    'relayUrl': relayUrl.toString(),
    'roomId': roomId,
    'slotId': slotId,
    'pairingToken': pairingToken,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
  });

  static RoomPairingPayload? tryParse(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['type'] != qrType ||
          value['version'] != qrVersion ||
          value['relayUrl'] is! String ||
          value['roomId'] is! String ||
          value['slotId'] is! String ||
          value['pairingToken'] is! String ||
          value['expiresAt'] is! int) {
        return null;
      }
      final relayUrl = PairingPayload.parseRelayUrl(
        value['relayUrl'] as String,
      );
      final roomId = value['roomId'] as String;
      final slotId = value['slotId'] as String;
      final token = value['pairingToken'] as String;
      if (relayUrl == null ||
          roomId.isEmpty ||
          !const {'p1', 'p2'}.contains(slotId) ||
          token.length < 32 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token)) {
        return null;
      }
      return RoomPairingPayload(
        relayUrl: relayUrl,
        roomId: roomId,
        slotId: slotId,
        pairingToken: token,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          value['expiresAt'] as int,
        ),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on RangeError {
      return null;
    }
  }
}

sealed class ScannedControllerPayload {
  const ScannedControllerPayload();

  Uri get relayUrl;

  static ScannedControllerPayload? tryParse(String raw) {
    final practice = PairingPayload.tryParse(raw);
    if (practice != null) return PracticeControllerPayload(practice);
    final room = RoomPairingPayload.tryParse(raw);
    if (room != null) return RoomControllerPayload(room);
    return null;
  }
}

final class PracticeControllerPayload extends ScannedControllerPayload {
  const PracticeControllerPayload(this.payload);

  final PairingPayload payload;

  @override
  Uri get relayUrl => payload.relayUrl;
}

final class RoomControllerPayload extends ScannedControllerPayload {
  const RoomControllerPayload(this.payload);

  final RoomPairingPayload payload;

  @override
  Uri get relayUrl => payload.relayUrl;
}
