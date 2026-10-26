import 'dart:math' as math;
import 'dart:ui';

import 'track_geometry.dart';

class SpawnPose {
  const SpawnPose(this.position, this.heading);
  final TrackPoint position;
  final double heading;
}

/// Immutable corridor data shared by rendering, collision and race progress.
/// A future seed generator supplies its centerline to the same factory.
class TrackDefinition {
  TrackDefinition._({
    required this.id,
    required this.worldBounds,
    required List<TrackPoint> centerline,
    required this.roadWidth,
    required List<Rect> roadRects,
    required List<(String, Rect)> walls,
    required this.redSpawn,
    required this.blueSpawn,
    required this.start,
    required List<TrackGate> checkpoints,
    required List<double> checkpointStations,
    required this.finish,
    required this.finishStation,
    required List<double> stations,
  }) : centerline = List.unmodifiable(centerline),
       roadRects = List.unmodifiable(roadRects),
       walls = List.unmodifiable(walls),
       checkpoints = List.unmodifiable(checkpoints),
       checkpointStations = List.unmodifiable(checkpointStations),
       stations = List.unmodifiable(stations);

  factory TrackDefinition.corridor({
    required String id,
    required Rect worldBounds,
    required List<TrackPoint> centerline,
    double roadWidth = 200,
  }) {
    if (centerline.length < 2 ||
        !roadWidth.isFinite ||
        roadWidth < 128 ||
        !worldBounds.isFinite ||
        worldBounds.isEmpty) {
      throw ArgumentError('A corridor needs bounds, width >= 128 and a route.');
    }
    final roads = <Rect>[];
    final stations = <double>[0];
    final gates = <TrackGate>[];
    final gateStations = <double>[];
    final half = roadWidth / 2;
    for (var i = 0; i < centerline.length - 1; i++) {
      final a = centerline[i];
      final b = centerline[i + 1];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final length = dx.abs() + dy.abs();
      if (!a.x.isFinite ||
          !a.y.isFinite ||
          !b.x.isFinite ||
          !b.y.isFinite ||
          (dx != 0 && dy != 0) ||
          length < 300) {
        throw ArgumentError(
          'Route segments must be cardinal and >= 300 units.',
        );
      }
      if (i > 0) {
        final previous = centerline[i - 1];
        if ((a.x - previous.x) * dx + (a.y - previous.y) * dy != 0) {
          throw ArgumentError(
            'Consecutive route segments must turn 90 degrees.',
          );
        }
      }
      final road = Rect.fromLTRB(
        math.min(a.x, b.x) - half,
        math.min(a.y, b.y) - half,
        math.max(a.x, b.x) + half,
        math.max(a.y, b.y) + half,
      );
      if (road.left < worldBounds.left + 32 ||
          road.right > worldBounds.right - 32 ||
          road.top < worldBounds.top + 32 ||
          road.bottom > worldBounds.bottom - 32) {
        throw ArgumentError(
          'Road needs at least 32 units of wall inside world bounds.',
        );
      }
      for (var j = 0; j < roads.length - 1; j++) {
        if (roads[j].inflate(16).overlaps(road.inflate(16))) {
          throw ArgumentError('Nonadjacent roads must be separated by walls.');
        }
      }
      roads.add(road);
      if (i < centerline.length - 2) {
        gates.add(_gate('cp${i + 1}', a.lerpTo(b, 0.5), dx, dy, half));
        gateStations.add(stations.last + length / 2);
      }
      stations.add(stations.last + length);
    }
    final first = centerline.first;
    final second = centerline[1];
    final firstLength = stations[1];
    final tx = (second.x - first.x) / firstLength;
    final ty = (second.y - first.y) / firstLength;
    final heading = math.atan2(ty, tx);
    SpawnPose spawn(double offset) => SpawnPose(
      TrackPoint(
        first.x + tx * 60 - ty * offset,
        first.y + ty * 60 + tx * offset,
      ),
      heading,
    );
    final last = centerline.last;
    final beforeLast = centerline[centerline.length - 2];
    final lastLength = stations.last - stations[stations.length - 2];
    final fx = (last.x - beforeLast.x) / lastLength;
    final fy = (last.y - beforeLast.y) / lastLength;
    final definition = TrackDefinition._(
      id: id,
      worldBounds: worldBounds,
      centerline: centerline,
      roadWidth: roadWidth,
      roadRects: roads,
      walls: _compileWalls(worldBounds, roads),
      redSpawn: spawn(-32),
      blueSpawn: spawn(32),
      start: _gate(
        'start',
        TrackPoint(first.x + tx * 120, first.y + ty * 120),
        tx,
        ty,
        half,
      ),
      checkpoints: gates,
      checkpointStations: gateStations,
      finish: _gate(
        'finish',
        TrackPoint(last.x - fx * 100, last.y - fy * 100),
        fx,
        fy,
        half,
      ),
      finishStation: stations.last - 100,
      stations: stations,
    );
    if (!definition.isDrivable(definition.redSpawn.position) ||
        !definition.isDrivable(definition.blueSpawn.position)) {
      throw ArgumentError('Spawn poses must fit inside the road.');
    }
    return definition;
  }

