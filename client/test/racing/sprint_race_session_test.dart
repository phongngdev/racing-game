import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/race_progress.dart';
import 'package:racing_client/racing/race_rules.dart';
import 'package:racing_client/racing/race_session.dart';
import 'package:racing_client/racing/simulation/race_simulation.dart';
import 'package:racing_client/racing/sprint/sprint_race_session.dart';
import 'package:racing_client/racing/tracks/track_definition.dart';
import 'package:racing_client/racing/tracks/track_geometry.dart';

void main() {
  test('countdown and GO publish only visible state changes', () {
    final f = _Fixture();
    addTearDown(f.dispose);
    var notifications = 0;
    void countNotification() => notifications++;
    f.race.addListener(countNotification);
    addTearDown(() => f.race.removeListener(countNotification));

    expect(f.race.startCountdown(), isTrue);
    expect(notifications, 1);
    f.race.advanceFrame(0.5, publish: false);
    expect(notifications, 1);
    f.race.advanceFrame(0.6, publish: false);
    expect(f.race.countdownNumber, 2);
    expect(notifications, 2);

    f.race.advanceFrame(2, publish: false);
    expect(f.race.phase, RacePhase.racing);
    expect(f.race.showGo, isTrue);
    expect(notifications, 3);
    f.race.advanceFrame(0.1, publish: false);
    expect(f.race.showGo, isTrue);
    expect(notifications, 3);
    for (var i = 0; i < 20 && f.race.showGo; i++) {
      f.race.advanceFrame(0.1, publish: false);
    }
    expect(f.race.showGo, isFalse);
    expect(notifications, 4);
  });

  test(
    'resuming a paused race waits three seconds with physics and clock frozen',
    () {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.start();
      f.race.advanceFrame(0.1);
      final pausedAt = f.race.raceTime;
      expect(f.race.pause(), isTrue);

      expect(f.race.resume(), isTrue);
      expect(f.race.phase, RacePhase.countdown);
      expect(f.race.countdownNumber, 3);
      expect(f.simulation.isRunning, isFalse);
      f.race.advanceFrame(2.99, publish: false);
      expect(f.race.phase, RacePhase.countdown);
      expect(f.race.countdownNumber, 1);
      expect(f.race.raceTime, pausedAt);
      expect(f.simulation.isRunning, isFalse);

      f.race.advanceFrame(0.02, publish: false);
      expect(f.race.phase, RacePhase.racing);
      expect(f.simulation.isRunning, isTrue);
      expect(f.race.raceTime, greaterThan(pausedAt));
    },
  );

  for (final first in PlayerId.values) {
    test(
      '$first wins, second player finishes later, Results waits for both',
      () {
        final f = _Fixture();
        addTearDown(f.dispose);
        f.start();
        expect(f.race.config.finishWaitSeconds, 60);
        for (final gate in f.track.checkpoints) {
          f.cross(gate, PlayerId.values);
        }
        f.cross(f.track.finish, [first]);
        expect(f.race.phase, RacePhase.racing);
        expect(f.race.winner, first);
        final second = first == PlayerId.red ? PlayerId.blue : PlayerId.red;
        expect(f.race.progressFor(second).status, RacePlayerStatus.racing);
        f.cross(f.track.finish, [second]);
        expect(f.race.phase, RacePhase.finished);
        expect(f.race.endReason, RaceEndReason.completed);
        expect(f.race.winner, first);
        expect(
          f.race.results.values.every(
            (p) => p.status == RacePlayerStatus.finished,
          ),
          isTrue,
        );
      },
    );
  }
  test('both Sprint players finish in one step, draw, then Rematch restores the race', () {
    final f = _Fixture();
    addTearDown(f.dispose);
    f.start();
    for (final gate in [...f.track.checkpoints, f.track.finish]) {
      f.cross(gate, PlayerId.values);
    }
    expect(f.race.phase, RacePhase.finished);
    expect(f.race.isDraw, isTrue);
    expect(f.race.winner, isNull);
    for (final player in PlayerId.values) {
      expect(f.race.progressFor(player).status, RacePlayerStatus.finished);
      expect(f.simulation.isPlayerFinished(player), isTrue);
    }
    expect(f.race.rematch(), isTrue);
    expect(f.race.phase, RacePhase.ready);
    expect(f.race.raceTime, 0);
    for (final player in PlayerId.values) {
      expect(f.race.progressFor(player).fraction, 0);
      expect(f.simulation.isPlayerFinished(player), isFalse);
    }
    expect(f.simulation.red.position.x, f.track.redSpawn.position.x);
  });

  test('first finish waits for simulation deadline, Pause freezes it, late player is DNF', () {
    final f = _Fixture(wait: 0.1);
    addTearDown(f.dispose);
    f.start();
    for (final gate in [...f.track.checkpoints, f.track.finish]) {
      f.cross(gate, [PlayerId.red]);
    }
    expect(f.race.phase, RacePhase.racing);
    expect(f.race.winner, PlayerId.red);
    final deadline = f.race.finishTimeRemaining;
    f.race.pause();
    f.race.advanceFrame(60);
    expect(f.race.finishTimeRemaining, deadline);
    f.race.resume();
    f.race.advanceFrame(3);
    for (var i = 0; i < 20; i++) {
      f.race.advanceFrame(1 / 120);
    }
    expect(f.race.phase, RacePhase.finished);
    expect(f.race.endReason, RaceEndReason.deadline);
    expect(f.race.progressFor(PlayerId.blue).status, RacePlayerStatus.dnf);
    expect(f.race.progressFor(PlayerId.red).status, RacePlayerStatus.finished);
    expect(f.race.rematch(), isTrue);
    expect(f.race.progressFor(PlayerId.blue).status, RacePlayerStatus.racing);
  });

  test('controller loss during racing preserves progress and allows the clock to continue', () {
    final f = _Fixture();
    addTearDown(f.dispose);
    f.start();
    f.cross(f.track.checkpoints.first, [PlayerId.red]);
    final time = f.race.raceTime;
    f.available = false;
    f.race.advanceFrame(1 / 120);
    expect(f.race.raceTime, greaterThan(time));
    expect(f.race.progressFor(PlayerId.red).completedCheckpoints, 1);
    f.available = true;
    f.race.pause();
    expect(f.race.restartFromPause(), isTrue);
    expect(f.race.progressFor(PlayerId.red).completedCheckpoints, 0);
    f.race.endForRoomClose();
    expect(f.race.winner, isNull);
    expect(
      f.race.results.values.every((p) => p.status == RacePlayerStatus.dnf),
      isTrue,
    );
  });

  for (final player in PlayerId.values) {
    test('real physics can drive $player through every corner and finish', () {
      final track = FixedTracks.sprint;
      final simulation = RaceSimulation(track: track);
      addTearDown(simulation.dispose);
      final input = _RouteDriver(simulation, track, player);
      final race = SprintRaceSession(
        simulation: simulation,
        inputSource: input,
        canStart: () => true,
        controllersAvailable: () => true,
        clearInputs: () {},
        setGameRunning: (_) {},
        track: track,
      );
      addTearDown(race.dispose);
      race.startCountdown();
      race.advanceFrame(3);
      final other = player == PlayerId.red ? PlayerId.blue : PlayerId.red;
      simulation.finishPlayer(other);
      for (
        var i = 0;
        i < 120 * 120 &&
            race.progressFor(player).status == RacePlayerStatus.racing;
        i++
      ) {
        race.advanceFrame(1 / 120, publish: false);
      }
      expect(
        race.progressFor(player).status,
        RacePlayerStatus.finished,
        reason: 'Car must finish using physics, without teleporting or removing walls.',
      );
      expect(race.progressFor(player).completedCheckpoints, 8);
    });
  }
}

