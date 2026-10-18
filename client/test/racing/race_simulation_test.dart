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
      expect(red.steering, -1);
      expect(red.horn, isTrue);
      expect(blue.throttle, 1);
      expect(blue.steering, 0);
      expect(blue.horn, isFalse);

      input.handleKey(LogicalKeyboardKey.keyS, true);
      expect(input.inputFor(PlayerId.red).throttle, 0);
      expect(input.inputFor(PlayerId.red).brake, 1);
      input.clear();
      expect(input.inputFor(PlayerId.red).brake, 0);
      expect(input.inputFor(PlayerId.blue).throttle, 0);
    });
  });

  group('RaceSimulation', () {
    test('accelerates, naturally slows, brakes, and steers', () {
      final simulation = RaceSimulation();
      addTearDown(simulation.dispose);
      final input = _TestInput();
      simulation.setRunning(true);
      input.values[PlayerId.red] = const CarInput(throttle: 1, steering: 1);
      _advance(simulation, input, 1);
      final topSpeed = simulation.red.speed;
      final heading = simulation.red.heading;
      expect(topSpeed, greaterThan(100));
      expect(topSpeed, lessThanOrEqualTo(simulation.config.maxSpeed));
      expect(heading, greaterThan(0.5));

      input.values[PlayerId.red] = const CarInput();
      _advance(simulation, input, 0.5);
      final coastingSpeed = simulation.red.speed;
      expect(coastingSpeed, lessThan(topSpeed));

      input.values[PlayerId.red] = const CarInput(brake: 1);
      _advance(simulation, input, 0.25);
      expect(simulation.red.speed, lessThan(coastingSpeed));
    });

    test('emits one vehicle impact for a continuous contact', () {
      final simulation = RaceSimulation();
      addTearDown(simulation.dispose);
      final events = <CollisionEvent>[];
      final subscription = simulation.collisionEvents.listen(events.add);
      addTearDown(subscription.cancel);
      simulation.red.position.setValues(230, 180);
      simulation.blue.position.setValues(260, 180);
      simulation.red.velocity.setValues(100, 0);
      simulation.blue.velocity.setValues(-100, 0);
      final input = _TestInput()..values.clear();
      simulation.setRunning(true);

      simulation.update(simulation.config.fixedStep, input);
      expect(events, hasLength(1));
      expect(events.single.type, CollisionType.vehicle);
      expect(events.single.players, [PlayerId.red, PlayerId.blue]);
      expect(events.single.intensity, inInclusiveRange(0, 1));

      // Keep the cars at the contact point; repeated resolution is not a new hit.
      simulation.red.velocity.setZero();
      simulation.blue.velocity.setZero();
      _advance(simulation, input, 0.1);
      expect(events, hasLength(1));
    });

    test('emits one wall impact and permits another after separation', () {
      final simulation = RaceSimulation();
      addTearDown(simulation.dispose);
      final events = <CollisionEvent>[];
      final subscription = simulation.collisionEvents.listen(events.add);
      addTearDown(subscription.cancel);
      simulation.red.position.setValues(120, 81);
      simulation.red.velocity.setValues(0, -100);
      final input = _TestInput()..values.clear();
      simulation.setRunning(true);

      simulation.update(simulation.config.fixedStep, input);
      expect(events, hasLength(1));
      expect(events.single.type, CollisionType.wall);
      expect(events.single.players, [PlayerId.red]);
      expect(events.single.intensity, inInclusiveRange(0, 1));

      simulation.red.velocity.setZero();
      _advance(simulation, input, 0.08);
      expect(events, hasLength(1));

      simulation.red.position.setValues(120, 100);
      simulation.red.velocity.setValues(0, -100);
      simulation.red.heading = -1.5707963267948966;
      _advance(simulation, input, 0.3);
      expect(events, hasLength(2));
    });

    test('reset returns both cars to their starting state and pauses', () {
      final simulation = RaceSimulation();
      addTearDown(simulation.dispose);
      simulation.red.position.setValues(450, 450);
      simulation.blue.velocity.setValues(30, 0);
      simulation.setRunning(true);

      simulation.reset();

      expect(simulation.isRunning, isFalse);
      expect(simulation.red.position.x, 150);
      expect(simulation.red.position.y, 112);
      expect(simulation.red.speed, 0);
      expect(simulation.blue.position.y, 166);
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
