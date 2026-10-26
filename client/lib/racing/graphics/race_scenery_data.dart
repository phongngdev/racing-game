import 'dart:math' as math;
import 'dart:ui';

/// Static scenery draw data. Bounds include the rotated image and a small
/// sampling margin so placement checks and camera culling use the full sprite.
class RaceSceneryPlacement {
  RaceSceneryPlacement({
    required this.assetKey,
    required this.center,
    required this.spriteWidth,
    required this.spriteHeight,
    this.rotation = 0,
    this.area = 'sprint',
    this.filterMargin = 2,
  }) : visualBounds = _rotatedBounds(
         center,
         spriteWidth,
         spriteHeight,
         rotation,
       ),
       cullBounds = _rotatedBounds(
         center,
         spriteWidth,
         spriteHeight,
         rotation,
       ).inflate(filterMargin);

  final String assetKey;
  final Offset center;
  final double spriteWidth;
  final double spriteHeight;
  final double rotation;
  final String area;
  final double filterMargin;
  final Rect visualBounds;
  final Rect cullBounds;

  static Rect _rotatedBounds(
    Offset center,
    double width,
    double height,
    double rotation,
  ) {
    final cosine = math.cos(rotation).abs();
    final sine = math.sin(rotation).abs();
    final halfWidth = (width * cosine + height * sine) / 2;
    final halfHeight = (width * sine + height * cosine) / 2;
    return Rect.fromCenter(
      center: center,
      width: halfWidth * 2,
      height: halfHeight * 2,
    );
  }
}

/// Indexes each image's complete cull bounds once, then queries only cells
/// touched by the current camera viewport.
class ScenerySpatialGrid {
  ScenerySpatialGrid(this.placements, {this.cellSize = 256})
    : _seenAt = List<int>.filled(placements.length, 0) {
    for (var index = 0; index < placements.length; index++) {
      final bounds = placements[index].cullBounds;
      final firstColumn = _cell(bounds.left);
      final lastColumn = _cell(bounds.right);
      final firstRow = _cell(bounds.top);
      final lastRow = _cell(bounds.bottom);
      for (var column = firstColumn; column <= lastColumn; column++) {
        for (var row = firstRow; row <= lastRow; row++) {
          (_cells[(column, row)] ??= <int>[]).add(index);
        }
      }
    }
  }

  final List<RaceSceneryPlacement> placements;
  final double cellSize;
  final Map<(int, int), List<int>> _cells = {};
  final List<int> _seenAt;
  int _queryId = 0;

  int _cell(double coordinate) => (coordinate / cellSize).floor();

  List<int> query(Rect visibleWorldRect) {
    if (placements.isEmpty || visibleWorldRect.isEmpty) return const [];
    if (_queryId == 0x7fffffff) {
      _seenAt.fillRange(0, _seenAt.length, 0);
      _queryId = 0;
    }
    final queryId = ++_queryId;
    final matches = <int>[];
    for (
      var column = _cell(visibleWorldRect.left);
      column <= _cell(visibleWorldRect.right);
      column++
    ) {
      for (
        var row = _cell(visibleWorldRect.top);
        row <= _cell(visibleWorldRect.bottom);
        row++
      ) {
        for (final index in _cells[(column, row)] ?? const <int>[]) {
          if (_seenAt[index] == queryId) continue;
          _seenAt[index] = queryId;
          if (visibleWorldRect.overlaps(placements[index].cullBounds)) {
            matches.add(index);
          }
        }
      }
    }
    matches.sort();
    return matches;
  }
}
