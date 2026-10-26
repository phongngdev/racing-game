import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../tracks/track_definition.dart';
import '../tracks/track_geometry.dart';

class SprintTrackComponent extends Component {
  SprintTrackComponent(this.track);
  final TrackDefinition track;
  final _grass = Paint()..color = const Color(0xFF24452F);
  final _road = Paint()..color = const Color(0xFF34383C);
  final _line = Paint()
    ..color = const Color(0xFFAAA595)
    ..strokeWidth = 3;
  final _white = Paint()..color = const Color(0xFFF0E9D8);
  final _dark = Paint()..color = const Color(0xFF191E1D);
  final _checkpoint = Paint()
    ..color = const Color(0x665BD184)
    ..strokeWidth = 4;

  @override
  void render(Canvas canvas) {
    final visible =
        CameraComponent.currentCamera?.visibleWorldRect ?? track.worldBounds;
    canvas.drawRect(visible.intersect(track.worldBounds), _grass);
    for (final road in track.roadRects) {
      if (visible.overlaps(road)) canvas.drawRect(road, _road);
    }
    for (var i = 0; i < track.centerline.length - 1; i++) {
      final a = track.centerline[i];
      final b = track.centerline[i + 1];
      final length = track.stations[i + 1] - track.stations[i];
      final dx = (b.x - a.x) / length;
      final dy = (b.y - a.y) / length;
      // Route dashes and arrows share the centerline used by checkpoints.
      for (var s = 140.0; s < length - 80; s += 120) {
        final point = Offset(a.x + dx * s, a.y + dy * s);
        if (!visible.inflate(25).contains(point)) continue;
        canvas.drawLine(point, point + Offset(dx * 24, dy * 24), _line);
        final tip = point + Offset(dx * 42, dy * 42);
        canvas.drawLine(
          tip,
          tip - Offset(dx * 14 - dy * 9, dy * 14 + dx * 9),
          _line,
        );
        canvas.drawLine(
          tip,
          tip - Offset(dx * 14 + dy * 9, dy * 14 - dx * 9),
          _line,
        );
      }
    }
    for (final gate in track.checkpoints) {
      final bounds = Rect.fromPoints(
        Offset(gate.start.x, gate.start.y),
        Offset(gate.end.x, gate.end.y),
      ).inflate(4);
      if (visible.overlaps(bounds)) {
        canvas.drawLine(
          Offset(gate.start.x, gate.start.y),
          Offset(gate.end.x, gate.end.y),
          _checkpoint,
        );
      }
    }
    _drawLine(canvas, track.start, visible);
    _drawLine(canvas, track.finish, visible);
  }

  void _drawLine(Canvas canvas, TrackGate gate, Rect visible) {
    final horizontal = gate.start.y == gate.end.y;
    final length = horizontal
        ? (gate.end.x - gate.start.x).abs()
        : (gate.end.y - gate.start.y).abs();
    final bounds = Rect.fromPoints(
      Offset(gate.start.x, gate.start.y),
      Offset(gate.end.x, gate.end.y),
    ).inflate(8);
    if (!visible.overlaps(bounds)) return;
    for (var n = 0; n * 10 < length; n++) {
      for (var col = 0; col < 2; col++) {
        final rect = horizontal
            ? Rect.fromLTWH(
                gate.start.x + n * 10,
                gate.start.y - 10 + col * 10,
                math.min(10, length - n * 10),
                10,
              )
            : Rect.fromLTWH(
                gate.start.x - 10 + col * 10,
                gate.start.y + n * 10,
                10,
                math.min(10, length - n * 10),
              );
        canvas.drawRect(rect, (n + col).isEven ? _white : _dark);
      }
    }
  }
}
