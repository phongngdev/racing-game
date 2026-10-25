import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/lap/lap_race_rules.dart';

void main() {
  test('same-step ties are independent of player update order', () {
    final redFirst = resolveFixedStepFinishes(const [
      LapFinishCandidate(player: PlayerId.red, eventTime: 12.004),
      LapFinishCandidate(player: PlayerId.blue, eventTime: 12.0045),
    ]);
    final blueFirst = resolveFixedStepFinishes(const [
      LapFinishCandidate(player: PlayerId.blue, eventTime: 12.0045),
      LapFinishCandidate(player: PlayerId.red, eventTime: 12.004),
    ]);

    expect(redFirst?.isDraw, isTrue);
    expect(redFirst?.winner, isNull);
    expect(blueFirst?.isDraw, isTrue);
    expect(blueFirst?.winner, isNull);
  });

  test('finish outside tie tolerance selects the earliest crossing', () {
    final redFirst = resolveFixedStepFinishes(const [
      LapFinishCandidate(player: PlayerId.red, eventTime: 9.001),
      LapFinishCandidate(player: PlayerId.blue, eventTime: 9.003),
    ]);
    final blueFirst = resolveFixedStepFinishes(const [
      LapFinishCandidate(player: PlayerId.blue, eventTime: 9.003),
      LapFinishCandidate(player: PlayerId.red, eventTime: 9.001),
    ]);

    expect(redFirst?.winner, PlayerId.red);
    expect(blueFirst?.winner, PlayerId.red);
    expect(redFirst?.isDraw, isFalse);
  });
}
