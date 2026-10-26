import 'dart:ui';

import '../lap/lap_race_track.dart';
import '../simulation/race_simulation.dart';
import '../tracks/track_definition.dart';

class RaceSurfacePatch {
  const RaceSurfacePatch({required this.path, required this.bounds});

  final Path path;
  final Rect bounds;
}

/// Builds a small, deterministic set of decorative dirt shapes from the
/// existing track geometry. It never consumes the track generator's RNG.
abstract final class RaceSurfacePatches {
  static const _roadClearance = 22.0;

  static List<RaceSurfacePatch> sprint(TrackDefinition track) {
    final result = <RaceSurfacePatch>[];
    final gates = <TrackGate>[track.start, ...track.checkpoints, track.finish];
    final salt = _trackHash(track);
    var index = 0;
    for (
      var station = 460.0;
      station < track.stations.last - 220;
      station += 820
    ) {
      final variation = _mix(salt, index);
      final frame = _frameAt(track, station + ((variation >>> 5) % 141) - 70);
      final width = 150.0 + (variation % 76);
      final height = 72.0 + ((variation >>> 8) % 37);
      final side = (variation & 1) == 0 ? 1.0 : -1.0;
      final center =
          frame.point +
          frame.normal * (side * (track.roadWidth / 2 + height / 2 + 28));
      final patch = _makePatch(
        center: center,
        tangent: frame.tangent,
        normal: frame.normal,
        width: width,
        height: height,
      );
      if (!_inside(track.worldBounds, patch.bounds) ||
          track.roadRects.any(
            (road) => road.inflate(_roadClearance).overlaps(patch.bounds),
          ) ||
          gates.any(
            (gate) =>
                _gateBounds(gate)
                    .inflate(_roadClearance)
                    .overlaps(patch.bounds),
          )) {
        index++;
        continue;
      }
      result.add(patch);
      index++;
    }
    return List.unmodifiable(result);
  }

  static List<RaceSurfacePatch> lap() {
    final island = RaceTrackLayout.island.deflate(8);
    final gates = <TrackGate>[
      LapRaceTrack.standard.finish,
      ...LapRaceTrack.standard.checkpoints,
    ];
    const centers = <(double, double, double, double)>[
      (402, 282, 94, 42),
      (558, 282, 94, 42),
      (402, 360, 94, 42),
      (558, 360, 94, 42),
    ];
    final patches = <RaceSurfacePatch>[];
    for (final (x, y, width, height) in centers) {
      final patch = _makePatch(
        center: Offset(x, y),
        tangent: const Offset(1, 0),
        normal: const Offset(0, 1),
        width: width,
        height: height,
      );
      if (_inside(island, patch.bounds) &&
          !gates.any(
            (gate) =>
                _gateBounds(gate)
                    .inflate(_roadClearance)
                    .overlaps(patch.bounds),
          )) {
        patches.add(patch);
      }
    }
    return List.unmodifiable(patches);
  }

  static RaceSurfacePatch _makePatch({
    required Offset center,
    required Offset tangent,
    required Offset normal,
    required double width,
    required double height,
  }) {
    Offset point(double along, double across) =>
        center + tangent * along + normal * across;

    final halfWidth = width / 2;
    final halfHeight = height / 2;
    final p0 = point(-halfWidth, 0);
    final p1 = point(0, -halfHeight);
    final p2 = point(halfWidth, 0);
    final p3 = point(0, halfHeight);
    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(
        point(-halfWidth * 0.76, -halfHeight * 0.62).dx,
        point(-halfWidth * 0.76, -halfHeight * 0.62).dy,
        point(-halfWidth * 0.27, -halfHeight * 0.68).dx,
        point(-halfWidth * 0.27, -halfHeight * 0.68).dy,
        p1.dx,
        p1.dy,
      )
      ..cubicTo(
        point(halfWidth * 0.32, -halfHeight * 0.68).dx,
        point(halfWidth * 0.32, -halfHeight * 0.68).dy,
        point(halfWidth * 0.70, -halfHeight * 0.48).dx,
        point(halfWidth * 0.70, -halfHeight * 0.48).dy,
        p2.dx,
        p2.dy,
      )
      ..cubicTo(
        point(halfWidth * 0.66, halfHeight * 0.54).dx,
        point(halfWidth * 0.66, halfHeight * 0.54).dy,
        point(halfWidth * 0.22, halfHeight * 0.70).dx,
        point(halfWidth * 0.22, halfHeight * 0.70).dy,
        p3.dx,
        p3.dy,
      )
      ..cubicTo(
        point(-halfWidth * 0.40, halfHeight * 0.70).dx,
        point(-halfWidth * 0.40, halfHeight * 0.70).dy,
        point(-halfWidth * 0.70, halfHeight * 0.44).dx,
        point(-halfWidth * 0.70, halfHeight * 0.44).dy,
        p0.dx,
        p0.dy,
      )
      ..close();
    final bounds =
        Rect.fromPoints(
          point(-halfWidth - 2, -halfHeight - 2),
          point(halfWidth + 2, halfHeight + 2),
        ).expandToInclude(
          Rect.fromPoints(
            point(-halfWidth - 2, halfHeight + 2),
            point(halfWidth + 2, -halfHeight - 2),
          ),
        );
    return RaceSurfacePatch(path: path, bounds: bounds);
  }

  static ({Offset point, Offset tangent, Offset normal}) _frameAt(
    TrackDefinition track,
    double station,
  ) {
    var index = 0;
    while (index < track.stations.length - 2 &&
        station > track.stations[index + 1]) {
      index++;
    }
    final start = track.centerline[index];
    final end = track.centerline[index + 1];
    final length = track.stations[index + 1] - track.stations[index];
    final tangent = Offset(
      (end.x - start.x) / length,
      (end.y - start.y) / length,
    );
    final point =
        Offset(start.x, start.y) + tangent * (station - track.stations[index]);
    return (
      point: point,
      tangent: tangent,
      normal: Offset(-tangent.dy, tangent.dx),
    );
  }

  static Rect _gateBounds(TrackGate gate) => Rect.fromPoints(
    Offset(gate.start.x, gate.start.y),
    Offset(gate.end.x, gate.end.y),
  );

  static bool _inside(Rect outer, Rect inner) =>
      outer.contains(inner.topLeft) && outer.contains(inner.bottomRight);

  static int _trackHash(TrackDefinition track) {
    var hash = _hashString('${track.seed ?? track.id}|${track.roadWidth}');
    for (final point in track.centerline) {
      hash = _hashString('${point.x},${point.y}', seed: hash);
    }
    return hash;
  }

  static int _hashString(String value, {int seed = 0x811c9dc5}) {
    var hash = seed;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  static int _mix(int seed, int value) =>
      ((seed ^ (value * 0x9e3779b9)) * 0x85ebca6b) & 0xffffffff;
}
