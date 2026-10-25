import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/simulation/race_simulation.dart';

void main() {
  group('KeyboardInputSource', () {
    test('maps both players independently and exposes reserved horn input', () {
      final input = KeyboardInputSource();
      input.handleKey(LogicalKeyboardKey.keyW, true);
      input.handleKey(LogicalKeyboardKey.keyA, true);
      input.handleKey(LogicalKeyboardKey.keyQ, true);
      input.handleKey(LogicalKeyboardKey.arrowUp, true);

      final red = input.inputFor(PlayerId.red);
      final blue = input.inputFor(PlayerId.blue);
      expect(red.throttle, 1);
      expect(red.reverse, 0);
      expect(red.steering, -1);
      expect(red.horn, isTrue);
      expect(blue.throttle, 1);
      expect(blue.steering, 0);
      expect(blue.horn, isFalse);

      input.handleKey(LogicalKeyboardKey.keyS, true);
      expect(input.inputFor(PlayerId.red).reverse, 1);
      expect(input.inputFor(PlayerId.red).brake, 0);
      input.clear();
      expect(input.inputFor(PlayerId.red).reverse, 0);
      input.handleKey(LogicalKeyboardKey.arrowDown, true);
      expect(input.inputFor(PlayerId.blue).reverse, 1);
      input.clear();
      expect(input.inputFor(PlayerId.blue).throttle, 0);
    });
  });

  group('RaceSimulation', () {
    test('moves directly at fixed speed, stops on release, and steers', () {
      final simulation = RaceSimulation();
      addTearDown(simulation.dispose);
      final input = _TestInput();
      simulation.setRunning(true);
      input.values[PlayerId.red] = const CarInput(throttle: 1, steering: 1);
      _advance(simulation, input, 0.25);
      final heading = simulation.red.heading;
      expect(simulation.red.speed, simulation.config.maxSpeed);
      expect(heading, closeTo(0.6, 0.02));
      expect(
        simulation.red.velocity.x,
        closeTo(math.cos(heading) * simulation.config.maxSpeed, 0.001),
      );
      expect(
        simulation.red.velocity.y,
        closeTo(math.sin(heading) * simulation.config.maxSpeed, 0.001),
      );

      input.values[PlayerId.red] = const CarInput();
      _advance(simulation, input, 1 / 120);
      expect(simulation.red.speed, 0);
      expect(simulation.red.heading, heading);
    });

    test('direction changes pass through zero over 150 milliseconds', () {
      final simulation = RaceSimulation();
      addTearDown(simulation.dispose);
      final input = _TestInput();
      simulation.setRunning(true);

      input.values[PlayerId.red] = const CarInput(throttle: 1);
      _advance(simulation, input, 1 / 120);
      expect(simulation.red.driveSpeed, simulation.config.maxSpeed);

      input.values[PlayerId.red] = const CarInput(reverse: 1);
      _advance(simulation, input, 0.075);
      expect(
        simulation.red.driveSpeed,
        closeTo(simulation.config.maxSpeed / 2, 1),
      );
      _advance(simulation, input, 0.075);
      expect(
        simulation.red.driveSpeed,
        closeTo(-simulation.config.maxReverseSpeed, 1),
      );
      expect(
        simulation.red.speed,
        lessThanOrEqualTo(simulation.config.maxReverseSpeed),
      );
    });

    test(
      'releasing during a direction change stops and cancels the switch',
      () {
        final simulation = RaceSimulation();
        addTearDown(simulation.dispose);
        final input = _TestInput();
        simulation.setRunning(true);
        input.values[PlayerId.red] = const CarInput(throttle: 1);
        _advance(simulation, input, 1 / 120);
        input.values[PlayerId.red] = const CarInput(reverse: 1);
        _advance(simulation, input, 0.075);
        expect(
          simulation.red.driveSpeed,
          closeTo(simulation.config.maxSpeed / 2, 1),
        );

        input.values[PlayerId.red] = const CarInput();
        _advance(simulation, input, 1 / 120);
        expect(simulation.red.speed, 0);

        input.values[PlayerId.red] = const CarInput(reverse: 1);
        _advance(simulation, input, 1 / 120);
        expect(simulation.red.driveSpeed, -simulation.config.maxReverseSpeed);
      },
    );

    test('reverse wins if both direction inputs are held', () {
      final simulation = RaceSimulation();
      addTearDown(simulation.dispose);
      final input = _TestInput();
      simulation.setRunning(true);
      input.values[PlayerId.red] = const CarInput(throttle: 1, reverse: 1);
      _advance(simulation, input, 1 / 120);
      expect(simulation.red.driveSpeed, -simulation.config.maxReverseSpeed);
    });

    test('emits one vehicle impact for a continuous contact', () {
      final simulation = RaceSimulation();
      addTearDown(simulation.dispose);
      final events = <CollisionEvent>[];
      final subscription = simulation.collisionEvents.listen(events.add);
      addTearDown(subscription.cancel);
      simulation.red.position.setValues(230, 180);
      simulation.blue.position.setValues(260, 180);
      simulation.red.heading = 0;
      simulation.blue.heading = math.pi;
      final input = _TestInput()..values.clear();
      input.values[PlayerId.red] = const CarInput(throttle: 1);
      input.values[PlayerId.blue] = const CarInput(throttle: 1);
      simulation.setRunning(true);

      simulation.update(simulation.config.fixedStep, input);
      expect(events, hasLength(1));
      expect(events.single.type, CollisionType.vehicle);
      expect(events.single.players, [PlayerId.red, PlayerId.blue]);
      expect(events.single.intensity, inInclusiveRange(0, 1));

      expect(simulation.red.speed, 0);
      expect(simulation.blue.speed, 0);

      // Keep the cars at the contact point; repeated resolution is not a new hit.
      input.values.clear();
      _advance(simulation, input, 0.1);
      expect(events, hasLength(1));
    });

    test('an unfinished car passes through a finished car without impact', () {
      final simulation = RaceSimulation();
      addTearDown(simulation.dispose);
      final events = <CollisionEvent>[];
      final subscription = simulation.collisionEvents.listen(events.add);
      addTearDown(subscription.cancel);
      simulation.red.position.setValues(200, 180);
      simulation.red.driveSpeed = 80;
      simulation.red.syncVelocity();
      simulation.blue.position.setValues(233, 180);
      simulation.blue.heading = math.pi;
      simulation.finishPlayer(PlayerId.red);
      final input = _TestInput()..values.clear();
      input.values[PlayerId.blue] = const CarInput(throttle: 1);
      simulation.setRunning(true);

      _advance(simulation, input, 0.25);

      expect(simulation.red.position.x, 200);
      expect(simulation.red.speed, 0);
      expect(simulation.blue.position.x, lessThan(simulation.red.position.x));
      expect(simulation.blue.speed, simulation.config.maxSpeed);
      expect(events, isEmpty);
    });

    test('emits one wall impact and permits another after separation', () {
      final simulation = RaceSimulation();
      addTearDown(simulation.dispose);
      final events = <CollisionEvent>[];
      final subscription = simulation.collisionEvents.listen(events.add);
      addTearDown(subscription.cancel);
      simulation.red.position.setValues(120, 81);
      simulation.red.heading = -math.pi / 2;
      final input = _TestInput()..values.clear();
      input.values[PlayerId.red] = const CarInput(throttle: 1);
      simulation.setRunning(true);

      simulation.update(simulation.config.fixedStep, input);
      expect(events, hasLength(1));
      expect(events.single.type, CollisionType.wall);
      expect(events.single.players, [PlayerId.red]);
      expect(events.single.intensity, inInclusiveRange(0, 1));
      expect(simulation.red.speed, 0);

      input.values.clear();
      _advance(simulation, input, 0.08);
      expect(events, hasLength(1));

      simulation.red.position.setValues(120, 100);
      simulation.red.heading = -1.5707963267948966;
      input.values[PlayerId.red] = const CarInput(throttle: 1);
      _advance(simulation, input, 0.3);
      expect(events, hasLength(2));
    });

    test('reset returns both cars to their starting state and pauses', () {
      final simulation = RaceSimulation();
      addTearDown(simulation.dispose);
      simulation.red.position.setValues(450, 450);
      simulation.blue.driveSpeed = 30;
      simulation.blue.syncVelocity();
      simulation.setRunning(true);

      simulation.reset();

      expect(simulation.isRunning, isFalse);
      expect(simulation.red.position.x, 150);
      expect(simulation.red.position.y, 112);
      expect(simulation.red.speed, 0);
      expect(simulation.blue.position.y, 166);
      expect(simulation.blue.speed, 0);
    });

    test('pausing stops both cars immediately', () {
      final simulation = RaceSimulation();
      addTearDown(simulation.dispose);
      simulation.red.driveSpeed = 100;
      simulation.blue.driveSpeed = -80;
      simulation.red.syncVelocity();
      simulation.blue.syncVelocity();

      simulation.setRunning(false);

      expect(simulation.red.speed, 0);
      expect(simulation.blue.speed, 0);
    });
  });
}

void _advance(RaceSimulation simulation, _TestInput input, double elapsed) {
  const frame = 1 / 120;
  var remaining = elapsed;
  while (remaining > 0) {
    final next = remaining < frame ? remaining : frame;
    simulation.update(next, input);
    remaining -= next;
  }
}

class _TestInput implements InputSource {
  final Map<PlayerId, CarInput> values = {
    PlayerId.red: const CarInput(),
    PlayerId.blue: const CarInput(),
  };

  @override
  CarInput inputFor(PlayerId player) => values[player] ?? const CarInput();
}
