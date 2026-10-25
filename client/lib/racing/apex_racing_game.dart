import 'dart:ui' show Canvas, Color, Paint, PaintingStyle, Rect;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

import 'input/car_input.dart';
import 'lap/lap_race_track.dart';
import 'simulation/race_simulation.dart';

class RaceSnapshot {
  const RaceSnapshot({this.redSpeed = 0, this.blueSpeed = 0});

  final double redSpeed;
  final double blueSpeed;
}

class ApexRacingGame extends FlameGame with KeyboardEvents {
  ApexRacingGame({
    required this.simulation,
    required this.inputSource,
    required this.snapshot,
    required this.onKeyboardEvent,
    this.lapTrack,
    this.onFrameUpdate,
  }) : super(
         camera: CameraComponent.withFixedResolution(
           width: RaceTrackLayout.worldWidth,
           height: RaceTrackLayout.worldHeight,
         ),
       ) {
    camera.viewfinder.position = Vector2(
      RaceTrackLayout.worldWidth / 2,
      RaceTrackLayout.worldHeight / 2,
    );
    world.addAll([
      TrackComponent(lapTrack: lapTrack),
      CarComponent(
        state: simulation.red,
        color: const Color(0xFFE34B50),
        isFinished: () => simulation.isPlayerFinished(PlayerId.red),
      ),
      CarComponent(
        state: simulation.blue,
        color: const Color(0xFF4388F5),
        isFinished: () => simulation.isPlayerFinished(PlayerId.blue),
      ),
    ]);
  }

  final RaceSimulation simulation;
  final InputSource inputSource;
  final ValueNotifier<RaceSnapshot> snapshot;
  final KeyEventResult Function(KeyEvent event) onKeyboardEvent;
  final LapRaceTrack? lapTrack;
  final void Function(double frameSeconds)? onFrameUpdate;
  double _snapshotElapsed = 0;

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) => onKeyboardEvent(event);

  @override
  Color backgroundColor() => const Color(0xFF193323);

  @override
  void update(double dt) {
    super.update(dt);
    final frameUpdate = onFrameUpdate;
    if (frameUpdate == null) {
      simulation.update(dt, inputSource);
    } else {
      frameUpdate(dt);
    }
    _snapshotElapsed += dt;
    if (_snapshotElapsed >= 0.1) {
      _snapshotElapsed %= 0.1;
      snapshot.value = RaceSnapshot(
        redSpeed: simulation.red.speed,
        blueSpeed: simulation.blue.speed,
      );
    }
  }
}

class TrackComponent extends Component {
  TrackComponent({this.lapTrack});

  final LapRaceTrack? lapTrack;

