import '../race_rules.dart';
export '../race_rules.dart' show resolveFixedStepFinishes;

typedef LapFinishCandidate = RaceFinishCandidate;
typedef LapFinishDecision = RaceFinishDecision;

class LapRaceConfig extends RaceRules {
  const LapRaceConfig({
    this.lapCount = 3,
    super.countdownSeconds = 3,
    super.finishWaitSeconds = 60,
    super.tieToleranceSeconds = 0.001,
  }) : assert(lapCount > 0);
  final int lapCount;
}
