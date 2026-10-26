class TrackPoint {
  const TrackPoint(this.x, this.y);

  final double x;
  final double y;

  TrackPoint lerpTo(TrackPoint other, double t) =>
      TrackPoint(x + (other.x - x) * t, y + (other.y - y) * t);
}

enum TrackDirection { east, south, west, north }

class TrackGate {
  const TrackGate({
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
