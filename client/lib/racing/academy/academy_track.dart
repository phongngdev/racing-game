import 'dart:math' as math;
import 'dart:ui' show Offset, Path, PathFillType;

import '../tracks/track_geometry.dart';

/// One immutable corridor supplies the asphalt polygon, painted boundaries,
/// wheel sensors and progress gates. Coordinates use 0.1 m per world unit.
class AcademyTrack {
  AcademyTrack._(List<TrackPoint> points, List<TrackPoint> tangents)
    : centerline = List.unmodifiable(points),
      roadWidth = 2.2 * vehicleWidth,
      halfWidth = 1.1 * vehicleWidth {
    leftBoundary = List.unmodifiable([
      for (var i = 0; i < points.length; i++)
        TrackPoint(
          points[i].x - tangents[i].y * halfWidth,
          points[i].y + tangents[i].x * halfWidth,
        ),
    ]);
    rightBoundary = List.unmodifiable([
      for (var i = 0; i < points.length; i++)
        TrackPoint(
          points[i].x + tangents[i].y * halfWidth,
          points[i].y - tangents[i].x * halfWidth,
        ),
    ]);
    roadPolygon = List.unmodifiable([
      ...leftBoundary,
      ...rightBoundary.reversed,
    ]);
    _roadPath = _path(roadPolygon, close: true);
    final cumulative = <double>[0];
    for (var i = 1; i < centerline.length; i++) {
      cumulative.add(
        cumulative.last + _distance(centerline[i - 1], centerline[i]),
      );
    }
    _stations = List.unmodifiable(cumulative);
  }

  factory AcademyTrack.sBend() {
    // QCVN 40:2024/BGTVT, 2.1.15.6 / Figure 11: opposite circular
    // bends with tangent continuity, Sqc = Rn + Rtr = 2 * centerRadius.
    // Figure 11's centres lie on a 45-degree diagonal. Rotate the layout
    // so the RC car starts heading east, with straight entry/exit aprons.
    const firstCenter = TrackPoint(360, 465);
    final separation = math.sqrt2 * centerRadius;
    final secondCenter = TrackPoint(
      firstCenter.x + separation,
      firstCenter.y - separation,
    );
    final points = <TrackPoint>[];
    final tangents = <TrackPoint>[];
    void append(TrackPoint point, TrackPoint tangent) {
      points.add(point);
      tangents.add(tangent);
    }

    void line(TrackPoint a, TrackPoint b, int steps) {
      for (var i = 0; i <= steps; i++) {
        if (points.isNotEmpty && i == 0) continue;
        append(a.lerpTo(b, i / steps), const TrackPoint(1, 0));
      }
    }

    void arc(TrackPoint center, double start, double sweep) {
      const steps = 72;
      for (var i = 1; i <= steps; i++) {
        final angle = start + sweep * i / steps;
        final sign = sweep.sign;
        append(
          TrackPoint(
            center.x + centerRadius * math.cos(angle),
            center.y + centerRadius * math.sin(angle),
          ),
          TrackPoint(-math.sin(angle) * sign, math.cos(angle) * sign),
        );
      }
    }

    line(const TrackPoint(92, 600), const TrackPoint(360, 600), 20);
    arc(firstCenter, math.pi / 2, -3 * math.pi / 4);
    arc(secondCenter, 3 * math.pi / 4, 3 * math.pi / 4);
    line(points.last, TrackPoint(908, secondCenter.y - centerRadius), 28);
    return AcademyTrack._(points, tangents);
  }

  final List<TrackPoint> centerline;
  final double roadWidth;
  final double halfWidth;
  late final List<TrackPoint> leftBoundary;
  late final List<TrackPoint> rightBoundary;
  late final List<TrackPoint> roadPolygon;
  late final List<double> _stations;
  late final Path _roadPath;

  static const checkpointFractions = [0.43, 0.70];
  List<double> get checkpointStations => checkpointFractions
      .map((fraction) => totalLength * fraction)
      .toList(growable: false);
  static const worldWidth = 1000.0;
  static const worldHeight = 700.0;
  static const wheelOffsetLongitudinal = 12.0;
  static const wheelbase = wheelOffsetLongitudinal * 2;
  static const wheelOffsetLateral = 10.0;
  static const tireRadius = 4.0;
  static const vehicleWidth = 2 * (wheelOffsetLateral + tireRadius);
  static const centerRadius = 135.0;
  static const boundaryLineWidth = 3.0;
  static const startStation = 145.0;

  TrackPoint get spawn => centerline[8];
  double get totalLength => _stations.last;

