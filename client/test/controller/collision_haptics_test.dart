import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/controller/collision_haptics.dart';

void main() {
  test('vibrates only for the foreground current phone session', () async {
    var pulses = 0;
    var capturedDuration = 0;
    int? capturedAmplitude;
    final haptics = CollisionHaptics(
      hasVibrator: () async => true,
      hasAmplitudeControl: () async => true,
      vibrate: ({required int duration, int? amplitude}) async {
        pulses++;
        capturedDuration = duration;
        capturedAmplitude = amplitude;
      },
      cancel: () async {},
      log: (_) {},
    );

    expect(
      await haptics.playForSession(
        foreground: true,
        currentGeneration: 8,
        eventGeneration: 7,
      ),
      VibrationResult.ignored,
    );
    expect(
      await haptics.playForSession(
        foreground: false,
        currentGeneration: 8,
        eventGeneration: 8,
      ),
      VibrationResult.ignored,
    );
    expect(pulses, 0);

    expect(
      await haptics.playForSession(
        foreground: true,
        currentGeneration: 8,
        eventGeneration: 8,
      ),
      VibrationResult.played,
    );
    expect(pulses, 1);
    expect(capturedDuration, 80);
    expect(capturedAmplitude, 180);
  });

  test(
    'manual test uses default amplitude when the motor has no control',
    () async {
      int? capturedAmplitude;
      final haptics = CollisionHaptics(
        hasVibrator: () async => true,
        hasAmplitudeControl: () async => false,
        vibrate: ({required int duration, int? amplitude}) async {
          capturedAmplitude = amplitude;
        },
        cancel: () async {},
        log: (_) {},
      );

      expect(await haptics.test(foreground: true), VibrationResult.played);
      expect(capturedAmplitude, isNull);
    },
  );

  test('reports unsupported hardware without calling the motor', () async {
    var pulses = 0;
    final haptics = CollisionHaptics(
      hasVibrator: () async => false,
      hasAmplitudeControl: () async => false,
      vibrate: ({required int duration, int? amplitude}) async {
        pulses++;
      },
      cancel: () async {},
      log: (_) {},
    );

    expect(await haptics.test(foreground: true), VibrationResult.unsupported);
    expect(pulses, 0);
  });

  test(
    'cancellation suppresses a vibration while capability checks are pending',
    () async {
      var pulses = 0;
      var completeAvailability = false;
      final availability = Future<bool>.delayed(
        const Duration(milliseconds: 1),
        () => completeAvailability,
      );
      final haptics = CollisionHaptics(
        hasVibrator: () => availability,
        hasAmplitudeControl: () async => true,
        vibrate: ({required int duration, int? amplitude}) async {
          pulses++;
        },
        cancel: () async {},
        log: (_) {},
      );

      final pending = haptics.test(foreground: true);
      await haptics.cancel();
      completeAvailability = true;
      expect(await pending, VibrationResult.ignored);
      expect(pulses, 0);
    },
  );

  test(
    'reports platform failures without throwing into input handling',
    () async {
      final haptics = CollisionHaptics(
        hasVibrator: () async => true,
        hasAmplitudeControl: () async => true,
        vibrate: ({required int duration, int? amplitude}) async {
          throw StateError('haptic unavailable');
        },
        cancel: () async {},
        log: (_) {},
      );

      expect(await haptics.test(foreground: true), VibrationResult.failed);
    },
  );
}
