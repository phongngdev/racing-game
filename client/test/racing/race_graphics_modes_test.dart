import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/apex_racing_game.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/lap/lap_race_track.dart';
import 'package:racing_client/racing/simulation/race_simulation.dart';
import 'package:racing_client/racing/sprint/sprint_graphics_assets.dart';
import 'package:racing_client/racing/tracks/sprint_track_generator.dart';
import 'package:racing_client/racing/tracks/track_definition.dart';

void main() {
  testWidgets('Random Sprint and Lap fall back if a car sprite fails', (
    tester,
  ) async {
    final randomTrack = const SprintTrackGenerator()
        .generate('graphics-fallback-7')
        .track;
    final cases = <({TrackDefinition? sprintTrack, bool lap})>[
      (sprintTrack: randomTrack, lap: false),
      (sprintTrack: null, lap: true),
    ];

    for (final testCase in cases) {
      final assets = SprintGraphicsAssets(
        loadSprite: (assetPath) async {
          if (assetPath == 'racing/vehicles/car_blue_1.png') {
            throw StateError('Simulated vehicle image failure.');
          }
          return _solidTestSprite();
        },
      );
      final simulation = RaceSimulation(track: testCase.sprintTrack);
      final snapshot = ValueNotifier(const RaceSnapshot());
      final game = ApexRacingGame(
        simulation: simulation,
        inputSource: KeyboardInputSource(),
        snapshot: snapshot,
        onKeyboardEvent: (_) => KeyEventResult.ignored,
        sprintTrack: testCase.sprintTrack,
        lapTrack: testCase.lap ? LapRaceTrack.standard : null,
        sprintGraphicsAssets: assets,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 900,
            height: 600,
            child: GameWidget(game: game),
          ),
        ),
      );
      await tester.runAsync(() async {
        await game.loaded.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw StateError('Timed out waiting for game.loaded'),
        );
        await game.ready().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw StateError('Timed out waiting for game.ready'),
        );
        await game.graphicsPreload.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw StateError('Timed out waiting for graphics'),
        );
      });
      game.pauseEngine();
      await tester.pump();

      expect(game.supportsGraphicsSelection, isTrue);
      expect(game.supportsKenneyGraphics, isFalse);
      expect(game.graphicsStyle, SprintGraphicsStyle.legacy);
      expect(game.setGraphicsStyle(SprintGraphicsStyle.kenney), isFalse);
      expect(assets['vehicles/car_red_1.png'], isNotNull);
      expect(assets['vehicles/car_blue_1.png'], isNull);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      simulation.dispose();
      snapshot.dispose();
    }
  });
}

Future<Sprite> _solidTestSprite() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 4, 4),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  return Sprite(await recorder.endRecording().toImage(4, 4));
}
