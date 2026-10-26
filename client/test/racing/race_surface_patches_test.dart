import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/graphics/race_surface_patches.dart';
import 'package:racing_client/racing/graphics/race_surface_textures.dart';
import 'package:racing_client/racing/lap/lap_race_track.dart';
import 'package:racing_client/racing/simulation/race_simulation.dart';
import 'package:racing_client/racing/sprint/sprint_graphics_assets.dart';
import 'package:racing_client/racing/tracks/sprint_track_generator.dart';
import 'package:racing_client/racing/tracks/track_definition.dart';

void main() {
  test(
    'Sprint dirt patches are deterministic and clear the road and gates',
    () {
      final track = FixedTracks.sprint;
      final fingerprint = sprintTrackFingerprint(track);
      final first = RaceSurfacePatches.sprint(track);
      final second = RaceSurfacePatches.sprint(track);

      expect(first.length, greaterThanOrEqualTo(2));
      expect(_patchSignatures(first), _patchSignatures(second));
      expect(sprintTrackFingerprint(track), fingerprint);
      for (final patch in first) {
        expect(_contains(track.worldBounds, patch.bounds), isTrue);
        expect(
          track.roadRects.any(
            (road) => road.inflate(22).overlaps(patch.bounds),
          ),
          isFalse,
        );
        expect(
          _sprintGates(
            track,
          ).any((gate) => _gateBounds(gate).inflate(22).overlaps(patch.bounds)),
          isFalse,
        );
      }
    },
  );

  test('Random Sprint dirt placement follows deterministic track geometry', () {
    const generator = SprintTrackGenerator();
    final trackA = generator.generate('surface-layout-75').track;
    final trackB = generator.generate('surface-layout-75').track;
    final patchesA = RaceSurfacePatches.sprint(trackA);
    final patchesB = RaceSurfacePatches.sprint(trackB);

    expect(patchesA, isNotEmpty);
    expect(_patchSignatures(patchesA), _patchSignatures(patchesB));
    for (final patch in patchesA) {
      expect(
        trackA.roadRects.any((road) => road.inflate(22).overlaps(patch.bounds)),
        isFalse,
      );
    }
  });

  test('Lap Race dirt patches stay inside the infield and clear all gates', () {
    final patches = RaceSurfacePatches.lap();
    final island = RaceTrackLayout.island.deflate(8);
    final gates = <TrackGate>[
      LapRaceTrack.standard.finish,
      ...LapRaceTrack.standard.checkpoints,
    ];

    expect(patches.length, greaterThanOrEqualTo(2));
    for (final patch in patches) {
      expect(_contains(island, patch.bounds), isTrue);
      expect(
        gates.any(
          (gate) => _gateBounds(gate).inflate(22).overlaps(patch.bounds),
        ),
        isFalse,
      );
    }
  });

  testWidgets(
    'surface textures prepare once and missing images use Canvas fallback',
    (tester) async {
      for (final failSurfaces in [false, true]) {
        final decoded = <Image>[];
        final assets = SprintGraphicsAssets(
          loadSprite: (assetPath) async {
            if (failSurfaces && assetPath.contains('/surfaces/')) {
              throw StateError('Simulated optional surface failure.');
            }
            final recorder = PictureRecorder();
            Canvas(recorder).drawRect(
              const Rect.fromLTWH(0, 0, 4, 4),
              Paint()..color = const Color(0xFFFFFFFF),
            );
            final image = await recorder.endRecording().toImage(4, 4);
            decoded.add(image);
            return Sprite(image);
          },
        );
        final textures = RaceSurfaceTextures();
        late Image preview;

        await tester.runAsync(() async {
          await assets.preload();
          await textures.prepare(assets);
          final recorder = PictureRecorder();
          final canvas = Canvas(recorder);
          textures.drawGrass(
            canvas,
            const Rect.fromLTWH(0, 0, 64, 64),
            const Color(0xFF24452F),
          );
          textures.drawAsphalt(
            canvas,
            Path()..addRect(const Rect.fromLTWH(8, 8, 48, 48)),
            const Color(0xFF34383C),
          );
          preview = await recorder.endRecording().toImage(64, 64);
        });

        expect(textures.hasGrassTexture, !failSurfaces);
        expect(textures.hasDirtTexture, !failSurfaces);
        expect(textures.hasAsphaltTexture, !failSurfaces);
        expect(preview.width, 64);

        textures.dispose();
        preview.dispose();
        for (final image in decoded) {
          image.dispose();
        }
      }
    },
  );
}

List<(double, double, double, double)> _patchSignatures(
  List<RaceSurfacePatch> patches,
) => [
  for (final patch in patches)
    (
      patch.bounds.left,
      patch.bounds.top,
      patch.bounds.width,
      patch.bounds.height,
    ),
];

List<TrackGate> _sprintGates(TrackDefinition track) => [
  track.start,
  ...track.checkpoints,
  track.finish,
];

Rect _gateBounds(TrackGate gate) => Rect.fromPoints(
  Offset(gate.start.x, gate.start.y),
  Offset(gate.end.x, gate.end.y),
);

bool _contains(Rect outer, Rect inner) =>
    outer.contains(inner.topLeft) && outer.contains(inner.bottomRight);
