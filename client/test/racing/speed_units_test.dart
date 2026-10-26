import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/speed_units.dart';

void main() {
  test('converts signed simulation speed to integer km/h', () {
    expect(speedKmh(0), 0);
    expect(speedKmh(100), 36);
    expect(speedKmh(200), 72);
    expect(speedKmh(260), 94);
    expect(speedKmh(-100), 36);
  });
}
