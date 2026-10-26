import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../simulation/race_simulation.dart';
import '../tracks/track_definition.dart';

/// Canvas-local rectangles shared by Flame viewports and Flutter pane labels.
List<Rect> sprintViewports(double width, double height) {
  if (width <= 0 || height <= 0) return const [];
  final gap = math.min(4.0, math.min(width, height) / 4);
  if (width / height >= 4 / 3) {
    final half = (width - gap) / 2;
    return [
      Rect.fromLTWH(0, 0, half, height),
      Rect.fromLTWH(half + gap, 0, half, height),
    ];
  }
  final half = (height - gap) / 2;
  return [
    Rect.fromLTWH(0, 0, width, half),
    Rect.fromLTWH(0, half + gap, width, half),
  ];
}

/// Presentation only: never advances simulation, input or race time.
class SprintCameraRig {
  SprintCameraRig(this.track);
  final TrackDefinition track;
  final Vector2 position = Vector2.zero();
  final Vector2 _lookAhead = Vector2.zero();
  Vector2 _viewport = Vector2.all(1);
  double get zoom => math.min(_viewport.x, _viewport.y) / track.cameraShortSide;

  void resize(double width, double height) {
    _viewport = Vector2(math.max(1, width), math.max(1, height));
    _clamp();
  }

  void snap(CarState car) {
    position.setFrom(car.renderPosition);
    _lookAhead.setZero();
    _clamp();
  }

  void update(
    double elapsed,
    CarState car, {
    required bool running,
    required bool finished,
  }) {
    if (!running || elapsed <= 0) return;
    final dt = elapsed.clamp(0.0, 0.1);
    final wanted = finished ? Vector2.zero() : car.velocity * 0.45;
    if (wanted.length > track.cameraLookAhead) {
      wanted.scale(track.cameraLookAhead / wanted.length);
    }
    _lookAhead.add((wanted - _lookAhead) * (1 - math.exp(-dt / 0.25)));
    position.add(
      (car.renderPosition + _lookAhead - position) * (1 - math.exp(-dt / 0.15)),
    );
    _clamp();
  }

  void _clamp() {
    final bounds = track.worldBounds;
    final halfWidth = _viewport.x / zoom / 2;
    final halfHeight = _viewport.y / zoom / 2;
    position.x = bounds.width <= halfWidth * 2
        ? bounds.center.dx
        : position.x.clamp(bounds.left + halfWidth, bounds.right - halfWidth);
    position.y = bounds.height <= halfHeight * 2
        ? bounds.center.dy
        : position.y.clamp(bounds.top + halfHeight, bounds.bottom - halfHeight);
  }
}
