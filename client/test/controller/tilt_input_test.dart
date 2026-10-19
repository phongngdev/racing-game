import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/controller/tilt_input.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  test(
    'calibrates, filters tilt, clamps steering, and detects stale samples',
    () async {
      var now = 0;
      final stream = StreamController<AccelerometerEvent>();
      final readings = <double>[];
      var unavailable = false;
      final tilt = TiltInput(
        clockMicros: () => now,
        onSteering: readings.add,
        onUnavailable: () => unavailable = true,
      );
      await tilt.start(events: stream.stream);
      void send(double degrees) {
        final angle = degrees * math.pi / 180;
        now += const Duration(milliseconds: 20).inMicroseconds;
        stream.add(
          AccelerometerEvent(
            9.8 * math.cos(angle),
            0,
            9.8 * math.sin(angle),
            DateTime.fromMicrosecondsSinceEpoch(now),
          ),
        );
      }

      send(0);
      await Future<void>.delayed(Duration.zero);
      final calibration = tilt.calibrate();
      for (var i = 0; i < 25; i++) {
        send(0);
        await Future<void>.delayed(Duration.zero);
      }
      expect(await calibration, isTrue);
      expect(tilt.isCalibrated, isTrue);
      for (var i = 0; i < 30; i++) {
        send(20);
        await Future<void>.delayed(Duration.zero);
      }
      expect(tilt.steering, greaterThan(0));
      expect(tilt.steering, lessThan(1));
      for (var i = 0; i < 30; i++) {
        send(-60);
        await Future<void>.delayed(Duration.zero);
      }
      expect(tilt.steering, -1);

      final pendingCalibration = tilt.calibrate();
      now += const Duration(milliseconds: 201).inMicroseconds;
      expect(tilt.hasFreshSample, isFalse);
      expect(tilt.steering, 0);
      tilt.markUnavailable();
      expect(await pendingCalibration, isFalse);
      expect(tilt.isCalibrated, isFalse);
      stream.addError(StateError('sensor unavailable'));
      await Future<void>.delayed(Duration.zero);
      expect(unavailable, isTrue);
      expect(readings.last, 0);
      await tilt.stop();
      await stream.close();
    },
  );
}
