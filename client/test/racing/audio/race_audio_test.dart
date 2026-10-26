import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/audio/race_audio.dart';

void main() {
  test('engine mix crossfades from idle to mid and high rpm layers', () {
    final idle = EngineAudioMix.forCar(
      speed: 0,
      throttle: 0,
      reverse: 0,
      steering: 0,
      brake: 0,
    );
    final cruising = EngineAudioMix.forCar(
      speed: 96,
      throttle: 0.55,
      reverse: 0,
      steering: 0.2,
      brake: 0,
    );
    final highRpm = EngineAudioMix.forCar(
      speed: 180,
      throttle: 1,
      reverse: 0,
      steering: 0,
      brake: 0,
    );

    expect(idle.idle, greaterThan(idle.mid));
    expect(cruising.mid, greaterThan(cruising.idle));
    expect(highRpm.high, greaterThan(cruising.high));
    expect(highRpm.pitch, greaterThan(cruising.pitch));
  });
}
