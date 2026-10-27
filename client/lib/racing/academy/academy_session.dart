import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../input/car_input.dart';
import '../simulation/race_simulation.dart';
import '../tracks/track_geometry.dart';
import 'academy_track.dart';

enum AcademyPhase { ready, running, paused, completed, failed }

enum AcademyRuleBasis { regulation12, gameConvention }

class AcademyPenalty {
  const AcademyPenalty({
    required this.label,
    required this.points,
    required this.elapsed,
    required this.basis,
  });

  final String label;
  final int points;
  final double elapsed;
  final AcademyRuleBasis basis;
}

/// Scoring and race-state logic kept independent of Flame and the widgets.
class AcademySession extends ChangeNotifier {
  AcademySession({
    required this.simulation,
    required this.input,
    required this.track,
  });

  static const durationSeconds = 120.0;
  static const passingScore = 80;
  static const regulationSpeedKmh = 24.0;

  final RaceSimulation simulation;
  final InputSource input;
  final AcademyTrack track;
  AcademyPhase phase = AcademyPhase.ready;
  double elapsedSeconds = 0;
  int score = 100;
  int nextCheckpoint = 0;
  final List<AcademyPenalty> penalties = [];
  String? finalMessage;
  double _lineContactSeconds = 0;
  double _nextLinePenaltyAt = 5;
  double _overtimeSeconds = 0;
  double _nextOvertimePenaltyAt = 0;
  double _speedingSeconds = 0;
  double _nextSpeedPenaltyAt = 3;
  TrackPoint? _previousPosition;
  double? _previousHeading;
  bool _finishCrossedForward = false;
  int _hudSteps = 0;

  double get remainingSeconds => math.max(0, durationSeconds - elapsedSeconds);
  int get displaySeconds => elapsedSeconds.floor();
  bool get isTerminal =>
      phase == AcademyPhase.completed || phase == AcademyPhase.failed;
  List<String> get checkpointLabels => const ['Khúc cua 1', 'Khúc cua 2'];

  void start() {
    if (phase != AcademyPhase.ready) return;
    phase = AcademyPhase.running;
    simulation.setRunning(true);
    _previousPosition = _carPoint;
    _previousHeading = simulation.red.heading;
    notifyListeners();
  }

  void pause() {
    if (phase != AcademyPhase.running) return;
    phase = AcademyPhase.paused;
    simulation.setRunning(false);
    notifyListeners();
  }

  void resume() {
    if (phase != AcademyPhase.paused) return;
    phase = AcademyPhase.running;
    _previousPosition = _carPoint;
    _previousHeading = simulation.red.heading;
    simulation.setRunning(true);
    notifyListeners();
  }

  void togglePause() => phase == AcademyPhase.running ? pause() : resume();

  void restart() {
    simulation.reset();
    phase = AcademyPhase.ready;
    elapsedSeconds = 0;
    score = 100;
    nextCheckpoint = 0;
    penalties.clear();
    finalMessage = null;
    _lineContactSeconds = 0;
    _nextLinePenaltyAt = 5;
    _overtimeSeconds = 0;
    _nextOvertimePenaltyAt = 0;
    _speedingSeconds = 0;
    _nextSpeedPenaltyAt = 3;
    _previousPosition = null;
    _previousHeading = null;
    _finishCrossedForward = false;
    _hudSteps = 0;
    notifyListeners();
  }

  /// Called once per fixed simulation step; camera updates never call this.
  void advanceStep(double seconds) {
    if (phase != AcademyPhase.running || seconds <= 0 || isTerminal) return;
    elapsedSeconds += seconds;
    _applyTimedRules(seconds);
    if (isTerminal) return;
    _checkRouteAndFinish();
    if (isTerminal) return;
    _checkLineContact(seconds);
    if (isTerminal) return;
    _previousPosition = _carPoint;
    _previousHeading = simulation.red.heading;
    if (++_hudSteps >= 12) {
      _hudSteps = 0;
      notifyListeners();
    }
  }

  TrackPoint get _carPoint =>
      TrackPoint(simulation.red.position.x, simulation.red.position.y);

  void _applyTimedRules(double dt) {
    final speedKmh = simulation.red.speed * 0.36;
    if (speedKmh > regulationSpeedKmh) {
      _speedingSeconds += dt;
      while (_speedingSeconds > _nextSpeedPenaltyAt) {
        _penalize('Vượt 24 km/h quá 3 giây', 1, AcademyRuleBasis.regulation12);
        _nextSpeedPenaltyAt += 3;
        if (isTerminal) return;
      }
    } else {
      _speedingSeconds = 0;
      _nextSpeedPenaltyAt = 3;
    }

    if (elapsedSeconds > durationSeconds) {
      _overtimeSeconds += dt;
      while (_overtimeSeconds > _nextOvertimePenaltyAt) {
        _penalize('Quá thời gian chuẩn', 5, AcademyRuleBasis.gameConvention);
        _nextOvertimePenaltyAt += durationSeconds;
        if (isTerminal) return;
      }
    }
  }

