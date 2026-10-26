import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/graphics/race_effects_component.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/simulation/race_simulation.dart';
import 'package:racing_client/racing/tracks/track_definition.dart';

void main() {
  group('RaceEffectsComponent', () {
    test(
      'dust uses outer drivable walls, not joins between road rectangles',
      () {
        final track = FixedTracks.sprint;
        final simulation = RaceSimulation(track: track);
        final input = _EffectInput();
        input.values[PlayerId.red] = const CarInput(throttle: 1);
        final effects = RaceEffectsComponent(
          simulation: simulation,
          inputSource: input,
          drivableWalls: track.walls.map((wall) => wall.$2).toList(),
        );
        addTearDown(() => _dispose(effects, simulation));
        simulation.red
          ..position.setValues(1050, 1800)
          ..driveSpeed = 200
          ..syncVelocity();
        simulation.setRunning(true);

        _advance(simulation, input, 0.2);

        expect(effects.dustCount, 0);
        simulation.setRunning(false);
        simulation.red
          ..position.setValues(1600, 320)
          ..heading = 0
          ..driveSpeed = 200
          ..syncVelocity();
        simulation.setRunning(true);
        _advance(simulation, input, 0.2);

        expect(effects.dustCount, greaterThan(0));
      },
    );

    test(
      'skids appear under hard braking at both rear wheel positions only',
      () {
        final simulation = RaceSimulation();
        final input = _EffectInput();
        final effects = RaceEffectsComponent(
          simulation: simulation,
          inputSource: input,
          drivableWalls: RaceTrackLayout.walls.map((wall) => wall.$2).toList(),
          useKenneyVehicleGeometry: true,
        );
        addTearDown(() => _dispose(effects, simulation));
        simulation.red
          ..position.setValues(200, 300)
          ..heading = math.pi / 2
          ..driveSpeed = 200
          ..syncVelocity();
        simulation.setRunning(true);

        _advance(simulation, input, 0.08);
        expect(effects.skidCount, 0);

        simulation.red
          ..driveSpeed = 200
          ..syncVelocity();
        input.values[PlayerId.red] = const CarInput(brake: 0.8);
        _advance(simulation, input, 0.1);

        expect(effects.skidCount, greaterThanOrEqualTo(2));
        final firstPair = effects.skidSegmentsForTesting.take(2).toList();
        expect(firstPair, hasLength(2));
        expect((firstPair[0].$1 - firstPair[1].$1).distance, closeTo(11, 0.1));

        effects.clear();
        simulation.red
          ..driveSpeed = 200
          ..syncVelocity();
        input.values[PlayerId.red] = const CarInput(reverse: 1);
        _advance(simulation, input, 0.05);
        expect(effects.skidCount, greaterThan(0));
      },
    );

    test(
      'collision effects share one bounded world store, freeze and clear',
      () async {
        final simulation = RaceSimulation(
          redStartPosition: Vector2(230, 180),
          blueStartPosition: Vector2(260, 180),
        );
        final input = _EffectInput();
        final effects = RaceEffectsComponent(
          simulation: simulation,
          inputSource: input,
          drivableWalls: RaceTrackLayout.walls.map((wall) => wall.$2).toList(),
        );
        addTearDown(() => _dispose(effects, simulation));
        simulation.red
          ..heading = 0
          ..driveSpeed = 100
          ..syncVelocity();
        simulation.blue
          ..heading = math.pi
          ..driveSpeed = 100
          ..syncVelocity();
        simulation.setRunning(true);
        simulation.update(simulation.config.fixedStep, input);
        expect(effects.impactCount, greaterThan(0));
        expect(effects.dustCount, 5);
        expect(effects.flashCount, 1);
        expect(effects.skidCount, 4);

        effects
          ..clockAdvances = false
          ..advanceEffects(0.5);
        expect(effects.impactCount, greaterThan(0));

        effects
          ..clockAdvances = true
          ..advanceEffects(0.05)
          ..advanceEffects(0.05)
          ..advanceEffects(0.05)
          ..advanceEffects(0.05)
          ..advanceEffects(0.05)
          ..advanceEffects(0.05)
          ..advanceEffects(0.05)
          ..advanceEffects(0.05);
        expect(effects.impactCount, 0);
        expect(effects.flashCount, 0);

        effects.clockAdvances = false;
        simulation.reset();
        effects.advanceEffects(0);
        expect(effects.skidCount, 0);
        expect(effects.dustCount, 0);
        expect(effects.impactCount, 0);
      },
    );

    test('launch and braking dust are visible away from edges; coasting leaves no skids', () {
      final simulation = RaceSimulation();
      final input = _EffectInput();
      final effects = RaceEffectsComponent(
        simulation: simulation,
        inputSource: input,
        drivableWalls: RaceTrackLayout.walls.map((wall) => wall.$2).toList(),
      );
      addTearDown(() => _dispose(effects, simulation));
      simulation.setRunning(true);
      input.values[PlayerId.red] = const CarInput(throttle: 1);
      _advance(simulation, input, 0.1);
      expect(effects.dustCount, greaterThan(0));
      expect(effects.skidCount, 0);
      effects.clear();
      input.values.clear();
      _advance(simulation, input, 0.05);
      expect(effects.dustCount, greaterThan(0));
      expect(effects.skidCount, 0);
      effects.enabled = false;
      expect(effects.dustCount, 0);
      input.values[PlayerId.red] = const CarInput(throttle: 1);
      _advance(simulation, input, 0.1);
      expect(effects.dustCount, 0);
    });

    test('finish celebration survives pause and clears on rematch reset', () {
      final simulation = RaceSimulation();
      final input = _EffectInput();
      final effects = RaceEffectsComponent(
        simulation: simulation,
        inputSource: input,
        drivableWalls: const [],
      );
      addTearDown(() => _dispose(effects, simulation));
      simulation.finishPlayer(PlayerId.red);
      effects.advanceEffects(0.016);
      expect(effects.finishCount, 1);
      expect(effects.impactCount, 18);
      effects.clockAdvances = false;
      for (var i = 0; i < 30; i++) {
        effects.advanceEffects(0.05);
      }
      expect(effects.finishCount, 1);
      effects.clockAdvances = true;
      effects.advanceEffects(0.05);
      expect(effects.impactCount, 18);
      simulation.reset();
      effects.advanceEffects(0);
      expect(effects.finishCount, 0);
      expect(effects.impactCount, 0);
    });
  });
}

Future<void> _dispose(
  RaceEffectsComponent effects,
  RaceSimulation simulation,
) async {
  effects.onRemove();
  await Future<void>.delayed(Duration.zero);
  simulation.dispose();
}

void _advance(RaceSimulation simulation, _EffectInput input, double elapsed) {
  final step = simulation.config.fixedStep;
  var remaining = elapsed;
  while (remaining > 1e-9) {
    final current = math.min(step, remaining);
    simulation.update(current, input);
    remaining -= current;
  }
}

class _EffectInput implements InputSource {
  final values = <PlayerId, CarInput>{};

  @override
  CarInput inputFor(PlayerId player) => values[player] ?? const CarInput();
}
