import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/academy/academy_game_page.dart';
import 'package:racing_client/racing/academy/academy_track.dart';
import 'package:racing_client/racing/graphics/race_surface_textures.dart';
import 'package:racing_client/racing/tracks/track_geometry.dart';

void main() {
  test(
    'road is one closed corridor containing both bends and straight aprons',
    () {
      final track = AcademyTrack.sBend();
      final path = track.roadPath();
      final contours = path.computeMetrics().toList();
      expect(contours, hasLength(1));
      expect(contours.single.isClosed, isTrue);
      for (
        var station = 10.0;
        station < track.totalLength - 10;
        station += 10
      ) {
        final gate = track.gateAt(station);
        for (final fraction in [.1, .5, .9]) {
          final point = gate.$1.lerpTo(gate.$2, fraction);
          expect(
            path.contains(Offset(point.x, point.y)),
            isTrue,
            reason:
                'asphalt must fill the full corridor at $station / $fraction',
          );
        }
      }
      expect(path.contains(const Offset(360, 465)), isFalse);
    },
  );

  test(
    'wheel sensor reaches the same painted boundary on both circular bends',
    () {
      final track = AcademyTrack.sBend();
      for (final fraction in [.35, .6]) {
        final station = track.totalLength * fraction;
        final point = track.pointAt(station);
        final direction = track.directionAt(station);
        final heading = math.atan2(direction.y, direction.x);
        expect(track.wheelsTouchingBoundary(point, heading), isEmpty);
        final lateral = track.halfWidth - AcademyTrack.wheelOffsetLateral;
        final touchingPose = TrackPoint(
          point.x - direction.y * lateral,
          point.y + direction.x * lateral,
        );
        expect(track.isOnRoad(touchingPose), isTrue);
        expect(track.wheelsTouchingBoundary(touchingPose, heading), isNotEmpty);
      }
    },
  );

  testWidgets(
    'asphalt fills the lane and grass remains outside; debug gates are off',
    (tester) async {
      final track = AcademyTrack.sBend();
      final textures = RaceSurfaceTextures();
      addTearDown(textures.dispose);
      final component = AcademyTrackComponent(track, textures);
      final recorder = ui.PictureRecorder();
      component.render(Canvas(recorder));
      final picture = recorder.endRecording();
      final image = await picture.toImage(1000, 700);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      Color pixel(TrackPoint point) {
        final offset = (point.y.round() * 1000 + point.x.round()) * 4;
        return Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      }

      for (final fraction in [.1, .3, .43, .57, .7, .9]) {
        final gate = track.gateAt(track.totalLength * fraction);
        for (final lateral in [.25, .75]) {
          expect(
            pixel(gate.$1.lerpTo(gate.$2, lateral)),
            const Color(0xFF34383C),
          );
        }
      }
      expect(pixel(const TrackPoint(360, 465)), const Color(0xFF24452F));
      expect(pixel(const TrackPoint(50, 50)), const Color(0xFF24452F));
      image.dispose();
      picture.dispose();
    },
  );

  testWidgets(
    'back to Academy is available while driving and stops simulation',
    (tester) async {
      var exited = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AcademyGamePage(onReturnToAcademy: () => exited = true),
        ),
      );
      final game = tester
          .widget<GameWidget<AcademyFlameGame>>(
            find.byType(GameWidget<AcademyFlameGame>),
          )
          .game!;
      await tester.runAsync(() async {
        await game.loaded;
        await game.ready();
      });
      game.session.start();
      await tester.pump();
      await tester.tap(find.text('Về Academy'));
      expect(exited, isTrue);
      expect(game.simulation.isRunning, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
