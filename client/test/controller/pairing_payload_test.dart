import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/controller/pairing_payload.dart';

void main() {
  test('round trips a LAN relay URL and temporary pairing credential', () {
    final payload = PairingPayload(
      relayUrl: Uri.parse('ws://192.168.1.20:3000/controller'),
      sessionId: 'session-01',
      pairingToken: List.filled(48, 'A').join(),
      expiresAt: DateTime.utc(2026, 10, 20, 12),
    );

    final decoded = PairingPayload.tryParse(payload.toQrValue());
    expect(decoded?.relayUrl, payload.relayUrl);
    expect(decoded?.sessionId, payload.sessionId);
    expect(decoded?.pairingToken, payload.pairingToken);
    expect(
      decoded?.expiresAt.millisecondsSinceEpoch,
      payload.expiresAt.millisecondsSinceEpoch,
    );
  });

  test('rejects malformed QR data and loopback relay addresses', () {
    expect(PairingPayload.tryParse('not-json'), isNull);
    for (final host in ['localhost', '127.0.0.1', '0.0.0.0']) {
      final raw = jsonEncode({
        'type': PairingPayload.qrType,
        'version': PairingPayload.qrVersion,
        'relayUrl': 'ws://$host:3000/controller',
        'sessionId': 'session-01',
        'pairingToken': List.filled(48, 'A').join(),
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      });
      expect(PairingPayload.tryParse(raw), isNull, reason: host);
    }
  });

  test('requires the controller relay path and credential format', () {
    for (final (url, token) in [
      ('ws://192.168.1.20/other', List.filled(48, 'A').join()),
      (
        'ws://192.168.1.20/controller?token=secret',
        List.filled(48, 'A').join(),
      ),
      ('ws://192.168.1.20/controller', 'short'),
    ]) {
      final raw = jsonEncode({
        'type': PairingPayload.qrType,
        'version': PairingPayload.qrVersion,
        'relayUrl': url,
        'sessionId': 'session-01',
        'pairingToken': token,
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      });
      expect(PairingPayload.tryParse(raw), isNull);
    }
  });
}
