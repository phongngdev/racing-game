import 'input/car_input.dart';

class RaceRules {
  const RaceRules({
    this.countdownSeconds = 3,
    this.finishWaitSeconds = 60,
    this.tieToleranceSeconds = 0.001,
  }) : assert(countdownSeconds > 0),
       assert(finishWaitSeconds > 0),
       assert(tieToleranceSeconds >= 0);

  final double countdownSeconds;
  final double finishWaitSeconds;
  final double tieToleranceSeconds;
}

class RaceFinishCandidate {
  const RaceFinishCandidate({required this.player, required this.eventTime});

  final PlayerId player;
  final double eventTime;
}

class RaceFinishDecision {
  const RaceFinishDecision({
    required this.winner,
    required this.isDraw,
    required this.firstFinishTime,
  });

  final PlayerId? winner;
  final bool isDraw;
  final double firstFinishTime;
}

/// Resolves all finishes from one fixed step without depending on list order.
RaceFinishDecision? resolveFixedStepFinishes(
  Iterable<RaceFinishCandidate> candidates, {
  double tieToleranceSeconds = 0.001,
}) {
  final sorted = candidates.toList()
    ..sort((a, b) => a.eventTime.compareTo(b.eventTime));
  if (sorted.isEmpty) return null;
  final first = sorted.first;
  final isDraw =
      sorted.length > 1 &&
      (sorted[1].eventTime - first.eventTime).abs() <= tieToleranceSeconds;
  return RaceFinishDecision(
    winner: isDraw ? null : first.player,
    isDraw: isDraw,
    firstFinishTime: first.eventTime,
  );
}