  void _checkLineContact(double dt) {
    final wheels = track.wheelsTouchingBoundary(
      _carPoint,
      simulation.red.heading,
    );
    if (wheels.isEmpty) {
      _lineContactSeconds = 0;
      _nextLinePenaltyAt = 5;
      return;
    }
    if (_lineContactSeconds == 0) {
      _penalize('Bánh xe đè vạch giới hạn', 5, AcademyRuleBasis.regulation12);
      if (isTerminal) return;
    }
    _lineContactSeconds += dt;
    while (_lineContactSeconds > _nextLinePenaltyAt) {
      _penalize(
        'Tiếp tục đè vạch quá 5 giây',
        5,
        AcademyRuleBasis.regulation12,
      );
      _nextLinePenaltyAt += 5;
      if (isTerminal) return;
    }
  }

  void _checkRouteAndFinish() {
    final previous = _previousPosition;
    final previousHeading = _previousHeading;
    if (previous == null || previousHeading == null) return;
    if (track.isEntirelyOffCourse(_carPoint, simulation.red.heading)) {
      _fail('Xe rời khỏi sa hình (quy ước của game).');
      return;
    }

    final length = track.totalLength;
    final stations = [...track.checkpointStations, length * .955];
    if (nextCheckpoint == 2 && _finishCrossedForward) {
      final gate = track.gateAt(stations[2]);
      final direction = track.directionAt(stations[2]);
      final fullyAcross = track
          .wheels(_carPoint, simulation.red.heading)
          .every(
            (wheel) =>
                (wheel.x - gate.$1.x) * direction.x +
                    (wheel.y - gate.$1.y) * direction.y >
                0,
          );
      if (fullyAcross) {
        phase = AcademyPhase.completed;
        finalMessage = 'Hoàn thành bài luyện!';
        simulation.setRunning(false);
        notifyListeners();
      }
      return;
    }
    while (nextCheckpoint < stations.length) {
      final gate = track.gateAt(stations[nextCheckpoint]);
      final direction = track.directionAt(stations[nextCheckpoint]);
      final forward = _crossesGate(
        previous,
        _carPoint,
        gate.$1,
        gate.$2,
        direction,
      );
      if (forward) {
        if (nextCheckpoint == 2) {
          _finishCrossedForward = true;
          _previousPosition = _carPoint;
          return;
        }
        nextCheckpoint++;
        notifyListeners();
        continue;
      }
      if (nextCheckpoint == 2 &&
          _crossesGate(
            previous,
            _carPoint,
            gate.$1,
            gate.$2,
            direction,
            reverse: true,
          )) {
        _fail('Qua vạch đích sai hướng (quy ước của game).');
      }
      break;
    }
    if (!isTerminal &&
        nextCheckpoint < stations.length &&
        track.stationOfClosestPoint(_carPoint) >
            stations[nextCheckpoint] + 20) {
      _fail('Bỏ qua cổng hoặc vạch đích (quy ước của game).');
    }
  }

  static bool _crossesGate(
    TrackPoint from,
    TrackPoint to,
    TrackPoint a,
    TrackPoint b,
    TrackPoint normal, {
    bool reverse = false,
  }) {
    double side(TrackPoint p) =>
        (p.x - a.x) * normal.x + (p.y - a.y) * normal.y;
    final d0 = side(from);
    final d1 = side(to);
    if (reverse ? !(d0 >= 0 && d1 < 0) : !(d0 <= 0 && d1 > 0)) return false;
    final t = d0 / (d0 - d1);
    final x = from.x + (to.x - from.x) * t;
    final y = from.y + (to.y - from.y) * t;
    final gx = b.x - a.x;
    final gy = b.y - a.y;
    final u = ((x - a.x) * gx + (y - a.y) * gy) / (gx * gx + gy * gy);
    return u >= 0 && u <= 1;
  }

  void _penalize(String label, int amount, AcademyRuleBasis basis) {
    final deducted = math.min(score, amount);
    score -= deducted;
    penalties.add(
      AcademyPenalty(
        label: label,
        points: deducted,
        elapsed: elapsedSeconds,
        basis: basis,
      ),
    );
    if (score < passingScore) {
      _fail('Điểm dưới ngưỡng 80 (ngưỡng tham khảo do game áp dụng).');
    }
  }

  void _fail(String reason) {
    if (isTerminal) return;
    phase = AcademyPhase.failed;
    finalMessage = reason;
    simulation.setRunning(false);
    notifyListeners();
  }

  static bool crossesGateForTest(
    TrackPoint from,
    TrackPoint to,
    TrackPoint a,
    TrackPoint b,
    TrackPoint normal,
  ) {
    return _crossesGate(from, to, a, b, normal);
  }
}
