import '../input/car_input.dart';
import 'lap_race_track.dart';
import '../race_progress.dart';
export '../race_progress.dart' show RacePlayerStatus;

typedef LapPlayerStatus = RacePlayerStatus;
typedef LapProgressEvent = RaceProgressEvent;

class LapPlayerProgress implements RacePlayerProgress {
  LapPlayerProgress({
    required this.player,
    required this.lapCount,
    required this.completedLaps,
    required this.nextGateId,
    required this.currentLapElapsed,
    required List<double> lapTimes,
    required this.finishTime,
    required this.status,
  }) : lapTimes = List.unmodifiable(lapTimes);

  @override
  final PlayerId player;
  final int lapCount;
  final int completedLaps;
  @override
  final String? nextGateId;
  final double currentLapElapsed;
  final List<double> lapTimes;
  @override
  final double? finishTime;
  @override
  final LapPlayerStatus status;

  int get lapNumber => completedLaps >= lapCount ? lapCount : completedLaps + 1;
}

class LapPlayerTracker implements RacePlayerTracker<LapPlayerProgress> {
  LapPlayerTracker({
    required this.player,
    this.track = LapRaceTrack.standard,
    this.lapCount = 3,
  }) : assert(lapCount > 0) {
    reset();
  }

  static const _armingDistance = 0.01;

  final PlayerId player;
  final LapRaceTrack track;
  final int lapCount;
  final Set<int> _acceptedCheckpointIndexes = {};
  final List<double> _lapTimes = [];
  int _nextGateIndex = 0;
  double _lapStartedAt = 0;
  double? _finishTime;
  LapPlayerStatus _status = LapPlayerStatus.racing;
  bool _expectedGateArmed = false;

  @override
  LapPlayerProgress progressAt(double raceTime) => LapPlayerProgress(
    player: player,
    lapCount: lapCount,
    completedLaps: _lapTimes.length,
    nextGateId: _status == LapPlayerStatus.racing
        ? _gateAt(_nextGateIndex).id
        : null,
    currentLapElapsed: _status == LapPlayerStatus.racing
        ? (raceTime - _lapStartedAt).clamp(0.0, double.infinity)
        : 0,
    lapTimes: _lapTimes,
    finishTime: _finishTime,
    status: _status,
  );

  @override
  void reset({double raceStartTime = 0}) {
    _acceptedCheckpointIndexes.clear();
    _lapTimes.clear();
    _nextGateIndex = 0;
    _lapStartedAt = raceStartTime;
    _finishTime = null;
    _status = LapPlayerStatus.racing;
    _expectedGateArmed = false;
  }

  @override
  void markDnf({bool revokeFinish = false}) {
    if (_status == LapPlayerStatus.finished && !revokeFinish) return;
    if (revokeFinish && _status == LapPlayerStatus.finished) {
      if (_lapTimes.length == lapCount) _lapTimes.removeLast();
      _finishTime = null;
    }
    _status = LapPlayerStatus.dnf;
  }

  @override
  LapProgressEvent? advanceSegment({
    required TrackPoint from,
    required TrackPoint to,
    required double stepStartTime,
    required double stepSeconds,
  }) {
    if (_status != LapPlayerStatus.racing) return null;

    for (final index in _acceptedCheckpointIndexes.toList()) {
      final backtracked = track.checkpoints[index].crossing(
        from,
        to,
        forward: false,
      );
      if (backtracked == null) continue;
      _nextGateIndex = 0;
      _acceptedCheckpointIndexes.clear();
      _expectedGateArmed = false;
      return LapProgressEvent(
        gateId: track.checkpoints[index].id,
        eventTime: stepStartTime + backtracked.t * stepSeconds,
        invalidatedProgress: true,
      );
    }

    final gate = _gateAt(_nextGateIndex);
    if (!_expectedGateArmed &&
        (gate.signedDistance(from) <= -_armingDistance ||
            gate.signedDistance(to) <= -_armingDistance)) {
      _expectedGateArmed = true;
    }
    if (!_expectedGateArmed) return null;

    final crossing = gate.crossing(from, to, forward: true);
    if (crossing == null) return null;
    final eventTime = stepStartTime + crossing.t * stepSeconds;
    if (_nextGateIndex < track.checkpoints.length) {
      _acceptedCheckpointIndexes.add(_nextGateIndex);
      _nextGateIndex++;
      _expectedGateArmed = false;
      return LapProgressEvent(gateId: gate.id, eventTime: eventTime);
    }

    final completedLap = _lapTimes.length + 1;
    _lapTimes.add(eventTime - _lapStartedAt);
    _nextGateIndex = 0;
    _acceptedCheckpointIndexes.clear();
    _expectedGateArmed = false;
    if (completedLap >= lapCount) {
      _finishTime = eventTime;
      _status = LapPlayerStatus.finished;
      return LapProgressEvent(
        gateId: gate.id,
        eventTime: eventTime,
        completedLap: completedLap,
        finished: true,
      );
    }
    _lapStartedAt = eventTime;
    return LapProgressEvent(
      gateId: gate.id,
      eventTime: eventTime,
      completedLap: completedLap,
    );
  }

  LapGate _gateAt(int index) => index < track.checkpoints.length
      ? track.checkpoints[index]
      : track.finish;
}
