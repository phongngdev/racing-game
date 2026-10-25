import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/lap/lap_player_tracker.dart';
import 'package:racing_client/racing/lap/lap_race_rules.dart';
import 'package:racing_client/racing/lap/lap_race_session.dart';
import 'package:racing_client/racing/lap/lap_race_track.dart';
import 'package:racing_client/racing/simulation/race_simulation.dart';

void main() {
  test('host ending before any finish records two DNF and no winner', () {
    final fixture = _RaceFixture();
    addTearDown(fixture.dispose);
    final race = fixture.race;

    expect(race.startCountdown(), isTrue);
    race.advanceFrame(3);
    expect(race.phase, LapRacePhase.racing);
    expect(race.progressFor(PlayerId.red).status, LapPlayerStatus.racing);
    expect(race.progressFor(PlayerId.blue).status, LapPlayerStatus.racing);

    expect(race.pause(), isTrue);
    expect(race.endEarly(), isTrue);
    expect(race.phase, LapRacePhase.finished);
    expect(race.progressFor(PlayerId.red).status, LapPlayerStatus.dnf);
    expect(race.progressFor(PlayerId.blue).status, LapPlayerStatus.dnf);
    expect(race.winner, isNull);
    expect(race.isDraw, isFalse);
    expect(race.endReason, LapRaceEndReason.hostEnded);
  });

  test('countdown pause preserves remaining time and race clock freezes', () {
    final fixture = _RaceFixture();
    addTearDown(fixture.dispose);
    final race = fixture.race;

    expect(race.startCountdown(), isTrue);
    race.advanceFrame(1.25);
    expect(race.countdownNumber, 2);
    expect(race.pause(), isTrue);
    final remaining = race.countdownRemaining;
    race.advanceFrame(4);
    expect(race.countdownRemaining, remaining);

    expect(race.resume(), isTrue);
    race.advanceFrame(remaining);
    expect(race.phase, LapRacePhase.racing);
    expect(race.raceTime, 0);
    race.advanceFrame(0.1);
    expect(race.raceTime, closeTo(8 / 120, 1e-9));

    expect(race.pause(), isTrue);
    final pausedAt = race.raceTime;
    race.advanceFrame(5);
    expect(race.raceTime, pausedAt);
    fixture.canStart = false;
    fixture.controllersAvailable = false;
    expect(race.resume(), isTrue);
    expect(race.phase, LapRacePhase.racing);
  });

  test('controller loss aborts countdown and requires a fresh start', () {
    final fixture = _RaceFixture();
    addTearDown(fixture.dispose);
    final race = fixture.race;

    expect(race.startCountdown(), isTrue);
    race.advanceFrame(1);
    fixture.controllersAvailable = false;
    race.advanceFrame(1 / 60);

    expect(race.phase, LapRacePhase.ready);
    expect(race.countdownRemaining, 3);
    expect(race.startCountdown(), isFalse);
  });

  test(
    'both players finishing in one fixed step produce an order-free draw',
    () {
      final fixture = _RaceFixture(lapCount: 1);
      addTearDown(fixture.dispose);
      final race = fixture.race;

      expect(race.startCountdown(), isTrue);
      race.advanceFrame(3);

      void step(TrackPoint red, TrackPoint blue) {
        fixture.simulation.red.position.setValues(red.x, red.y);
        fixture.simulation.blue.position.setValues(blue.x, blue.y);
        race.advanceFrame(1 / 120);
      }

      step(const TrackPoint(800, 330), const TrackPoint(840, 330));
      step(const TrackPoint(470, 500), const TrackPoint(470, 540));
      step(const TrackPoint(170, 310), const TrackPoint(230, 310));
      step(const TrackPoint(470, 112), const TrackPoint(470, 166));
      step(const TrackPoint(490, 112), const TrackPoint(490, 166));

      expect(race.phase, LapRacePhase.finished);
      expect(race.progressFor(PlayerId.red).status, LapPlayerStatus.finished);
      expect(race.progressFor(PlayerId.blue).status, LapPlayerStatus.finished);
      expect(race.isDraw, isTrue);
      expect(race.winner, isNull);
      expect(race.endReason, LapRaceEndReason.completed);
    },
  );

  test('the first finisher is held while the other gets simulation time', () {
    final fixture = _RaceFixture(lapCount: 1, finishWaitSeconds: 0.02);
    addTearDown(fixture.dispose);
    final race = fixture.race;

    expect(race.startCountdown(), isTrue);
    race.advanceFrame(3);

    void step(TrackPoint red, TrackPoint blue) {
      fixture.simulation.red.position.setValues(red.x, red.y);
      fixture.simulation.blue.position.setValues(blue.x, blue.y);
      race.advanceFrame(1 / 120);
    }

    step(const TrackPoint(800, 330), const TrackPoint(840, 330));
    step(const TrackPoint(470, 500), const TrackPoint(470, 540));
    step(const TrackPoint(170, 310), const TrackPoint(230, 310));
    step(const TrackPoint(470, 112), const TrackPoint(470, 166));
    step(const TrackPoint(490, 112), const TrackPoint(470, 166));

    expect(race.phase, LapRacePhase.racing);
    expect(race.winner, PlayerId.red);
    expect(race.finishTimeRemaining, greaterThan(0));
    expect(race.progressFor(PlayerId.blue).status, LapPlayerStatus.racing);

    race.advanceFrame(0.1);

    expect(race.phase, LapRacePhase.finished);
    expect(race.endReason, LapRaceEndReason.deadline);
    expect(race.progressFor(PlayerId.red).status, LapPlayerStatus.finished);
    expect(race.progressFor(PlayerId.blue).status, LapPlayerStatus.dnf);
  });

  test('Restart is pause-only and Rematch is results-only', () {
    final fixture = _RaceFixture();
    addTearDown(fixture.dispose);
    final race = fixture.race;
    final impacts = <CollisionEvent>[];
    final subscription = fixture.simulation.collisionEvents.listen(impacts.add);
    addTearDown(subscription.cancel);

    void expectVehicleCollisionAfterReset() {
      impacts.clear();
      fixture.simulation.red.position.setValues(230, 180);
      fixture.simulation.blue.position.setValues(260, 180);
      fixture.simulation.red.heading = 0;
      fixture.simulation.blue.heading = 3.141592653589793;
      fixture.keyboard.handleKey(LogicalKeyboardKey.keyW, true);
      fixture.keyboard.handleKey(LogicalKeyboardKey.arrowUp, true);
      race.advanceFrame(fixture.simulation.config.fixedStep);
      fixture.keyboard.clear();
      expect(
        impacts.map((event) => event.type),
        contains(CollisionType.vehicle),
      );
    }

    expect(race.restartFromPause(), isFalse);
    expect(race.rematch(), isFalse);
    expect(race.startCountdown(), isTrue);
    race.advanceFrame(3);
    fixture.simulation.red.position.setValues(500, 300);
    fixture.simulation.finishPlayer(PlayerId.red);
    expect(race.restartFromPause(), isFalse);
    expect(race.pause(), isTrue);
    expect(race.restartFromPause(), isTrue);
    expect(race.phase, LapRacePhase.ready);
    expect(race.raceTime, 0);
    expect(fixture.simulation.red.position.x, 430);
    expect(fixture.simulation.isPlayerFinished(PlayerId.red), isFalse);

    expect(race.startCountdown(), isTrue);
    race.advanceFrame(3);
    expectVehicleCollisionAfterReset();
    expect(race.pause(), isTrue);
    expect(race.endEarly(), isTrue);
    expect(race.rematch(), isTrue);
    expect(race.phase, LapRacePhase.ready);
    expect(race.winner, isNull);
    expect(race.progressFor(PlayerId.red).completedLaps, 0);
    expect(race.progressFor(PlayerId.blue).completedLaps, 0);
    expect(fixture.simulation.isPlayerFinished(PlayerId.red), isFalse);
    expect(fixture.simulation.isPlayerFinished(PlayerId.blue), isFalse);

    expect(race.startCountdown(), isTrue);
    race.advanceFrame(3);
    expectVehicleCollisionAfterReset();
  });
}

class _RaceFixture {
  _RaceFixture({int lapCount = 3, double finishWaitSeconds = 60})
    : simulation = RaceSimulation(
        redStartPosition: Vector2(430, 112),
        blueStartPosition: Vector2(430, 166),
      ) {
    keyboard = KeyboardInputSource();
    race = LapRaceSession(
      simulation: simulation,
      inputSource: keyboard,
      canStart: () => canStart,
      controllersAvailable: () => controllersAvailable,
      clearInputs: () {},
      setGameRunning: (_) {},
      config: LapRaceConfig(
        lapCount: lapCount,
        finishWaitSeconds: finishWaitSeconds,
      ),
    );
  }

  final RaceSimulation simulation;
  late final KeyboardInputSource keyboard;
  late final LapRaceSession race;
  bool canStart = true;
  bool controllersAvailable = true;

  void dispose() {
    race.dispose();
    simulation.dispose();
  }
}