  List<TrackPoint> wheels(TrackPoint position, double heading) {
    final forward = TrackPoint(math.cos(heading), math.sin(heading));
    final side = TrackPoint(-forward.y, forward.x);
    return [
      for (final longitudinal in [
        wheelOffsetLongitudinal,
        -wheelOffsetLongitudinal,
      ])
        for (final lateral in [wheelOffsetLateral, -wheelOffsetLateral])
          TrackPoint(
            position.x + forward.x * longitudinal + side.x * lateral,
            position.y + forward.y * longitudinal + side.y * lateral,
          ),
    ];
  }

  List<int> wheelsTouchingBoundary(TrackPoint position, double heading) {
    final wheelPoints = wheels(position, heading);
    return [
      for (var i = 0; i < wheelPoints.length; i++)
        if (_distanceToBoundary(wheelPoints[i]) <=
            tireRadius + boundaryLineWidth / 2)
          i,
    ];
  }

  bool isOnRoad(TrackPoint point) =>
      _roadPath.contains(Offset(point.x, point.y));

  bool isEntirelyOffCourse(TrackPoint position, double heading) =>
      wheels(position, heading).every(
        (wheel) =>
            !isOnRoad(wheel) &&
            _distanceToBoundary(wheel) > tireRadius + boundaryLineWidth / 2,
      );

  double _distanceToBoundary(TrackPoint point) {
    var best = double.infinity;
    for (final boundary in [leftBoundary, rightBoundary]) {
      for (var i = 1; i < boundary.length; i++) {
        best = math.min(
          best,
          _distanceToSegment(point, boundary[i - 1], boundary[i]),
        );
      }
    }
    return best;
  }

  double stationOfClosestPoint(TrackPoint point) {
    var bestDistance = double.infinity;
    var bestStation = 0.0;
    for (var i = 1; i < centerline.length; i++) {
      final a = centerline[i - 1];
      final b = centerline[i];
      final t = _projection(point, a, b);
      final distance = _distance(point, a.lerpTo(b, t));
      if (distance < bestDistance) {
        bestDistance = distance;
        bestStation = _stations[i - 1] + (_stations[i] - _stations[i - 1]) * t;
      }
    }
    return bestStation;
  }

  /// A filled, explicitly closed contour; never pass the open centreline to
  /// drawAsphalt, whose Paint uses PaintingStyle.fill.
  Path roadPath() => Path.from(_roadPath);
  Path leftBoundaryPath() => _path(leftBoundary);
  Path rightBoundaryPath() => _path(rightBoundary);

  (int, double) _segmentAt(double station) {
    if (!station.isFinite || station < 0 || station > totalLength) {
      throw RangeError('Station is outside the Academy route.');
    }
    for (var i = 1; i < _stations.length; i++) {
      if (_stations[i] >= station) {
        return (
          i,
          (station - _stations[i - 1]) / (_stations[i] - _stations[i - 1]),
        );
      }
    }
    return (_stations.length - 1, 1);
  }

  (TrackPoint, TrackPoint) gateAt(double station) {
    final (i, t) = _segmentAt(station);
    return (
      leftBoundary[i - 1].lerpTo(leftBoundary[i], t),
      rightBoundary[i - 1].lerpTo(rightBoundary[i], t),
    );
  }

  TrackPoint pointAt(double station) {
    final (i, t) = _segmentAt(station);
    return centerline[i - 1].lerpTo(centerline[i], t);
  }

  TrackPoint directionAt(double station) {
    final (left, right) = gateAt(station);
    final dx = left.x - right.x;
    final dy = left.y - right.y;
    final length = math.sqrt(dx * dx + dy * dy);
    return TrackPoint(dy / length, -dx / length);
  }

  static Path _path(List<TrackPoint> points, {bool close = false}) {
    final path = Path()..fillType = PathFillType.nonZero;
    path.moveTo(points.first.x, points.first.y);
    for (final point in points.skip(1)) {
      path.lineTo(point.x, point.y);
    }
    if (close) path.close();
    return path;
  }

  static double _distance(TrackPoint a, TrackPoint b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  static double _projection(TrackPoint point, TrackPoint a, TrackPoint b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lengthSquared = dx * dx + dy * dy;
    return lengthSquared == 0
        ? 0
        : (((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared)
              .clamp(0.0, 1.0)
              .toDouble();
  }

  static double _distanceToSegment(TrackPoint p, TrackPoint a, TrackPoint b) =>
      _distance(p, a.lerpTo(b, _projection(p, a, b)));
}
