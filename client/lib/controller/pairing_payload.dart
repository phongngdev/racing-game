import 'dart:convert';

import 'controller_config.dart';

class PairingPayload {
  const PairingPayload({
    required this.relayUrl,
    required this.sessionId,
    required this.pairingToken,
    required this.expiresAt,
  });

  static const qrType = 'apex-rc-practice';
  static const qrVersion = 1;
  static const controllerPath = '/controller';

  final Uri relayUrl;
  final String sessionId;
  final String pairingToken;
  final DateTime expiresAt;

  bool get isExpired => !DateTime.now().isBefore(expiresAt);

  String toQrValue() => jsonEncode({
    'type': qrType,
    'version': qrVersion,
    'relayUrl': relayUrl.toString(),
    'sessionId': sessionId,
    'pairingToken': pairingToken,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
  });

  static PairingPayload? tryParse(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['type'] != qrType ||
          value['version'] != qrVersion ||
          value['relayUrl'] is! String ||
          value['sessionId'] is! String ||
          value['pairingToken'] is! String ||
          value['expiresAt'] is! int) {
        return null;
      }
      final relayUrl = parseRelayUrl(value['relayUrl'] as String);
      final sessionId = value['sessionId'] as String;
      final pairingToken = value['pairingToken'] as String;
      if (relayUrl == null ||
          sessionId.isEmpty ||
          pairingToken.length < 32 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(pairingToken)) {
        return null;
      }
      return PairingPayload(
        relayUrl: relayUrl,
        sessionId: sessionId,
        pairingToken: pairingToken,
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

  static Uri? parseRelayUrl(String value) {
    final uri = ControllerConfig.parse(value);
    if (uri == null ||
        uri.path != controllerPath ||
        uri.hasQuery ||
        _isLoopbackOrWildcard(uri.host)) {
      return null;
    }
    return uri;
  }

  static bool _isLoopbackOrWildcard(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '::1' ||
        normalized == '0.0.0.0' ||
        normalized == '::' ||
        normalized == '127.0.0.1' ||
        normalized.startsWith('127.');
  }
}
