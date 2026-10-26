import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/apex_racing_game.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/simulation/race_simulation.dart';
import 'package:racing_client/racing/sprint/sprint_camera.dart';
import 'package:racing_client/racing/sprint/sprint_graphics_assets.dart';
import 'package:racing_client/racing/sprint/sprint_race_session.dart';
import 'package:racing_client/racing/tracks/track_definition.dart';
import 'package:racing_client/racing/tracks/sprint_track_generator.dart';

void main() {
  testWidgets('failed car preload safely keeps Fixed Sprint on Legacy', (
    tester,
  ) async {
    final assets = SprintGraphicsAssets(
      loadSprite: (assetPath) async {
        if (assetPath == 'racing/vehicles/car_red_1.png' ||
            assetPath == 'racing/scenery/tree_large.png') {
          throw StateError('Simulated optional asset failure.');
        }
        return _solidTestSprite();
      },
    );
    final track = FixedTracks.sprint;
    final simulation = RaceSimulation(track: track);
    final snapshot = ValueNotifier(const RaceSnapshot());
    final game = ApexRacingGame(
      simulation: simulation,
      inputSource: KeyboardInputSource(),
      snapshot: snapshot,
      onKeyboardEvent: (_) => KeyEventResult.ignored,
      sprintTrack: track,
      sprintGraphicsAssets: assets,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(width: 900, height: 600, child: GameWidget(game: game)),
      ),
    );
    await tester.runAsync(() async {
      await game.loaded.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError('Timed out waiting for game.loaded'),
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
    await tester.pump();
    game.pauseEngine();

    expect(game.supportsKenneyGraphics, isFalse);
    expect(game.graphicsStyle, SprintGraphicsStyle.legacy);
    expect(game.setGraphicsStyle(SprintGraphicsStyle.kenney), isFalse);
    expect(assets['vehicles/car_red_1.png'], isNull);
    expect(assets['vehicles/car_blue_1.png'], isNotNull);
    expect(assets['scenery/tree_large.png'], isNull);
    expect(assets['scenery/rock1.png'], isNotNull);
    expect(
      game.world.children.whereType<CarComponent>().every(
        (component) => component.style == SprintGraphicsStyle.legacy,
      ),
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    simulation.dispose();
    snapshot.dispose();
  });

  testWidgets('failed scenery image is skipped while Kenney stays active', (
    tester,
  ) async {
    final assets = SprintGraphicsAssets(
      loadSprite: (assetPath) async {
        if (assetPath == 'racing/scenery/tree_large.png') {
          throw StateError('Simulated scenery image failure.');
        }
        return _solidTestSprite();
      },
    );
    final track = FixedTracks.sprint;
    final simulation = RaceSimulation(track: track);
    final snapshot = ValueNotifier(const RaceSnapshot());
    final game = ApexRacingGame(
      simulation: simulation,
      inputSource: KeyboardInputSource(),
      snapshot: snapshot,
      onKeyboardEvent: (_) => KeyEventResult.ignored,
      sprintTrack: track,
      sprintGraphicsAssets: assets,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(width: 900, height: 600, child: GameWidget(game: game)),
      ),
    );
    await tester.runAsync(() async {
      await game.loaded.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError('Timed out waiting for game.loaded'),
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
    await tester.pump();
    game.pauseEngine();

    expect(game.supportsKenneyGraphics, isTrue);
    expect(game.graphicsStyle, SprintGraphicsStyle.kenney);
    expect(assets['scenery/tree_large.png'], isNull);
    expect(assets['scenery/rock1.png'], isNotNull);
    expect(tester.takeException(), isNull);

    final redPosition = simulation.red.position.clone();
    final bluePosition = simulation.blue.position.clone();
    final cameraPosition = game.camera.viewfinder.position.clone();
    final cameraZoom = game.camera.viewfinder.zoom;
    final resetRevision = simulation.resetRevision;
    expect(game.setGraphicsStyle(SprintGraphicsStyle.legacy), isTrue);
    expect(game.setGraphicsStyle(SprintGraphicsStyle.kenney), isTrue);
    expect(simulation.red.position, redPosition);
    expect(simulation.blue.position, bluePosition);
    expect(game.camera.viewfinder.position, cameraPosition);
    expect(game.camera.viewfinder.zoom, cameraZoom);
    expect(simulation.resetRevision, resetRevision);

    await tester.pumpWidget(const SizedBox.shrink());
    simulation.dispose();
    snapshot.dispose();
  });

  test('panes partition landscape and portrait without overlap', () {
    for (final size in const [Size(1200, 600), Size(600, 900), Size(1, 1)]) {
      final panes = sprintViewports(size.width, size.height);
      expect(panes.length, 2);
      expect(panes[0].overlaps(panes[1]), isFalse);
      expect(panes.last.right, size.width);
      expect(panes.last.bottom, size.height);
    }
  });
  test('camera smoothing is bounded, Pause freezes it and reset snaps', () {
    final track = FixedTracks.sprint;
    final sim = RaceSimulation(track: track);
    addTearDown(sim.dispose);
    final rig = SprintCameraRig(track)
      ..resize(600, 600)
      ..snap(sim.red);
    final start = rig.position.clone();
    sim.red.position.setValues(1000, 1000);
    sim.red.snapRenderPose();
    sim.red.driveSpeed = 200;
    sim.red.syncVelocity();
    rig.update(1 / 60, sim.red, running: false, finished: false);
    expect(rig.position, start);
    rig.update(1 / 60, sim.red, running: true, finished: false);
    expect(rig.position.x, greaterThan(start.x));
    expect(rig.position.x, lessThan(sim.red.position.x));
    for (var i = 0; i < 300; i++) {
      rig.update(1 / 60, sim.red, running: true, finished: false);
    }
    expect(rig.position.x, closeTo(1090, 0.1));
    sim.reset();
    rig.snap(sim.red);
    expect(rig.position.x, sim.red.position.x);
    sim.red.position.setValues(0, 0);
    sim.red.snapRenderPose();
    rig.snap(sim.red);
    expect(rig.position.x, 240);
    expect(rig.position.y, 240);
  });
  test(
    'generated track bounds clamp both camera rigs to the generated world',
    () {
      final track = const SprintTrackGenerator()
          .generate('camera-bounds')
          .track;
      final simulation = RaceSimulation(track: track);
      addTearDown(simulation.dispose);
      final rig = SprintCameraRig(track)
        ..resize(600, 360)
        ..snap(simulation.red);
      simulation.red.position.setValues(
        track.worldBounds.right + 1000,
        track.worldBounds.bottom + 1000,
      );
      simulation.red.snapRenderPose();
      rig.snap(simulation.red);
      expect(rig.zoom, greaterThan(0));
      expect(rig.position.x, lessThanOrEqualTo(track.worldBounds.right));
      expect(rig.position.y, lessThanOrEqualTo(track.worldBounds.bottom));
      expect(rig.position.x, greaterThanOrEqualTo(track.worldBounds.left));
      expect(rig.position.y, greaterThanOrEqualTo(track.worldBounds.top));
    },
  );
  testWidgets(
    'two Flame cameras share one world, simulation and fixed-step clock',
    (tester) async {
      final track = FixedTracks.sprint;
      final sim = RaceSimulation(track: track);
      final input = KeyboardInputSource();
      final snapshot = ValueNotifier(const RaceSnapshot());
      final race = SprintRaceSession(
        simulation: sim,
        inputSource: input,
        canStart: () => true,
        controllersAvailable: () => true,
        clearInputs: input.clear,
        setGameRunning: (_) {},
        track: track,
      );
      final game = ApexRacingGame(
        simulation: sim,
        inputSource: input,
        snapshot: snapshot,
        onKeyboardEvent: (_) => KeyEventResult.ignored,
        sprintTrack: track,
        onFrameUpdate: (dt) => race.advanceFrame(dt, publish: false),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 1200,
            height: 600,
            child: GameWidget(game: game),
          ),
        ),
      );
      await tester.runAsync(() async {
        await game.loaded;
        await game.ready();
      });
      await tester.pump();
      game.pauseEngine();
      final cameras = game.children.whereType<CameraComponent>().toList();
      expect(cameras.length, 2);
      expect(identical(cameras[0].world, cameras[1].world), isTrue);
      final redCamera = game.camera;
      final blueCamera = cameras.singleWhere(
        (camera) => !identical(camera, redCamera),
      );
      final panes = sprintViewports(game.canvasSize.x, game.canvasSize.y);
      expect(redCamera.viewport.position.x, panes[0].left);
      expect(redCamera.viewport.position.y, panes[0].top);
      expect(blueCamera.viewport.position.x, panes[1].left);
      expect(blueCamera.viewport.position.y, panes[1].top);
      race.startCountdown();
      race.advanceFrame(3);
      input.handleKey(LogicalKeyboardKey.keyW, true);
      final initial = sim.red.position.x;
      game.update(1 / 120);
      expect(race.raceTime, closeTo(1 / 120, 1e-9));
      expect(sim.red.position.x - initial, closeTo(200 / 120, 1e-4));
      input.clear();
      sim.finishPlayer(PlayerId.red);
      sim.blue.position.setValues(3000, 1800);
      for (var i = 0; i < 120; i++) {
        game.update(1 / 120);
      }
      expect(
        blueCamera.visibleWorldRect.contains(
          Offset(sim.blue.position.x, sim.blue.position.y),
        ),
        isTrue,
        reason:
            'car=${sim.blue.position} camera=${blueCamera.viewfinder.position} '
            'zoom=${blueCamera.viewfinder.zoom} pane=${blueCamera.viewport.size} '
            'visible=${blueCamera.visibleWorldRect} phase=${race.phase}',
      );
      expect(
        redCamera.visibleWorldRect.contains(
          Offset(sim.red.position.x, sim.red.position.y),
        ),
        isTrue,
      );
      final beforePause = race.raceTime;
      race.pause();
      game.update(1);
      expect(race.raceTime, beforePause);
      race.restartFromPause();
      game.update(0);
      expect(
        blueCamera.visibleWorldRect.contains(
          Offset(sim.blue.position.x, sim.blue.position.y),
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      race.dispose();
      sim.dispose();
      snapshot.dispose();
    },
  );
}

Future<Sprite> _solidTestSprite() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 4, 4),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  return Sprite(await recorder.endRecording().toImage(4, 4));
}
