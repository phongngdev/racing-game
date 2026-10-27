import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/academy/academy_game_page.dart';
import 'package:racing_client/racing/academy/academy_input_source.dart';
import 'package:racing_client/racing/academy/academy_session.dart';
import 'package:racing_client/racing/academy/academy_track.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/input/remote_input_source.dart';
import 'package:racing_client/racing/simulation/race_simulation.dart';
import 'package:racing_client/racing/tracks/track_geometry.dart';

void main() {
  late AcademyTrack track;
  late RaceSimulation simulation;
  late AcademySession session;
  late KeyboardInputSource input;

  void create({InputSource? source}) {
    track = AcademyTrack.sBend();
    input = KeyboardInputSource();
    simulation = RaceSimulation(
      config: RaceConfig.academy,
      wallRects: const [],
      redStartPosition: Vector2(track.spawn.x, track.spawn.y),
    );
    if (source is _RouteFollower) source.bind(simulation);
    session = AcademySession(
      simulation: simulation,
      input: source ?? input,
      track: track,
    );
  }

  void dispose() {
    session.dispose();
    simulation.dispose();
  }

  const step = 1 / 120;

  void touchBoundary() => simulation.red.position.setValues(
    track.spawn.x,
    track.spawn.y - track.halfWidth + AcademyTrack.wheelOffsetLateral,
  );

  setUp(() => create());
  tearDown(() => dispose());

  test('clean entry begins at 100 and does not accrue a penalty', () {
    session.start();
    session.advanceStep(step);
    expect(session.score, 100);
    expect(session.penalties, isEmpty);
    expect(session.elapsedSeconds, closeTo(step, 1e-8));
  });

  test('wheel contact deducts once while contact remains active', () {
    session.start();
    touchBoundary();
    for (var i = 0; i < 120; i++) {
      session.advanceStep(step);
    }
    expect(session.score, 95);
    expect(session.penalties, hasLength(1));
    expect(session.penalties.single.basis, AcademyRuleBasis.regulation12);
  });

  test(
    'continued wheel contact deducts again after more than five seconds',
    () {
      session.start();
      touchBoundary();
      for (var i = 0; i < 601; i++) {
        session.advanceStep(step);
      }
      expect(session.score, 90);
      expect(session.penalties.map((penalty) => penalty.points), [5, 5]);
    },
  );

  test('leaving and touching the boundary again starts a new event', () {
    session.start();
    touchBoundary();
    session.advanceStep(step);
    simulation.red.position.setValues(track.spawn.x, track.spawn.y);
    session.advanceStep(step);
    touchBoundary();
    session.advanceStep(step);
    expect(session.score, 90);
    expect(session.penalties, hasLength(2));
  });

  test(
    'time beyond the two-minute standard is labeled and scored separately',
    () {
      session.start();
      for (var i = 0; i < 14401; i++) {
        session.advanceStep(step);
      }
      expect(session.elapsedSeconds, greaterThan(120));
      expect(session.penalties, hasLength(1));
      expect(session.penalties.single.label, 'Quá thời gian chuẩn');
      expect(session.penalties.single.basis, AcademyRuleBasis.gameConvention);
      expect(session.score, 95);
    },
  );

  test(
    'speeding is counted only after three seconds above the class limit',
    () {
      session.start();
      simulation.red.driveSpeed = 70;
      for (var i = 0; i < 361; i++) {
        session.advanceStep(step);
      }
      expect(session.penalties, hasLength(1));
      expect(session.penalties.single.label, contains('24 km/h'));
      expect(session.score, 99);
    },
  );

  test(
    'leaving the route and skipping an unvisited gate fail by game convention',
    () {
      session.start();
      simulation.red.position.setValues(1100, 900);
      session.advanceStep(step);
      expect(session.phase, AcademyPhase.failed);
      expect(session.finalMessage, contains('rời khỏi sa hình'));

      session.restart();
      session.start();
      final later = track.pointAt(track.totalLength * .85);
      simulation.red.position.setValues(later.x, later.y);
      session.advanceStep(step);
      expect(session.phase, AcademyPhase.failed);
      expect(session.finalMessage, contains('Bỏ qua cổng'));
    },
  );

  test('a backwards finish crossing fails with a game-convention reason', () {
    final station = track.totalLength * .955;
    final gate = track.gateAt(station);
    final direction = track.directionAt(station);
    final center = TrackPoint(
      (gate.$1.x + gate.$2.x) / 2,
      (gate.$1.y + gate.$2.y) / 2,
    );
    session.start();
    session.nextCheckpoint = 2;
    simulation.red.heading = math.atan2(direction.y, direction.x);
    simulation.red.position.setValues(
      center.x + direction.x * 2,
      center.y + direction.y * 2,
    );
    // Use the current pose as the prior pose after arming the test state.
    session.pause();
    session.resume();
    simulation.red.position.setValues(
      center.x - direction.x * 2,
      center.y - direction.y * 2,
    );
    session.advanceStep(step);
    expect(session.phase, AcademyPhase.failed);
    expect(session.finalMessage, contains('sai hướng'));
  });

  test(
    'correct ordered route and fully crossed finish complete the lesson',
    () {
      final station = track.totalLength * .955;
      final gate = track.gateAt(station);
      final direction = track.directionAt(station);
      final center = TrackPoint(
        (gate.$1.x + gate.$2.x) / 2,
        (gate.$1.y + gate.$2.y) / 2,
      );
      simulation.red.heading = math.atan2(direction.y, direction.x);
      simulation.red.position.setValues(
        center.x - direction.x * 20,
        center.y - direction.y * 20,
      );
      session.start();
      session.nextCheckpoint = 2;
      simulation.red.position.setValues(
        center.x + direction.x * 15,
        center.y + direction.y * 15,
      );
      session.advanceStep(step);
      expect(session.phase, AcademyPhase.running);
      session.advanceStep(step);
      expect(session.phase, AcademyPhase.completed);
      expect(session.elapsedSeconds, greaterThan(0));
    },
  );

  test(
    'restart resets score, time, penalties, route progress, and vehicle pose',
    () {
      session.start();
      touchBoundary();
      session.advanceStep(step);
      session.nextCheckpoint = 1;
      session.restart();
      expect(session.phase, AcademyPhase.ready);
      expect(session.score, 100);
      expect(session.elapsedSeconds, 0);
      expect(session.penalties, isEmpty);
      expect(session.nextCheckpoint, 0);
      expect(simulation.red.position.x, closeTo(track.spawn.x, 1e-9));
      expect(simulation.red.position.y, closeTo(track.spawn.y, 1e-9));
    },
  );

  for (final throttle in [.6, 1.0]) {
    test(
      'Academy profile completes both arcs without touching a line at throttle $throttle',
      () {
        dispose();
        create(source: _RouteFollower(track, throttle: throttle));
        session.start();
        for (var i = 0; i < 12000 && !session.isTerminal; i++) {
          simulation.update(
            1 / 60,
            session.input,
            onFixedStep: session.advanceStep,
          );
        }
        expect(
          session.phase,
          AcademyPhase.completed,
          reason:
              'Actual fixed-step vehicle must drive the corridor. ${session.finalMessage}',
        );
        expect(session.penalties, isEmpty);
        expect(session.score, 100);
        expect(
          session.elapsedSeconds,
          lessThan(AcademySession.durationSeconds),
        );
      },
    );
  }

  test('keyboard accepts either WASD or arrows for the visible car', () {
    final source = AcademyInputSource(
      remote: RemoteInputSource(),
      usePhone: false,
    );
    source.handleKey(LogicalKeyboardKey.arrowUp, true);
    source.handleKey(LogicalKeyboardKey.arrowRight, true);
    expect(source.inputFor(PlayerId.red).throttle, 1);
    expect(source.inputFor(PlayerId.red).steering, 1);
    source.clear();
    expect(source.inputFor(PlayerId.red).throttle, 0);
    expect(source.inputFor(PlayerId.red).steering, 0);
  });

  test('follow and overview camera changes do not advance lesson state', () {
    final game = AcademyFlameGame(
      simulation: simulation,
      session: session,
      track: track,
    );
    session.start();
    final elapsed = session.elapsedSeconds;
    final position = simulation.red.position.clone();
    game.setOverview(true);
    game.setOverview(false);
    expect(session.elapsedSeconds, elapsed);
    expect(session.score, 100);
    expect(session.nextCheckpoint, 0);
    expect(simulation.red.position.x, position.x);
    expect(simulation.red.position.y, position.y);
  });
}

class _RouteFollower implements InputSource {
  _RouteFollower(this.track, {required this.throttle});
  final AcademyTrack track;
  final double throttle;

  @override
  CarInput inputFor(PlayerId player) {
    if (player != PlayerId.red) return const CarInput();
    final car = _simulation!.red;
    final station = track.stationOfClosestPoint(
      TrackPoint(car.position.x, car.position.y),
    );
    final target = track.pointAt(math.min(track.totalLength, station + 40));
    final targetHeading = math.atan2(
      target.y - car.position.y,
      target.x - car.position.x,
    );
    var error =
        (targetHeading - car.heading + math.pi) % (2 * math.pi) - math.pi;
    if (error < -math.pi) error += 2 * math.pi;
    final lookahead = math.max(
      1.0,
      math.sqrt(
        math.pow(target.x - car.position.x, 2) +
            math.pow(target.y - car.position.y, 2),
      ),
    );
    final steering =
        (2 *
                math.sin(error) *
                car.speed /
                lookahead /
                RaceConfig.academy.turnRate)
            .clamp(-1.0, 1.0);
    return CarInput(throttle: throttle, steering: steering.toDouble());
  }

  RaceSimulation? _simulation;

  void bind(RaceSimulation simulation) => _simulation = simulation;
}
