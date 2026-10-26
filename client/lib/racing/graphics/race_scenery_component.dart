import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../sprint/sprint_graphics_assets.dart';
import '../tracks/track_definition.dart';
import 'race_scenery_data.dart';
import 'race_scenery_layout.dart';

export 'race_scenery_data.dart' show RaceSceneryPlacement, ScenerySpatialGrid;

/// Deterministic, non-colliding Kenney scenery shared by Sprint and Lap Race.
class RaceSceneryComponent extends Component {
  RaceSceneryComponent.sprint(
    TrackDefinition track,
    SprintGraphicsAssets assets,
  ) : this._(assets, RaceSceneryLayout.sprint(track));

  RaceSceneryComponent.lap(SprintGraphicsAssets assets)
    : this._(assets, RaceSceneryLayout.lap());

  RaceSceneryComponent._(this.assets, List<RaceSceneryPlacement> placements)
    : placements = List.unmodifiable(placements),
      _spatialGrid = ScenerySpatialGrid(placements);

  final SprintGraphicsAssets assets;
  final List<RaceSceneryPlacement> placements;
  final ScenerySpatialGrid _spatialGrid;
  SprintGraphicsStyle style = SprintGraphicsStyle.legacy;

  static final _paint = Paint()..filterQuality = FilterQuality.low;

  bool isVisibleIn(RaceSceneryPlacement placement, Rect visibleWorldRect) =>
      visibleWorldRect.overlaps(placement.cullBounds);

  /// Returns only sprites in grid cells intersecting this camera's viewport.
  /// The current camera is queried separately each time Flame renders a camera.
  List<int> visiblePlacementIndices(Rect visibleWorldRect) =>
      _spatialGrid.query(visibleWorldRect);

  @override
  void render(Canvas canvas) {
    if (style != SprintGraphicsStyle.kenney) return;
    final visible = CameraComponent.currentCamera?.visibleWorldRect;
    if (visible == null) return;
    for (final index in visiblePlacementIndices(visible)) {
      final placement = placements[index];
      final sprite = assets[placement.assetKey];
      if (sprite == null) continue;
      final source = sprite.src;
      final scale = math.min(
        placement.spriteWidth / source.width,
        placement.spriteHeight / source.height,
      );
      canvas.save();
      canvas.translate(placement.center.dx, placement.center.dy);
      if (placement.rotation.abs() > 0.0001) {
        canvas.rotate(placement.rotation);
      }
      canvas.drawImageRect(
        sprite.image,
        source,
        Rect.fromCenter(
          center: Offset.zero,
          width: source.width * scale,
          height: source.height * scale,
        ),
        _paint,
      );
      canvas.restore();
    }
  }
}
