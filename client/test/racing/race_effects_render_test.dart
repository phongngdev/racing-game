import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/apex_racing_game.dart';
import 'package:racing_client/racing/graphics/race_effects_component.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/simulation/race_simulation.dart';
import 'package:racing_client/racing/sprint/sprint_graphics_assets.dart';
import 'package:racing_client/racing/tracks/track_definition.dart';

void main() {
  testWidgets(
    'Kenney effects render visible pixels through both Sprint cameras',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final simulation = RaceSimulation(track: FixedTracks.sprint);
      final input = _RenderInput();
      final snapshot = ValueNotifier(const RaceSnapshot());
      final spriteRecorder = ui.PictureRecorder();
      Canvas(spriteRecorder).drawRect(
        const Rect.fromLTWH(0, 0, 4, 4),
        Paint()..color = const Color(0xFF557766),
      );
      final spritePicture = spriteRecorder.endRecording();
      final sprite = Sprite(spritePicture.toImageSync(4, 4));
      spritePicture.dispose();
      final game = ApexRacingGame(
        simulation: simulation,
        inputSource: input,
        snapshot: snapshot,
        onKeyboardEvent: (_) => KeyEventResult.ignored,
        sprintTrack: FixedTracks.sprint,
        sprintGraphicsAssets: SprintGraphicsAssets(
          loadSprite: (_) async => sprite,
        ),
      );
      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      await tester.runAsync(() async {
        await game.loaded.timeout(const Duration(seconds: 5));
        await game.ready().timeout(const Duration(seconds: 5));
      });
      await tester.pump();
      await tester.runAsync(
        () => game.graphicsPreload.timeout(const Duration(seconds: 5)),
      );
      game.pauseEngine();
      await tester.pump();
      final effects = game.world.children
          .whereType<RaceEffectsComponent>()
          .single;
      expect(effects.isMounted, isTrue);
      expect(effects.enabled, isTrue);
      expect(effects.overlay.parent, same(game.world));
      expect(
        effects.priority,
        lessThan(game.world.children.whereType<CarComponent>().first.priority),
      );
      expect(
        effects.overlay.priority,
        greaterThan(
          game.world.children.whereType<CarComponent>().first.priority,
        ),
      );

      simulation.red
        ..position.setValues(500, 1800)
        ..heading = 0
        ..driveSpeed = 200
        ..syncVelocity();
      simulation.blue
        ..position.setValues(530, 1800)
        ..heading = math.pi
        ..driveSpeed = 200
        ..syncVelocity();
      simulation.setRunning(true);
      game.update(simulation.config.fixedStep);
      final cameras = game.children.whereType<CameraComponent>().toList();
      expect(cameras, hasLength(2));
      for (final camera in cameras) {
        camera.viewfinder.position = Vector2(515, 1800);
      }
      expect(effects.flashCount, 1);
      final particles = effects.impactCount;
      late Uint8List withEffects, withoutEffects;
      await tester.runAsync(() async {
        withEffects = await _render(game).timeout(const Duration(seconds: 5));
        expect(
          effects.impactCount,
          particles,
        ); // Rendering two cameras never spawns/ages particles.
        effects.enabled = false;
        withoutEffects = await _render(game)
            .timeout(const Duration(seconds: 5));
      });
      final changed = [0, 0];
      for (var index = 0; index < withEffects.length; index += 4) {
        if (withEffects[index] != withoutEffects[index] ||
            withEffects[index + 1] != withoutEffects[index + 1] ||
            withEffects[index + 2] != withoutEffects[index + 2]) {
          changed[(index ~/ 4 % 1400) < 700 ? 0 : 1]++;
        }
      }
      expect(changed[0], greaterThan(100));
      expect(changed[1], greaterThan(100));
      game.setGraphicsStyle(SprintGraphicsStyle.kenney);
      expect(effects.enabled, isTrue);
      game.setGraphicsStyle(SprintGraphicsStyle.legacy);
      expect(effects.enabled, isFalse);
      expect(effects.impactCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      simulation.dispose();
      snapshot.dispose();
      sprite.image.dispose();
    },
  );
}

Future<Uint8List> _render(ApexRacingGame game) async {
  final recorder = ui.PictureRecorder();
  game.render(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = picture.toImageSync(1400, 900);
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return pixels!.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes);
}

class _RenderInput implements InputSource {
  @override
  CarInput inputFor(PlayerId player) => const CarInput(throttle: 1);
}
