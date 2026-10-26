import 'dart:math' as math;

import '../tracks/track_geometry.dart';
export '../tracks/track_geometry.dart';

typedef LapGate = TrackGate;

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
