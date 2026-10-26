import '../input/car_input.dart';
import '../race_progress.dart';
import '../tracks/track_definition.dart';
import '../tracks/track_geometry.dart';

class SprintPlayerProgress implements RacePlayerProgress {
  const SprintPlayerProgress({
    required this.player,
    required this.status,
    required this.finishTime,
    required this.nextGateId,
    required this.completedCheckpoints,
    required this.totalCheckpoints,
    required this.fraction,
  });
  @override
  final PlayerId player;
  @override
  final RacePlayerStatus status;
  @override
  final double? finishTime;
  @override
  final String? nextGateId;
  final int completedCheckpoints;
  final int totalCheckpoints;
  final double fraction;
}

class SprintPlayerTracker implements RacePlayerTracker<SprintPlayerProgress> {
  SprintPlayerTracker({required this.player, required this.track}) {
    reset();
  }
  final PlayerId player;
  final TrackDefinition track;
  int _next = 0;
  bool _armed = false;
  RacePlayerStatus _status = RacePlayerStatus.racing;
  double? _finishTime;
  late TrackPoint _position;

  @override
  SprintPlayerProgress progressAt(double raceTime) {
    final lower = _next == 0
        ? track.gridStation
        : track.checkpointStations[_next - 1];
    final upper = _next < track.checkpoints.length
        ? track.checkpointStations[_next]
        : track.finishStation;
    final station = track.projectStation(_position, lower, upper);
    final fraction = _status == RacePlayerStatus.finished
        ? 1.0
        : ((station - track.gridStation) /
                  (track.finishStation - track.gridStation))
              .clamp(0.0, 0.999);
    return SprintPlayerProgress(
      player: player,
      status: _status,
      finishTime: _finishTime,
      nextGateId: _status != RacePlayerStatus.racing
          ? null
          : _next < track.checkpoints.length
          ? track.checkpoints[_next].id
          : 'finish',
      completedCheckpoints: _next,
      totalCheckpoints: track.checkpoints.length,
      fraction: fraction,
    );
  }

  @override
  void reset({double raceStartTime = 0}) {
    _next = 0;
    _armed = false;
    _status = RacePlayerStatus.racing;
    _finishTime = null;
    _position =
        (player == PlayerId.red ? track.redSpawn : track.blueSpawn).position;
  }

  @override
  void markDnf({bool revokeFinish = false}) {
    if (_status == RacePlayerStatus.finished && !revokeFinish) return;
    _status = RacePlayerStatus.dnf;
    _finishTime = null;
  }

  @override
  RaceProgressEvent? advanceSegment({
    required TrackPoint from,
    required TrackPoint to,
    required double stepStartTime,
    required double stepSeconds,
  }) {
    if (_status != RacePlayerStatus.racing) return null;
    _position = to;
    // Rolling back keeps earlier gates, but requires this gate to be crossed again.
    for (var i = _next - 1; i >= 0; i--) {
      final crossing = track.checkpoints[i].crossing(from, to, forward: false);
      if (crossing == null) continue;
      _next = i;
      _armed = false;
      return RaceProgressEvent(
        gateId: track.checkpoints[i].id,
        eventTime: stepStartTime + crossing.t * stepSeconds,
        invalidatedProgress: true,
      );
    }
    final gate = _next < track.checkpoints.length
        ? track.checkpoints[_next]
        : track.finish;
    if (gate.signedDistance(from) <= -0.01 ||
        gate.signedDistance(to) <= -0.01) {
      _armed = true;
    }
    if (!_armed) return null;
    final crossing = gate.crossing(from, to, forward: true);
    if (crossing == null) return null;
    _armed = false;
    final time = stepStartTime + crossing.t * stepSeconds;
    if (_next < track.checkpoints.length) {
      _next++;
      return RaceProgressEvent(gateId: gate.id, eventTime: time);
    }
    _status = RacePlayerStatus.finished;
    _finishTime = time;
    return RaceProgressEvent(gateId: gate.id, eventTime: time, finished: true);
  }
}
