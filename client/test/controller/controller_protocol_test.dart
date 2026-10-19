import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/controller/controller_config.dart';
import 'package:racing_client/controller/controller_protocol.dart';

void main() {
  test('validates LAN WebSocket URLs', () {
    expect(
      ControllerConfig.parse('ws://192.168.1.20:3000/controller')?.host,
      '192.168.1.20',
    );
    expect(
      ControllerConfig.parse('wss://race.example/controller')?.scheme,
      'wss',
    );
    expect(ControllerConfig.parse('http://192.168.1.20:3000'), isNull);
    expect(ControllerConfig.parse('ws://user@192.168.1.20'), isNull);
  });

  test('encodes and decodes event/data messages', () {
    final encoded = const ControllerMessage('input', {
      'seq': 3,
      'steering': -0.5,
    }).encode();
    final decoded = ControllerMessage.decode(encoded);
    expect(decoded?.event, 'input');
    expect(decoded?.data['seq'], 3);
    expect(decoded?.data['steering'], -0.5);
    expect(ControllerMessage.decode('{broken'), isNull);
    expect(ControllerMessage.decode('[]'), isNull);
  });
}
