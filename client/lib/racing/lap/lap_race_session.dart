import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../input/car_input.dart';
import '../simulation/race_simulation.dart';
import 'lap_player_tracker.dart';
import 'lap_race_rules.dart';
import 'lap_race_track.dart';

enum LapRacePhase { ready, countdown, racing, paused, finished }

enum LapRaceEndReason { completed, deadline, hostEnded, roomClosed }

class LapRaceSession extends ChangeNotifier {
  LapRaceSession({
    required this.simulation,
    required this.inputSource,
    required this.canStart,
    required this.controllersAvailable,
    required this.clearInputs,
    required this.setGameRunning,
    this.config = const LapRaceConfig(),
    this.track = LapRaceTrack.standard,
  }) : _red = LapPlayerTracker(
         player: PlayerId.red,
         lapCount: config.lapCount,
         track: track,
       ),
       _blue = LapPlayerTracker(
         player: PlayerId.blue,
         lapCount: config.lapCount,
         track: track,
       ) {
    _capturePositions();
    setGameRunning(true);
  }

  final RaceSimulation simulation;
  final InputSource inputSource;
  final bool Function() canStart;
  final bool Function() controllersAvailable;
  final VoidCallback clearInputs;
  final ValueChanged<bool> setGameRunning;
  final LapRaceConfig config;
  final LapRaceTrack track;
  final LapPlayerTracker _red;
  final LapPlayerTracker _blue;

  LapRacePhase _phase = LapRacePhase.ready;
  LapRacePhase? _pausedFrom;
  LapRaceEndReason? _endReason;
  PlayerId? _winner;
  bool _isDraw = false;
  double _raceTime = 0;
  double _countdownRemaining = 0;
  double _goRemaining = 0;
  double? _firstFinishTime;
  double? _finishDeadline;
  String? _message;
  TrackPoint _previousRed = const TrackPoint(0, 0);
  TrackPoint _previousBlue = const TrackPoint(0, 0);

  LapRacePhase get phase => _phase;
  LapRacePhase? get pausedFrom => _pausedFrom;
  LapRaceEndReason? get endReason => _endReason;
  PlayerId? get winner => _winner;
  bool get isDraw => _isDraw;
  double get raceTime => _raceTime;
  double get countdownRemaining => _countdownRemaining;
  int get countdownNumber => _countdownRemaining.ceil().clamp(1, 3);
  bool get showGo => _phase == LapRacePhase.racing && _goRemaining > 0;
  double? get finishDeadline => _finishDeadline;
  double? get finishTimeRemaining => _finishDeadline == null
      ? null
      : math.max(0, _finishDeadline! - _raceTime);
  String? get message => _message;
  bool get canStartRace => _phase == LapRacePhase.ready && canStart();
  bool get canPause =>
      _phase == LapRacePhase.ready ||
      _phase == LapRacePhase.countdown ||
      _phase == LapRacePhase.racing;
  bool get isComplete => _phase == LapRacePhase.finished;

  LapPlayerProgress progressFor(PlayerId player) =>
      _trackerFor(player).progressAt(_raceTime);

  Map<PlayerId, LapPlayerProgress> get results => Map.unmodifiable({
    PlayerId.red: progressFor(PlayerId.red),
    PlayerId.blue: progressFor(PlayerId.blue),
  });

  bool startCountdown() {
    if (!canStartRace) {
      _message = 'Kết nối và sẵn sàng các slot Phone trước khi bắt đầu.';
      notifyListeners();
      return false;
    }
    _message = null;
    _countdownRemaining = config.countdownSeconds;
    _phase = LapRacePhase.countdown;
    setGameRunning(true);
    notifyListeners();
    return true;
  }

  void advanceFrame(double elapsed, {bool publish = true}) {
    if (!elapsed.isFinite || elapsed <= 0) return;
    if (_phase == LapRacePhase.countdown) {
      if (!controllersAvailable()) {
        _phase = LapRacePhase.ready;
        _countdownRemaining = config.countdownSeconds;
        _message = 'Tay cầm bị ngắt hoặc mất tín hiệu trong countdown. Sẵn sàng lại để đếm từ đầu.';
        notifyListeners();
        return;
      }
      if (elapsed < _countdownRemaining) {
        _countdownRemaining -= elapsed;
        return;
      }
      final physicsElapsed = elapsed - _countdownRemaining;
      _countdownRemaining = 0;
      _phase = LapRacePhase.racing;
      _goRemaining = 0.75;
      simulation.setRunning(true);
      if (physicsElapsed > 0) {
        simulation.update(
          physicsElapsed,
          inputSource,
          onFixedStep: _onFixedStep,
        );
      }
      notifyListeners();
      return;
    }
    if (_phase != LapRacePhase.racing) return;
    simulation.update(elapsed, inputSource, onFixedStep: _onFixedStep);
    if (publish) notifyListeners();
  }

  bool pause() {
    if (!canPause) return false;
    _pausedFrom = _phase;
    _phase = LapRacePhase.paused;
    simulation.setRunning(false);
    clearInputs();
    setGameRunning(false);
    notifyListeners();
    return true;
  }

  bool resume() {
    if (_phase != LapRacePhase.paused) return false;
    final previous = _pausedFrom;
    _pausedFrom = null;
    if (previous == LapRacePhase.countdown && !canStart()) {
      _phase = LapRacePhase.ready;
      _countdownRemaining = config.countdownSeconds;
      _message =
          'Tay cầm chưa gửi input trung tính. Sẵn sàng lại để đếm từ đầu.';
    } else {
      _phase = previous ?? LapRacePhase.ready;
      if (_phase == LapRacePhase.racing) simulation.setRunning(true);
      _message = null;
    }
    setGameRunning(true);
    notifyListeners();
    return true;
  }

