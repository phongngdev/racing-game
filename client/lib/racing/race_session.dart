import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'input/car_input.dart';
import 'simulation/race_simulation.dart';
import 'tracks/track_geometry.dart';
import 'race_progress.dart';
import 'race_rules.dart';
import 'audio/race_audio.dart';

enum RacePhase { ready, countdown, racing, paused, finished }

enum RaceEndReason { completed, deadline, hostEnded, roomClosed }

/// One lifecycle and one fixed-step clock, independent of the race tracker.
class RaceSession<P extends RacePlayerProgress> extends ChangeNotifier {
  RaceSession({
    required this.simulation,
    required this.inputSource,
    required this.canStart,
    required this.controllersAvailable,
    required this.clearInputs,
    required this.setGameRunning,
    required RacePlayerTracker<P> redTracker,
    required RacePlayerTracker<P> blueTracker,
    this.config = const RaceRules(),
  }) : _red = redTracker,
       _blue = blueTracker {
    _capturePositions();
    setGameRunning(true);
  }

  final _audioEvents = StreamController<RaceFeedbackEvent>.broadcast();
  Stream<RaceFeedbackEvent> get audioEvents => _audioEvents.stream;

  void _emitAudio(String event, {PlayerId? player, int? count}) {
    if (!_audioEvents.isClosed) {
      _audioEvents.add(RaceFeedbackEvent(event, player: player, count: count));
    }
  }

  final RaceSimulation simulation;
  final InputSource inputSource;
  final bool Function() canStart;
  final bool Function() controllersAvailable;
  final VoidCallback clearInputs;
  final ValueChanged<bool> setGameRunning;
  final RaceRules config;

  final RacePlayerTracker<P> _red;
  final RacePlayerTracker<P> _blue;

  RacePhase _phase = RacePhase.ready;
  RacePhase? _pausedFrom;
  RaceEndReason? _endReason;
  PlayerId? _winner;
  bool _isDraw = false;
  double _raceTime = 0;
  double _countdownRemaining = 0;
  double _goRemaining = 0;
  bool _resumeAfterCountdown = false;
  double? _firstFinishTime;
  double? _finishDeadline;
  String? _message;
  TrackPoint _previousRed = const TrackPoint(0, 0);
  TrackPoint _previousBlue = const TrackPoint(0, 0);

  RacePhase get phase => _phase;
  RacePhase? get pausedFrom => _pausedFrom;
  RaceEndReason? get endReason => _endReason;
  PlayerId? get winner => _winner;
  bool get isDraw => _isDraw;
  double get raceTime => _raceTime;
  double get countdownRemaining => _countdownRemaining;
  int get countdownNumber => _countdownRemaining.ceil().clamp(1, 3);
  bool get showGo => _phase == RacePhase.racing && _goRemaining > 0;
  double? get finishDeadline => _finishDeadline;
  double? get finishTimeRemaining => _finishDeadline == null
      ? null
      : math.max(0, _finishDeadline! - _raceTime);
  String? get message => _message;
  bool get canStartRace => _phase == RacePhase.ready && canStart();
  bool get canPause =>
      _phase == RacePhase.ready ||
      _phase == RacePhase.countdown ||
      _phase == RacePhase.racing;
  bool get isComplete => _phase == RacePhase.finished;

  P progressFor(PlayerId player) => _trackerFor(player).progressAt(_raceTime);

