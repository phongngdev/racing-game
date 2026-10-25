import '../input/car_input.dart';

class LapRaceConfig {
  const LapRaceConfig({
    this.lapCount = 3,
    this.countdownSeconds = 3,
    this.finishWaitSeconds = 60,
    this.tieToleranceSeconds = 0.001,
  }) : assert(lapCount > 0),
       assert(countdownSeconds > 0),
       assert(finishWaitSeconds > 0),
       assert(tieToleranceSeconds >= 0);

  final int lapCount;
  final double countdownSeconds;
  final double finishWaitSeconds;
  final double tieToleranceSeconds;
}

class LapFinishCandidate {
  const LapFinishCandidate({required this.player, required this.eventTime});

  final PlayerId player;
  final double eventTime;
}

class LapFinishDecision {
  const LapFinishDecision({
    required this.winner,
    required this.isDraw,
    required this.firstFinishTime,
  });

  final PlayerId? winner;
  final bool isDraw;
  final double firstFinishTime;
}

/// Resolves all finishes from one fixed step without depending on list order.
LapFinishDecision? resolveFixedStepFinishes(
  Iterable<LapFinishCandidate> candidates, {
  double tieToleranceSeconds = 0.001,
}) {
  final sorted = candidates.toList()
    ..sort((a, b) => a.eventTime.compareTo(b.eventTime));
  if (sorted.isEmpty) return null;
  final first = sorted.first;
  final isDraw =
      sorted.length > 1 &&
      (sorted[1].eventTime - first.eventTime).abs() <= tieToleranceSeconds;
  return LapFinishDecision(
    winner: isDraw ? null : first.player,
    isDraw: isDraw,
    firstFinishTime: first.eventTime,
  );
}
