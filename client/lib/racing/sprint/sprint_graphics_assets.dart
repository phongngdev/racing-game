import 'dart:ui';

import 'package:flame/components.dart';

import '../tracks/track_definition.dart';
import '../tracks/track_geometry.dart';

enum SprintGraphicsStyle { legacy, kenney }

typedef SprintSpriteLoader = Future<Sprite> Function(String assetPath);

/// Images are loaded once, shared by both sprint viewports, and owned by
/// Flame's image cache. Missing images leave the Canvas fallback available.
class SprintGraphicsAssets {
  SprintGraphicsAssets({SprintSpriteLoader? loadSprite})
    : _loadSprite = loadSprite ?? _loadDefaultSprite;

  final SprintSpriteLoader _loadSprite;
  Future<void>? _preloadFuture;
  final Map<String, Sprite> _sprites = {};

  Future<void> preload() => _preloadFuture ??= _load();

  Sprite? operator [](String key) => _sprites[key];

  bool get hasCars =>
      _sprites.containsKey('vehicles/car_red_1.png') &&
      _sprites.containsKey('vehicles/car_blue_1.png');

  Future<void> _load() async {
    await Future.wait(
      _assetKeys.map((key) async {
        try {
          _sprites[key] = await _loadSprite('racing/$key');
        } catch (_) {
          // A broken optional art asset must never prevent a race from starting.
        }
      }),
    );
  }

  static Future<Sprite> _loadDefaultSprite(String assetPath) =>
      Sprite.load(assetPath);

  static const _assetKeys = <String>[
    'vehicles/car_red_1.png',
    'vehicles/car_blue_1.png',
    'scenery/tree_small.png',
    'scenery/tree_large.png',
    'scenery/rock1.png',
    'scenery/rock2.png',
    'scenery/rock3.png',
    'scenery/tent_blue.png',
    'scenery/cone_straight.png',
    'scenery/barrel_blue.png',
    'scenery/tires_white.png',
  ];
}

class SprintSceneryComponent extends Component {
  SprintSceneryComponent(this.track, this.assets)
    : _placements = _placementsFor(track);

  final TrackDefinition track;
  final SprintGraphicsAssets assets;
  final List<_SceneryPlacement> _placements;
  SprintGraphicsStyle style = SprintGraphicsStyle.legacy;
  static final _paint = Paint()..filterQuality = FilterQuality.low;

  @override
  void render(Canvas canvas) {
    if (style != SprintGraphicsStyle.kenney) return;
    final visible = CameraComponent.currentCamera?.visibleWorldRect;
    if (visible == null) return;
    for (final placement in _placements) {
      if (!visible.overlaps(placement.bounds)) continue;
      final sprite = assets[placement.assetKey];
      if (sprite == null) continue;
      canvas.drawImageRect(sprite.image, sprite.src, placement.bounds, _paint);
    }
  }

  static List<_SceneryPlacement> _placementsFor(TrackDefinition track) {
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
    final candidates = <_SceneryCandidate>[];
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
        final bounds = Rect.fromCenter(
          center: Offset(x.toDouble(), y.toDouble()),
          width: style.$2,
          height: style.$2,
        );
        if (!track.worldBounds.contains(bounds.topLeft) ||
            !track.worldBounds.contains(bounds.bottomRight) ||
            track.roadRects.any((road) => road.inflate(22).overlaps(bounds)) ||
            _gates(
              track,
            ).any((gate) => _gateBounds(gate).inflate(22).overlaps(bounds))) {
          continue;
        }
        candidates.add(_SceneryCandidate(rank, style.$1, bounds));
      }
    }
    candidates.sort((a, b) => a.rank.compareTo(b.rank));
    final selected = <_SceneryPlacement>[];
    for (final candidate in candidates) {
      if (selected.any(
        (existing) => existing.bounds.inflate(12).overlaps(candidate.bounds),
      )) {
        continue;
      }
      selected.add(_SceneryPlacement(candidate.assetKey, candidate.bounds));
      if (selected.length == 28) break;
    }
    return List.unmodifiable(selected);
  }

  static Iterable<TrackGate> _gates(TrackDefinition track) sync* {
    yield track.start;
    yield* track.checkpoints;
    yield track.finish;
  }

  static Rect _gateBounds(TrackGate gate) => Rect.fromPoints(
    Offset(gate.start.x, gate.start.y),
    Offset(gate.end.x, gate.end.y),
  );
}

class _SceneryCandidate {
  const _SceneryCandidate(this.rank, this.assetKey, this.bounds);

  final int rank;
  final String assetKey;
  final Rect bounds;
}

class _SceneryPlacement {
  const _SceneryPlacement(this.assetKey, this.bounds);

  final String assetKey;
  final Rect bounds;
}