  @override
  void render(Canvas canvas) {
    final grass = Paint()..color = const Color(0xFF24452F);
    final asphalt = Paint()..color = const Color(0xFF34383C);
    final islandPaint = Paint()..color = const Color(0xFF2C573A);
    final wallShadow = Paint()..color = const Color(0xFF797F7C);
    final kerbRed = Paint()..color = const Color(0xFFE95458);
    final kerbWhite = Paint()..color = const Color(0xFFF0E9D8);
    final lane = Paint()..color = const Color(0xFFA6A394);

    canvas.drawRect(
      Rect.fromLTWH(
        0,
        0,
        RaceTrackLayout.worldWidth,
        RaceTrackLayout.worldHeight,
      ),
      grass,
    );
    canvas.drawRect(const Rect.fromLTWH(64, 64, 832, 512), asphalt);
    canvas.drawRect(RaceTrackLayout.island, islandPaint);

    for (final wall in RaceTrackLayout.walls) {
      if (wall.$1 == 'island') {
        canvas.drawRect(
          wall.$2.inflate(4),
          Paint()
            ..color = wallShadow.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 12,
        );
        canvas.drawRect(
          wall.$2.inflate(4),
          Paint()
            ..color = kerbRed.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8,
        );
        canvas.drawRect(
          wall.$2.inflate(4),
          Paint()
            ..color = kerbWhite.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        continue;
      }
      canvas.drawRect(wall.$2, wallShadow);
      const step = 16.0;
      final bounds = wall.$2;
      if (bounds.width > bounds.height) {
        for (var x = bounds.left; x < bounds.right; x += step) {
          canvas.drawRect(
            Rect.fromLTWH(x, bounds.top, step / 2, bounds.height),
            ((x / step).floor().isEven) ? kerbRed : kerbWhite,
          );
        }
      } else {
        for (var y = bounds.top; y < bounds.bottom; y += step) {
          canvas.drawRect(
            Rect.fromLTWH(bounds.left, y, bounds.width, step / 2),
            ((y / step).floor().isEven) ? kerbRed : kerbWhite,
          );
        }
      }
    }

    canvas.drawRect(
      RaceTrackLayout.island,
      Paint()
        ..color = const Color(0xFF191E1D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Small rectangular dashes keep the top-down track readable at game scale.
    for (var x = 190.0; x < 850; x += 48) {
      canvas.drawRect(Rect.fromLTWH(x, 136, 22, 3), lane);
      canvas.drawRect(Rect.fromLTWH(x, 501, 22, 3), lane);
    }
    for (var y = 260.0; y < 400; y += 42) {
      canvas.drawRect(Rect.fromLTWH(172, y, 3, 20), lane);
      canvas.drawRect(Rect.fromLTWH(785, y, 3, 20), lane);
    }

    final finish = lapTrack?.finish;
    if (finish == null) {
      // Preserve the Practice mode's original decorative line.
      const startX = 126.0;
      for (var row = 0; row < 18; row++) {
        for (var column = 0; column < 2; column++) {
          final paint = (row + column).isEven ? kerbWhite : wallShadow;
          canvas.drawRect(
            Rect.fromLTWH(startX + column * 8, 70 + row * 8, 8, 8),
            paint,
          );
        }
      }
    } else {
      final top = finish.start.y;
      final bottom = finish.end.y;
      var row = 0;
      for (var y = top; y < bottom; y += 8, row++) {
        for (var column = 0; column < 2; column++) {
          final paint = (row + column).isEven ? kerbWhite : wallShadow;
          canvas.drawRect(
            Rect.fromLTWH(finish.start.x - 8 + column * 8, y, 8, 8),
            paint,
          );
        }
      }
    }

    // A few square grass tufts add texture without external image assets.
    final tuft = Paint()..color = const Color(0xFF397049);
    for (var i = 0; i < 70; i++) {
      final x = (i * 137 + 31) % 944;
      final y = (i * 83 + 19) % 624;
      final insideOuterTrack = x >= 64 && x <= 896 && y >= 64 && y <= 576;
      final insideIsland =
          x >= RaceTrackLayout.island.left &&
          x <= RaceTrackLayout.island.right &&
          y >= RaceTrackLayout.island.top &&
          y <= RaceTrackLayout.island.bottom;
      if (!insideOuterTrack || insideIsland) {
        canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 4, 4), tuft);
      }
    }
  }
}

class CarComponent extends Component {
  CarComponent({
    required this.state,
    required this.color,
    this.isFinished = _neverFinished,
  });

  final CarState state;
  final Color color;
  final bool Function() isFinished;

  static bool _neverFinished() => false;

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(state.position.x, state.position.y);
    canvas.rotate(state.heading);

    canvas.drawRect(
      const Rect.fromLTWH(-17, -9, 38, 24),
      Paint()..color = const Color(0x66000000),
    );
    final tire = Paint()..color = const Color(0xFF111416);
    canvas.drawRect(const Rect.fromLTWH(-13, -14, 8, 5), tire);
    canvas.drawRect(const Rect.fromLTWH(9, -14, 8, 5), tire);
    canvas.drawRect(const Rect.fromLTWH(-13, 10, 8, 5), tire);
    canvas.drawRect(const Rect.fromLTWH(9, 10, 8, 5), tire);

    canvas.drawRect(
      const Rect.fromLTWH(-19, -12, 38, 24),
      Paint()..color = isFinished() ? color.withAlpha(112) : color,
    );
    canvas.drawRect(
      const Rect.fromLTWH(-18, -10, 3, 20),
      Paint()..color = const Color(0xFF22292B),
    );
    canvas.drawRect(
      const Rect.fromLTWH(15, -13, 5, 26),
      Paint()..color = const Color(0xFFEDE7D7),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-6, -8, 13, 16),
      Paint()..color = const Color(0xFFB8D2D5),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-1, -8, 3, 16),
      Paint()..color = const Color(0xFF4D6570),
    );
    canvas.drawRect(
      const Rect.fromLTWH(5, -2, 14, 4),
      Paint()..color = color.withAlpha(120),
    );
    canvas.restore();
  }
}
