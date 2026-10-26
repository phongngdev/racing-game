import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/graphics/race_scenery_component.dart';
import 'package:racing_client/racing/lap/lap_race_track.dart';
import 'package:racing_client/racing/simulation/race_simulation.dart';
import 'package:racing_client/racing/sprint/sprint_graphics_assets.dart';
import 'package:racing_client/racing/tracks/sprint_track_generator.dart';
import 'package:racing_client/racing/tracks/track_definition.dart';

void main() {
  test(
    'Random Sprint scenery is deterministic and leaves track geometry clear',
    () {
      const generator = SprintTrackGenerator();
      final trackA = generator.generate('scenery-stability-7').track;
      final trackB = generator.generate('scenery-stability-7').track;
      final fingerprintBefore = sprintGeometryFingerprint(trackA);
      final sceneA = RaceSceneryComponent.sprint(
        trackA,
        SprintGraphicsAssets(),
      );
      final sceneB = RaceSceneryComponent.sprint(
        trackB,
        SprintGraphicsAssets(),
      );

      expect(sceneA.placements.length, lessThanOrEqualTo(28));
      expect(sceneA.placements, isNotEmpty);
      expect(
        sceneA.placements.map(_placementSignature),
        sceneB.placements.map(_placementSignature),
      );
      expect(sprintGeometryFingerprint(trackA), fingerprintBefore);
      for (final placement in sceneA.placements) {
        expect(
          trackA.worldBounds.contains(placement.cullBounds.topLeft) &&
              trackA.worldBounds.contains(placement.cullBounds.bottomRight),
          isTrue,
        );
        expect(
          trackA.roadRects.any(
            (road) => road.inflate(22).overlaps(placement.cullBounds),
          ),
          isFalse,
        );
        expect(
          _sprintGates(trackA).any(
            (gate) =>
                _gateBounds(gate).inflate(22).overlaps(placement.cullBounds),
          ),
          isFalse,
        );
      }
      _expectSeparated(sceneA.placements, 12);
    },
  );

  test('Lap scenery stays within the island and clear of all gates', () {
    final scene = RaceSceneryComponent.lap(SprintGraphicsAssets());
    final safeIsland = RaceTrackLayout.island.deflate(26);

    expect(scene.placements.length, lessThanOrEqualTo(16));
    expect(scene.placements, isNotEmpty);
    for (final placement in scene.placements) {
      expect(
        safeIsland.contains(placement.cullBounds.topLeft) &&
            safeIsland.contains(placement.cullBounds.bottomRight),
        isTrue,
      );
      expect(
        _lapGates.any(
          (gate) =>
              _gateBounds(gate).inflate(22).overlaps(placement.cullBounds),
        ),
        isFalse,
      );
    }
    _expectSeparated(scene.placements, 8);
  });

  test('culling checks full sprite bounds against each camera viewport', () {
    final scene = RaceSceneryComponent.lap(SprintGraphicsAssets());
    final placement = scene.placements.first;
    final visibleEdge = Rect.fromLTWH(
      placement.cullBounds.right - 1,
      placement.cullBounds.top,
      30,
      placement.cullBounds.height,
    );
    final outside = Rect.fromLTWH(
      placement.cullBounds.right + 1,
      placement.cullBounds.top,
      30,
      placement.cullBounds.height,
    );

    expect(scene.isVisibleIn(placement, visibleEdge), isTrue);
    expect(scene.isVisibleIn(placement, outside), isFalse);
    expect(
      scene.isVisibleIn(placement, outside),
      isFalse,
      reason: 'Each camera supplies its own visible world rectangle.',
    );
  });
}

Object _placementSignature(RaceSceneryPlacement placement) =>
    (placement.assetKey, placement.visualBounds, placement.cullBounds);

void _expectSeparated(List<RaceSceneryPlacement> placements, double gap) {
  for (var i = 0; i < placements.length; i++) {
    for (var j = i + 1; j < placements.length; j++) {
      expect(
        placements[i].cullBounds
            .inflate(gap)
            .overlaps(placements[j].cullBounds),
        isFalse,
      );
    }
  }
}

Iterable<TrackGate> _sprintGates(TrackDefinition track) sync* {
  yield track.start;
  yield* track.checkpoints;
  yield track.finish;
}

final _lapGates = [
  LapRaceTrack.standard.finish,
  ...LapRaceTrack.standard.checkpoints,
];

Rect _gateBounds(TrackGate gate) => Rect.fromPoints(
  Offset(gate.start.x, gate.start.y),
  Offset(gate.end.x, gate.end.y),
);
