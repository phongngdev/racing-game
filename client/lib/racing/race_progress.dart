import 'input/car_input.dart';
import 'tracks/track_geometry.dart';

enum RacePlayerStatus { racing, finished, dnf }

abstract interface class RacePlayerProgress {
  PlayerId get player;
  RacePlayerStatus get status;
  double? get finishTime;
  String? get nextGateId;
}

class RaceProgressEvent {
  const RaceProgressEvent({
    required this.gateId,
    required this.eventTime,
    this.completedLap,
    this.finished = false,
    this.invalidatedProgress = false,
  });
  final String gateId;
  final double eventTime;
  final int? completedLap;
  final bool finished;
  final bool invalidatedProgress;
}

abstract interface class RacePlayerTracker<P extends RacePlayerProgress> {
  P progressAt(double raceTime);
  void reset({double raceStartTime = 0});
  void markDnf({bool revokeFinish = false});
  RaceProgressEvent? advanceSegment({
    required TrackPoint from,
    required TrackPoint to,
    required double stepStartTime,
    required double stepSeconds,
  });
}