  final String id;
  final Rect worldBounds;
  final List<TrackPoint> centerline;
  final double roadWidth;
  final List<Rect> roadRects;
  final List<(String, Rect)> walls;
  final SpawnPose redSpawn;
  final SpawnPose blueSpawn;
  final TrackGate start;
  final List<TrackGate> checkpoints;
  final List<double> checkpointStations;
  final TrackGate finish;
  final double finishStation;
  final List<double> stations;
  double get gridStation => 60;
  double get cameraShortSide => 480;
  double get cameraLookAhead => 90;

  bool isDrivable(TrackPoint point, {double radius = 16}) {
    if (!worldBounds.contains(Offset(point.x, point.y))) return false;
    for (final wall in walls) {
      final x = point.x.clamp(wall.$2.left, wall.$2.right);
      final y = point.y.clamp(wall.$2.top, wall.$2.bottom);
      final dx = point.x - x;
      final dy = point.y - y;
      if (dx * dx + dy * dy < radius * radius - 1e-6) return false;
    }
    return true;
  }

  /// Project only onto the currently validated part of the route.
  double projectStation(TrackPoint point, double minimum, double maximum) {
    var bestDistance = double.infinity;
    var bestStation = minimum;
    for (var i = 0; i < centerline.length - 1; i++) {
      if (stations[i + 1] < minimum || stations[i] > maximum) continue;
      final a = centerline[i];
      final b = centerline[i + 1];
      final length = stations[i + 1] - stations[i];
      final dx = (b.x - a.x) / length;
      final dy = (b.y - a.y) / length;
      final local = ((point.x - a.x) * dx + (point.y - a.y) * dy).clamp(
        math.max(0, minimum - stations[i]),
        math.min(length, maximum - stations[i]),
      );
      final px = a.x + dx * local;
      final py = a.y + dy * local;
      final distance = math.pow(point.x - px, 2) + math.pow(point.y - py, 2);
      if (distance < bestDistance) {
        bestDistance = distance.toDouble();
        bestStation = stations[i] + local;
      }
    }
    return bestStation;
  }

  static TrackGate _gate(
    String id,
    TrackPoint center,
    double dx,
    double dy,
    double half,
  ) {
    final direction = dx > 0
        ? TrackDirection.east
        : dx < 0
        ? TrackDirection.west
        : dy > 0
        ? TrackDirection.south
        : TrackDirection.north;
    return TrackGate(
      id: id,
      direction: direction,
      start: TrackPoint(
        center.x - (dy != 0 ? half : 0),
        center.y - (dx != 0 ? half : 0),
      ),
      end: TrackPoint(
        center.x + (dy != 0 ? half : 0),
        center.y + (dx != 0 ? half : 0),
      ),
    );
  }

  static List<(String, Rect)> _compileWalls(Rect bounds, List<Rect> roads) {
    final xs = {
      bounds.left,
      bounds.right,
      for (final r in roads) ...[r.left, r.right],
    }.toList()..sort();
    final ys = {
      bounds.top,
      bounds.bottom,
      for (final r in roads) ...[r.top, r.bottom],
    }.toList()..sort();
    final rectangles = <Rect>[];
    var previous = <(double, double), int>{};
    for (var x = 0; x < xs.length - 1; x++) {
      final current = <(double, double), int>{};
      int? run;
      for (var y = 0; y < ys.length; y++) {
        final blocked =
            y < ys.length - 1 &&
            !roads.any(
              (r) => r.contains(
                Offset((xs[x] + xs[x + 1]) / 2, (ys[y] + ys[y + 1]) / 2),
              ),
            );
        if (blocked) {
          run ??= y;
        } else if (run != null) {
          final key = (ys[run], ys[y]);
          final index = previous[key];
          if (index != null) {
            final old = rectangles[index];
            rectangles[index] = Rect.fromLTRB(
              old.left,
              old.top,
              xs[x + 1],
              old.bottom,
            );
            current[key] = index;
          } else {
            current[key] = rectangles.length;
            rectangles.add(Rect.fromLTRB(xs[x], ys[run], xs[x + 1], ys[y]));
          }
          run = null;
        }
      }
      previous = current;
    }
    return [
      for (var i = 0; i < rectangles.length; i++)
        ('corridor-wall-$i', rectangles[i]),
    ];
  }
}

class FixedTracks {
  static final sprint = TrackDefinition.corridor(
    id: 'sprint-01',
    worldBounds: const Rect.fromLTWH(0, 0, 3600, 2200),
    centerline: const [
      TrackPoint(240, 1800),
      TrackPoint(1050, 1800),
      TrackPoint(1050, 1200),
      TrackPoint(450, 1200),
      TrackPoint(450, 400),
      TrackPoint(1900, 400),
      TrackPoint(1900, 1000),
      TrackPoint(3000, 1000),
      TrackPoint(3000, 1800),
      TrackPoint(3400, 1800),
    ],
  );
}
