import 'dart:math' as math;

class TrackPoint {
  const TrackPoint(this.x, this.y);

  final double x;
  final double y;

  TrackPoint lerpTo(TrackPoint other, double t) =>
      TrackPoint(x + (other.x - x) * t, y + (other.y - y) * t);
}

enum TrackDirection { east, south, west, north }

class LapGate {
  const LapGate({
    required this.id,
    required this.start,
    required this.end,
    required this.direction,
  });

  final String id;
  final TrackPoint start;
  final TrackPoint end;
  final TrackDirection direction;

  TrackPoint get _normal => switch (direction) {
    TrackDirection.east => const TrackPoint(1, 0),
    TrackDirection.south => const TrackPoint(0, 1),
    TrackDirection.west => const TrackPoint(-1, 0),
    TrackDirection.north => const TrackPoint(0, -1),
  };

  double signedDistance(TrackPoint point) {
    final normal = _normal;
    return (point.x - start.x) * normal.x + (point.y - start.y) * normal.y;
  }

  GateCrossing? crossing(
    TrackPoint from,
    TrackPoint to, {
    required bool forward,
  }) {
    final fromDistance = signedDistance(from);
    final toDistance = signedDistance(to);
    final movesForward = toDistance > fromDistance;
    if (forward ? !movesForward : movesForward) return null;
    if (forward
        ? (fromDistance > 0 || toDistance < 0)
        : (fromDistance < 0 || toDistance > 0)) {
      return null;
    }
    final distanceDelta = toDistance - fromDistance;
    if (distanceDelta.abs() < 1e-9) return null;
    final t = (-fromDistance / distanceDelta).clamp(0.0, 1.0);
    final point = from.lerpTo(to, t);
    final gateX = end.x - start.x;
    final gateY = end.y - start.y;
    final gateLengthSquared = gateX * gateX + gateY * gateY;
    if (gateLengthSquared <= 0) return null;
    final along =
        ((point.x - start.x) * gateX + (point.y - start.y) * gateY) /
        gateLengthSquared;
    if (along < 0 || along > 1) return null;
    return GateCrossing(t: t, point: point);
  }
}

class GateCrossing {
  const GateCrossing({required this.t, required this.point});

  /// Fraction of the fixed step at which the car center crossed the gate.
  final double t;
  final TrackPoint point;
}

class LapRaceTrack {
  const LapRaceTrack({
    required this.finish,
    required this.checkpoints,
    required this.redGrid,
    required this.blueGrid,
  });

  static const standard = LapRaceTrack(
    finish: LapGate(
      id: 'finish',
      start: TrackPoint(480, 64),
      end: TrackPoint(480, 214),
      direction: TrackDirection.east,
    ),
    checkpoints: [
      LapGate(
        id: 'cp1-right',
        start: TrackPoint(680, 320),
        end: TrackPoint(896, 320),
        direction: TrackDirection.south,
      ),
      LapGate(
        id: 'cp2-bottom',
        start: TrackPoint(480, 426),
        end: TrackPoint(480, 576),
        direction: TrackDirection.west,
      ),
      LapGate(
        id: 'cp3-left',
        start: TrackPoint(64, 320),
        end: TrackPoint(280, 320),
        direction: TrackDirection.north,
      ),
    ],
    redGrid: TrackPoint(430, 112),
    blueGrid: TrackPoint(430, 166),
  );

  final LapGate finish;
  final List<LapGate> checkpoints;
  final TrackPoint redGrid;
  final TrackPoint blueGrid;

  List<LapGate> get orderedLapGates => [...checkpoints, finish];

  bool get hasValidGateGeometry {
    if (checkpoints.length != 3 ||
        orderedLapGates.map((gate) => gate.id).toSet().length != 4) {
      return false;
    }
    final walls = const <(double, double, double, double)>[
      (0, 0, 960, 64),
      (0, 576, 960, 640),
      (0, 64, 64, 576),
      (896, 64, 960, 576),
      (280, 214, 680, 426),
    ];
    for (final gate in orderedLapGates) {
      final midpoint = TrackPoint(
        (gate.start.x + gate.end.x) / 2,
        (gate.start.y + gate.end.y) / 2,
      );
      if (walls.any(
        (wall) =>
            midpoint.x > wall.$1 &&
            midpoint.x < wall.$3 &&
            midpoint.y > wall.$2 &&
            midpoint.y < wall.$4,
      )) {
        return false;
      }
      final length = math.sqrt(
        math.pow(gate.end.x - gate.start.x, 2) +
            math.pow(gate.end.y - gate.start.y, 2),
      );
      if (length <= 0) return false;
    }
    return true;
  }
}