class _Fixture {
  _Fixture({double wait = 60}) {
    simulation = RaceSimulation(track: track);
    race = SprintRaceSession(
      simulation: simulation,
      inputSource: KeyboardInputSource(),
      canStart: () => available,
      controllersAvailable: () => available,
      clearInputs: () {},
      setGameRunning: (_) {},
      track: track,
      config: RaceRules(finishWaitSeconds: wait),
    );
  }
  final track = FixedTracks.sprint;
  late final RaceSimulation simulation;
  late final SprintRaceSession race;
  bool available = true;
  void start() {
    expect(race.startCountdown(), isTrue);
    race.advanceFrame(3);
  }

  void cross(TrackGate gate, List<PlayerId> players) {
    final middle = gate.start.lerpTo(gate.end, 0.5);
    final normal = switch (gate.direction) {
      TrackDirection.east => const TrackPoint(1, 0),
      TrackDirection.west => const TrackPoint(-1, 0),
      TrackDirection.south => const TrackPoint(0, 1),
      TrackDirection.north => const TrackPoint(0, -1),
    };
    for (final distance in [-2.0, 2.0]) {
      for (final player in players) {
        final offset = player == PlayerId.red ? -32 : 32;
        final car = player == PlayerId.red ? simulation.red : simulation.blue;
        car.position.setValues(
          middle.x + normal.x * distance - normal.y * offset,
          middle.y + normal.y * distance + normal.x * offset,
        );
      }
      race.advanceFrame(1 / 120);
    }
  }

  void dispose() {
    race.dispose();
    simulation.dispose();
  }
}

/// Test-only driver. It steers through actual simulation walls at the normal speed.
class _RouteDriver implements InputSource {
  _RouteDriver(this.simulation, this.track, this.player);
  final RaceSimulation simulation;
  final TrackDefinition track;
  final PlayerId player;
  int _waypoint = 1;
  @override
  CarInput inputFor(PlayerId id) {
    if (id != player) return const CarInput();
    final car = player == PlayerId.red ? simulation.red : simulation.blue;
    var target = track.centerline[_waypoint];
    if (_waypoint < track.centerline.length - 1 &&
        math.sqrt(
              math.pow(target.x - car.position.x, 2) +
                  math.pow(target.y - car.position.y, 2),
            ) <
            110) {
      target = track.centerline[++_waypoint];
    }
    final angle = math.atan2(
      target.y - car.position.y,
      target.x - car.position.x,
    );
    final error = math.atan2(
      math.sin(angle - car.heading),
      math.cos(angle - car.heading),
    );
    return CarInput(throttle: 1, steering: (error * 2).clamp(-1.0, 1.0));
  }
}
