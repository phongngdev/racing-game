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
    'Sprint scenery follows the route with deterministic varied clusters',
    () {
      final track = FixedTracks.sprint;
      final fingerprintBefore = sprintGeometryFingerprint(track);
      final sceneA = RaceSceneryComponent.sprint(track, SprintGraphicsAssets());
      final sceneB = RaceSceneryComponent.sprint(track, SprintGraphicsAssets());
      final naturalBudget = (track.stations.last * 24 / 1000).ceil();

      expect(sceneA.placements.length, greaterThan(120));
      expect(
        sceneA.placements
            .where((placement) => placement.area == 'nature')
            .length,
        inInclusiveRange(100, naturalBudget),
      );
      expect(
        sceneA.placements.any((placement) => placement.area == 'startFinish'),
        isTrue,
      );
      expect(
        sceneA.placements.any((placement) => placement.area == 'corner'),
        isTrue,
      );
      expect(
        sceneA.placements.map(_placementSignature),
        sceneB.placements.map(_placementSignature),
      );
      expect(sprintGeometryFingerprint(track), fingerprintBefore);

      for (final placement in sceneA.placements) {
        expect(
          track.worldBounds.contains(placement.cullBounds.topLeft) &&
              track.worldBounds.contains(placement.cullBounds.bottomRight),
          isTrue,
        );
        expect(
          track.roadRects.any(
            (road) => road.inflate(22).overlaps(placement.cullBounds),
          ),
          isFalse,
          reason: placement.assetKey,
        );
        expect(
          _sprintGates(track).any(
            (gate) =>
                _gateBounds(gate).inflate(22).overlaps(placement.cullBounds),
          ),
          isFalse,
          reason: placement.assetKey,
        );
      }
      _expectSeparated(sceneA.placements, 8);

      final sceneryKinds = sceneA.placements
          .map((placement) => placement.assetKey)
          .toSet();
      expect(sceneryKinds.length, greaterThanOrEqualTo(10));
      expect(sceneryKinds, contains('scenery/tribune_full.png'));
      expect(sceneryKinds, contains('scenery/barrier_red_race.png'));
      expect(sceneryKinds, contains('scenery/arrow_yellow.png'));
    },
  );

  test('a longer Random Sprint receives a larger natural scenery budget', () {
    final generator = SprintTrackGenerator();
    final fixedLength = FixedTracks.sprint.stations.last;
    TrackDefinition? longest;
    for (var index = 0; index < 100; index++) {
      final track = generator.generate('environment-density-$index').track;
      if (track.stations.last > (longest?.stations.last ?? fixedLength)) {
        longest = track;
      }
    }
    expect(longest, isNotNull);
    expect(longest!.stations.last, greaterThan(fixedLength));

    final fixed = RaceSceneryComponent.sprint(
      FixedTracks.sprint,
      SprintGraphicsAssets(),
    );
    final random = RaceSceneryComponent.sprint(longest, SprintGraphicsAssets());
    final fixedNatural = fixed.placements
        .where((placement) => placement.area == 'nature')
        .length;
    final randomNatural = random.placements
        .where((placement) => placement.area == 'nature')
        .length;
    expect(
      randomNatural,
      greaterThan(fixedNatural),
      reason: 'The longer route receives a proportionally larger landscape.',
    );
  });

  test('Lap scenery fills the safe island and uses existing wall bands', () {
    final scene = RaceSceneryComponent.lap(SprintGraphicsAssets());
    final safeIsland = RaceTrackLayout.island.deflate(26);
    final safeOuterWalls = <Rect>[
      const Rect.fromLTWH(12, 12, 936, 40),
      const Rect.fromLTWH(12, 588, 936, 40),
      const Rect.fromLTWH(12, 76, 40, 488),
      const Rect.fromLTWH(908, 76, 40, 488),
    ];
    final islandScenery = scene.placements
        .where((placement) => placement.area == 'lapIsland')
        .toList();
    final wallScenery = scene.placements
        .where((placement) => placement.area == 'lapWall')
        .toList();
    expect(islandScenery.length, greaterThan(16));
    expect(islandScenery.length, lessThanOrEqualTo(31));
    expect(wallScenery, isNotEmpty);
    expect(wallScenery.length, lessThanOrEqualTo(38));
    for (final placement in islandScenery) {
      expect(_containsRect(safeIsland, placement.cullBounds), isTrue);
    }
    for (final placement in wallScenery) {
      expect(
        safeOuterWalls.any(
          (region) => _containsRect(region, placement.cullBounds),
        ),
        isTrue,
        reason: placement.assetKey,
      );
    }
    for (final placement in scene.placements) {
      expect(
        _lapGates.any(
          (gate) =>
              _gateBounds(gate).inflate(22).overlaps(placement.cullBounds),
        ),
        isFalse,
        reason: placement.assetKey,
      );
    }
    _expectSeparated(scene.placements, 2);
  });

  test(
    'spatial grid culls each supplied camera viewport by full image bounds',
    () {
      final scene = RaceSceneryComponent.lap(SprintGraphicsAssets());
      final firstPlacement = scene.placements.first;
      final visibleAtEdge = Rect.fromLTRB(
        firstPlacement.cullBounds.right - 1,
        firstPlacement.cullBounds.top,
        firstPlacement.cullBounds.right + 20,
        firstPlacement.cullBounds.bottom,
      );
      final farViewport = const Rect.fromLTWH(800, 500, 40, 40);

      expect(scene.isVisibleIn(firstPlacement, visibleAtEdge), isTrue);
      expect(
        scene.visiblePlacementIndices(visibleAtEdge),
        _bruteVisibleIndices(scene, visibleAtEdge),
      );
      expect(
        scene.visiblePlacementIndices(farViewport),
        _bruteVisibleIndices(scene, farViewport),
      );
      expect(
        scene.visiblePlacementIndices(visibleAtEdge).length,
        lessThan(scene.placements.length),
      );
    },
  );
}

Object _placementSignature(RaceSceneryPlacement placement) => (
  placement.assetKey,
  placement.center,
  placement.spriteWidth,
  placement.spriteHeight,
  placement.rotation,
  placement.area,
  placement.visualBounds,
  placement.cullBounds,
);

void _expectSeparated(List<RaceSceneryPlacement> placements, double gap) {
  for (var i = 0; i < placements.length; i++) {
    for (var j = i + 1; j < placements.length; j++) {
      expect(
        placements[i].cullBounds
            .inflate(gap)
            .overlaps(placements[j].cullBounds),
        isFalse,
        reason: '${placements[i].assetKey} and ${placements[j].assetKey}',
      );
    }
  }
}

bool _containsRect(Rect outer, Rect inner) =>
    outer.contains(inner.topLeft) && outer.contains(inner.bottomRight);

List<int> _bruteVisibleIndices(RaceSceneryComponent scene, Rect viewport) => [
  for (var index = 0; index < scene.placements.length; index++)
    if (viewport.overlaps(scene.placements[index].cullBounds)) index,
];

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