  Map<PlayerId, P> get results => Map.unmodifiable({
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
    _resumeAfterCountdown = false;
    _phase = RacePhase.countdown;
    _emitAudio('countdown', count: countdownNumber);
    setGameRunning(true);
    notifyListeners();
    return true;
  }

  void advanceFrame(double elapsed, {bool publish = true}) {
    if (!elapsed.isFinite || elapsed <= 0) return;
    if (_phase == RacePhase.countdown) {
      if (!_resumeAfterCountdown && !controllersAvailable()) {
        _phase = RacePhase.ready;
        _countdownRemaining = config.countdownSeconds;
        _resumeAfterCountdown = false;
        _message = 'Tay cầm bị ngắt hoặc mất tín hiệu trong countdown. Sẵn sàng lại để đếm từ đầu.';
        notifyListeners();
        return;
      }
      if (elapsed < _countdownRemaining) {
        final previousNumber = countdownNumber;
        _countdownRemaining -= elapsed;
        if (countdownNumber != previousNumber) {
          _emitAudio('countdown', count: countdownNumber);
        }
        if (countdownNumber != previousNumber) notifyListeners();
        return;
      }
      final physicsElapsed = elapsed - _countdownRemaining;
      _countdownRemaining = 0;
      _phase = RacePhase.racing;
      _emitAudio('go');
      _resumeAfterCountdown = false;
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
    if (_phase != RacePhase.racing) return;
    final wasShowingGo = showGo;
    simulation.update(elapsed, inputSource, onFixedStep: _onFixedStep);
    final goJustEnded = _phase == RacePhase.racing && wasShowingGo && !showGo;
    if (publish || goJustEnded) notifyListeners();
  }

  bool pause() {
    if (!canPause) return false;
    _pausedFrom = _phase;
    _phase = RacePhase.paused;
    simulation.setRunning(false);
    clearInputs();
    setGameRunning(false);
    notifyListeners();
    return true;
  }

  bool resume() {
    if (_phase != RacePhase.paused) return false;
    final previous = _pausedFrom;
    _pausedFrom = null;
    if (previous == RacePhase.countdown &&
        !_resumeAfterCountdown &&
        !canStart()) {
      _phase = RacePhase.ready;
      _countdownRemaining = config.countdownSeconds;
      _message =
          'Tay cầm chưa gửi input trung tính. Sẵn sàng lại để đếm từ đầu.';
    } else if (previous == RacePhase.racing) {
      _phase = RacePhase.countdown;
      _countdownRemaining = config.countdownSeconds;
      _resumeAfterCountdown = true;
      _emitAudio('countdown', count: countdownNumber);
      _message = null;
    } else {
      _phase = previous ?? RacePhase.ready;
      if (_phase == RacePhase.racing) simulation.setRunning(true);
      _message = null;
    }
    setGameRunning(true);
    notifyListeners();
    return true;
  }

  bool restartFromPause() {
    if (_phase != RacePhase.paused) return false;
    _resetToReady();
    _message = 'Đã restart. Sẵn sàng tay cầm rồi bắt đầu countdown.';
    notifyListeners();
    return true;
  }

  bool rematch() {
    if (_phase != RacePhase.finished) return false;
    _resetToReady();
    _message = 'Rematch sẵn sàng. Room và controller vẫn được giữ.';
    notifyListeners();
    return true;
  }

  bool endEarly() {
    if (_phase != RacePhase.paused) return false;
    _markUnfinishedDnf();
    _endReason = RaceEndReason.hostEnded;
    _finishSession();
    return true;
  }

  void endForRoomClose() {
    if (_phase == RacePhase.finished) return;
    _markUnfinishedDnf();
    _endReason = RaceEndReason.roomClosed;
    _finishSession();
  }

  void _resetToReady() {
    simulation.reset();
    clearInputs();
    _red.reset();
    _blue.reset();
    _phase = RacePhase.ready;
    _pausedFrom = null;
    _endReason = null;
    _winner = null;
    _isDraw = false;
    _raceTime = 0;
    _countdownRemaining = 0;
    _goRemaining = 0;
    _resumeAfterCountdown = false;
    _firstFinishTime = null;
    _finishDeadline = null;
    _capturePositions();
    setGameRunning(true);
  }

  void _onFixedStep(double stepSeconds) {
    if (_phase != RacePhase.racing) return;
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

    final events = <(PlayerId, RaceProgressEvent)>[
      if (redEvent != null) (PlayerId.red, redEvent),
      if (blueEvent != null) (PlayerId.blue, blueEvent),
    ];
    _processFinishEvents(events);
    if (_phase != RacePhase.finished &&
        _finishDeadline != null &&
        _raceTime >= _finishDeadline!) {
      _markUnfinishedDnf();
      _endReason = RaceEndReason.deadline;
      _finishSession();
      return;
    }
    if (_phase != RacePhase.finished && _allPlayersTerminal) {
      _endReason = RaceEndReason.completed;
      _finishSession();
    }
  }

  void _processFinishEvents(List<(PlayerId, RaceProgressEvent)> events) {
    final finishers = events
        .where((entry) => entry.$2.finished)
        .toList(growable: false);
    if (finishers.isEmpty) return;

    final accepted = <(PlayerId, RaceProgressEvent)>[];
    for (final entry in events) {
      if (!entry.$2.finished && !entry.$2.invalidatedProgress) {
        _emitAudio('checkpoint', player: entry.$1);
      }
    }
    for (final finisher in finishers) {
      final eventTime = finisher.$2.eventTime;
      if (_finishDeadline != null && eventTime > _finishDeadline!) {
        _trackerFor(finisher.$1).markDnf(revokeFinish: true);
        simulation.finishPlayer(finisher.$1);
      } else {
        accepted.add(finisher);
        _emitAudio('finish', player: finisher.$1);
        simulation.finishPlayer(finisher.$1);
      }
    }
    if (_firstFinishTime == null && accepted.isNotEmpty) {
      final decision = resolveFixedStepFinishes(
        accepted.map(
          (entry) => RaceFinishCandidate(
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
      if (tracker.progressAt(_raceTime).status == RacePlayerStatus.racing) {
        tracker.markDnf();
      }
      simulation.finishPlayer(player);
    }
  }

  bool get _allPlayersTerminal => PlayerId.values.every(
    (player) =>
        _trackerFor(player).progressAt(_raceTime).status !=
        RacePlayerStatus.racing,
  );

  void _finishSession() {
    if (_phase == RacePhase.finished) return;
    if (_isDraw) {
      _emitAudio('draw');
    } else if (_winner != null) {
      _emitAudio('victory', player: _winner);
    } else {
      _emitAudio('dnf');
    }
    _phase = RacePhase.finished;
    _pausedFrom = null;
    _resumeAfterCountdown = false;
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

  RacePlayerTracker<P> _trackerFor(PlayerId player) =>
      player == PlayerId.red ? _red : _blue;

  @override
  void dispose() {
    _audioEvents.close();
    super.dispose();
  }
}