  bool restartFromPause() {
    if (_phase != LapRacePhase.paused) return false;
    _resetToReady();
    _message = 'Đã restart. Sẵn sàng tay cầm rồi bắt đầu countdown.';
    notifyListeners();
    return true;
  }

  bool rematch() {
    if (_phase != LapRacePhase.finished) return false;
    _resetToReady();
    _message = 'Rematch sẵn sàng. Room và controller vẫn được giữ.';
    notifyListeners();
    return true;
  }

  bool endEarly() {
    if (_phase != LapRacePhase.paused) return false;
    _markUnfinishedDnf();
    _endReason = LapRaceEndReason.hostEnded;
    _finishSession();
    return true;
  }

  void endForRoomClose() {
    if (_phase == LapRacePhase.finished) return;
    _markUnfinishedDnf();
    _endReason = LapRaceEndReason.roomClosed;
    _finishSession();
  }

  void _resetToReady() {
    simulation.reset();
    clearInputs();
    _red.reset();
    _blue.reset();
    _phase = LapRacePhase.ready;
    _pausedFrom = null;
    _endReason = null;
    _winner = null;
    _isDraw = false;
    _raceTime = 0;
    _countdownRemaining = 0;
    _goRemaining = 0;
    _firstFinishTime = null;
    _finishDeadline = null;
    _capturePositions();
    setGameRunning(true);
  }

  void _onFixedStep(double stepSeconds) {
    if (_phase != LapRacePhase.racing) return;
    final stepStartTime = _raceTime;
    final redPosition = _position(PlayerId.red);
    final bluePosition = _position(PlayerId.blue);
    final redEvent = _red.advanceSegment(
      from: _previousRed,
      to: redPosition,
      stepStartTime: stepStartTime,
      stepSeconds: stepSeconds,
    );
    final blueEvent = _blue.advanceSegment(
      from: _previousBlue,
      to: bluePosition,
      stepStartTime: stepStartTime,
      stepSeconds: stepSeconds,
    );
    _previousRed = redPosition;
    _previousBlue = bluePosition;
    _raceTime += stepSeconds;
    _goRemaining = math.max(0, _goRemaining - stepSeconds);

    final events = <(PlayerId, LapProgressEvent)>[
      if (redEvent != null) (PlayerId.red, redEvent),
      if (blueEvent != null) (PlayerId.blue, blueEvent),
    ];
    _processFinishEvents(events);
    if (_phase != LapRacePhase.finished &&
        _finishDeadline != null &&
        _raceTime >= _finishDeadline!) {
      _markUnfinishedDnf();
      _endReason = LapRaceEndReason.deadline;
      _finishSession();
      return;
    }
    if (_phase != LapRacePhase.finished && _allPlayersTerminal) {
      _endReason = LapRaceEndReason.completed;
      _finishSession();
    }
  }

  void _processFinishEvents(List<(PlayerId, LapProgressEvent)> events) {
    final finishers = events
        .where((entry) => entry.$2.finished)
        .toList(growable: false);
    if (finishers.isEmpty) return;

    final accepted = <(PlayerId, LapProgressEvent)>[];
    for (final finisher in finishers) {
      final eventTime = finisher.$2.eventTime;
      if (_finishDeadline != null && eventTime > _finishDeadline!) {
        _trackerFor(finisher.$1).markDnf(revokeFinish: true);
        simulation.finishPlayer(finisher.$1);
      } else {
        accepted.add(finisher);
        simulation.finishPlayer(finisher.$1);
      }
    }
    if (_firstFinishTime == null && accepted.isNotEmpty) {
      final decision = resolveFixedStepFinishes(
        accepted.map(
          (entry) => LapFinishCandidate(
            player: entry.$1,
            eventTime: entry.$2.eventTime,
          ),
        ),
        tieToleranceSeconds: config.tieToleranceSeconds,
      )!;
      _winner = decision.winner;
      _isDraw = decision.isDraw;
      _firstFinishTime = decision.firstFinishTime;
      if (!_isDraw) {
        _finishDeadline = _firstFinishTime! + config.finishWaitSeconds;
      }
    }
  }

  void _markUnfinishedDnf() {
    for (final player in PlayerId.values) {
      final tracker = _trackerFor(player);
      if (tracker.progressAt(_raceTime).status == LapPlayerStatus.racing) {
        tracker.markDnf();
      }
      simulation.finishPlayer(player);
    }
  }

  bool get _allPlayersTerminal => PlayerId.values.every(
    (player) =>
        _trackerFor(player).progressAt(_raceTime).status !=
        LapPlayerStatus.racing,
  );

  void _finishSession() {
    if (_phase == LapRacePhase.finished) return;
    _phase = LapRacePhase.finished;
    _pausedFrom = null;
    simulation.setRunning(false);
    clearInputs();
    setGameRunning(true);
    notifyListeners();
  }

  void _capturePositions() {
    _previousRed = _position(PlayerId.red);
    _previousBlue = _position(PlayerId.blue);
  }

  TrackPoint _position(PlayerId player) {
    final car = player == PlayerId.red ? simulation.red : simulation.blue;
    return TrackPoint(car.position.x, car.position.y);
  }

  LapPlayerTracker _trackerFor(PlayerId player) =>
      player == PlayerId.red ? _red : _blue;
}
