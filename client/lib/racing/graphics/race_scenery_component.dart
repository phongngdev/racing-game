import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../lap/lap_race_track.dart';
import '../simulation/race_simulation.dart';
import '../sprint/sprint_graphics_assets.dart';
import '../tracks/track_definition.dart';

/// Deterministic, non-colliding Kenney scenery shared by Sprint and Lap Race.
class RaceSceneryComponent extends Component {
  RaceSceneryComponent.sprint(
    TrackDefinition track,
    SprintGraphicsAssets assets,
  ) : this._(assets, _sprintPlacements(track));

  RaceSceneryComponent.lap(SprintGraphicsAssets assets)
    : this._(assets, _lapPlacements());

  RaceSceneryComponent._(this.assets, List<RaceSceneryPlacement> placements)
    : placements = List.unmodifiable(placements);

  final SprintGraphicsAssets assets;
  final List<RaceSceneryPlacement> placements;
  SprintGraphicsStyle style = SprintGraphicsStyle.legacy;

  static final _paint = Paint()..filterQuality = FilterQuality.low;

  bool isVisibleIn(RaceSceneryPlacement placement, Rect visibleWorldRect) =>
      visibleWorldRect.overlaps(placement.cullBounds);

  @override
  void render(Canvas canvas) {
    if (style != SprintGraphicsStyle.kenney) return;
    final visible = CameraComponent.currentCamera?.visibleWorldRect;
    if (visible == null) return;
    for (final placement in placements) {
      if (!isVisibleIn(placement, visible)) continue;
      final sprite = assets[placement.assetKey];
      if (sprite == null) continue;
      final source = sprite.src;
      final scale = math.min(
        placement.visualBounds.width / source.width,
        placement.visualBounds.height / source.height,
      );
      final destination = Rect.fromCenter(
        center: placement.visualBounds.center,
        width: source.width * scale,
        height: source.height * scale,
      );
      canvas.drawImageRect(sprite.image, source, destination, _paint);
    }
  }

  static List<RaceSceneryPlacement> _sprintPlacements(TrackDefinition track) {
    const styles = <(String, double)>[
      ('scenery/tree_small.png', 48),
      ('scenery/tree_large.png', 64),
      ('scenery/rock1.png', 36),
      ('scenery/rock2.png', 34),
      ('scenery/rock3.png', 36),
      ('scenery/tent_blue.png', 44),
      ('scenery/cone_straight.png', 26),
      ('scenery/barrel_blue.png', 28),
      ('scenery/tires_white.png', 30),
    ];
    final candidates = <RaceSceneryPlacement>[];
    for (
      var x = track.worldBounds.left + 44;
      x < track.worldBounds.right - 44;
      x += 92
    ) {
      for (
        var y = track.worldBounds.top + 44;
        y < track.worldBounds.bottom - 44;
        y += 92
      ) {
        final rank =
            ((x.toInt() * 73856093) ^ (y.toInt() * 19349663)) & 0x7fffffff;
        final style = styles[rank % styles.length];
        final candidate = _placement(
          style.$1,
          Offset(x.toDouble(), y.toDouble()),
          style.$2,
        );
        if (!track.worldBounds.contains(candidate.cullBounds.topLeft) ||
            !track.worldBounds.contains(candidate.cullBounds.bottomRight) ||
            track.roadRects.any(
              (road) => road.inflate(22).overlaps(candidate.cullBounds),
            ) ||
            _gates(track).any(
              (gate) =>
                  _gateBounds(gate).inflate(22).overlaps(candidate.cullBounds),
            )) {
          continue;
        }
        candidates.add(candidate.withRank(rank));
      }
    }
    candidates.sort((a, b) => a.rank.compareTo(b.rank));
    return _selectSeparated(candidates, maximum: 28, gap: 12);
  }

  static List<RaceSceneryPlacement> _lapPlacements() {
    const styles = <(String, double)>[
      ('scenery/tree_small.png', 38),
      ('scenery/tree_large.png', 46),
      ('scenery/rock1.png', 32),
      ('scenery/rock2.png', 30),
      ('scenery/rock3.png', 34),
      ('scenery/tent_blue.png', 40),
      ('scenery/tires_white.png', 30),
    ];
    final safeIsland = RaceTrackLayout.island.deflate(26);
    final candidates = <RaceSceneryPlacement>[];
    for (var x = safeIsland.left + 2; x < safeIsland.right - 2; x += 60) {
      for (var y = safeIsland.top + 2; y < safeIsland.bottom - 2; y += 48) {
        final rank =
            ((x.toInt() * 73856093) ^ (y.toInt() * 19349663)) & 0x7fffffff;
        final style = styles[rank % styles.length];
        final candidate = _placement(
          style.$1,
          Offset(x, y),
          style.$2,
        ).withRank(rank);
        if (!safeIsland.contains(candidate.cullBounds.topLeft) ||
            !safeIsland.contains(candidate.cullBounds.bottomRight) ||
            _lapGates().any(
              (gate) =>
                  _gateBounds(gate).inflate(22).overlaps(candidate.cullBounds),
            )) {
          continue;
        }
        candidates.add(candidate);
      }
    }
    candidates.sort((a, b) => a.rank.compareTo(b.rank));
    return _selectSeparated(candidates, maximum: 16, gap: 8);
  }

  static List<RaceSceneryPlacement> _selectSeparated(
    List<RaceSceneryPlacement> candidates, {
    required int maximum,
    required double gap,
  }) {
    final selected = <RaceSceneryPlacement>[];
    for (final candidate in candidates) {
      if (selected.any(
        (existing) =>
            existing.cullBounds.inflate(gap).overlaps(candidate.cullBounds),
      )) {
        continue;
      }
      selected.add(candidate);
      if (selected.length == maximum) break;
    }
    return List.unmodifiable(selected);
  }

  static RaceSceneryPlacement _placement(
    String assetKey,
    Offset center,
    double size,
  ) {
    final visualBounds = Rect.fromCenter(
      center: center,
      width: size,
      height: size,
    );
    // The full source image, including any transparent shadow pixels, is fit
    // inside visualBounds. Two units allow for low-quality filter sampling.
    return RaceSceneryPlacement(
      assetKey: assetKey,
      visualBounds: visualBounds,
      cullBounds: visualBounds.inflate(2),
    );
  }

  static Iterable<TrackGate> _gates(TrackDefinition track) sync* {
    yield track.start;
    yield* track.checkpoints;
    yield track.finish;
  }

  static Iterable<TrackGate> _lapGates() sync* {
    final track = LapRaceTrack.standard;
    yield track.finish;
    yield* track.checkpoints;
  }

  static Rect _gateBounds(TrackGate gate) => Rect.fromPoints(
    Offset(gate.start.x, gate.start.y),
    Offset(gate.end.x, gate.end.y),
  );
}

class RaceSceneryPlacement {
  const RaceSceneryPlacement({
    required this.assetKey,
    required this.visualBounds,
    required this.cullBounds,
    this.rank = 0,
  });

  final String assetKey;
  final Rect visualBounds;
  final Rect cullBounds;
  final int rank;

  RaceSceneryPlacement withRank(int rank) => RaceSceneryPlacement(
    assetKey: assetKey,
    visualBounds: visualBounds,
    cullBounds: cullBounds,
    rank: rank,
  );
}
