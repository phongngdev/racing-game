import 'package:flutter/services.dart';

enum PlayerId { red, blue }

/// Controls normalized to [-1, 1] for steering and [0, 1] for pedals.
class CarInput {
  const CarInput({
    this.throttle = 0,
    this.brake = 0,
    this.steering = 0,
    this.horn = false,
  });

  final double throttle;
  final double brake;
  final double steering;
  final bool horn;
}

abstract interface class InputSource {
  CarInput inputFor(PlayerId player);
}

/// Keyboard adapter. The simulation only consumes [CarInput].
class KeyboardInputSource implements InputSource {
  final Set<LogicalKeyboardKey> _pressed = {};

  void handleKey(LogicalKeyboardKey key, bool isDown) {
    if (isDown) {
      _pressed.add(key);
    } else {
      _pressed.remove(key);
    }
  }

  void clear() => _pressed.clear();

  @override
  CarInput inputFor(PlayerId player) {
    final keys = switch (player) {
      PlayerId.red => _PlayerKeys(
        throttle: LogicalKeyboardKey.keyW,
        brake: LogicalKeyboardKey.keyS,
        left: LogicalKeyboardKey.keyA,
        right: LogicalKeyboardKey.keyD,
        horn: LogicalKeyboardKey.keyQ,
      ),
      PlayerId.blue => _PlayerKeys(
        throttle: LogicalKeyboardKey.arrowUp,
        brake: LogicalKeyboardKey.arrowDown,
        left: LogicalKeyboardKey.arrowLeft,
        right: LogicalKeyboardKey.arrowRight,
        horn: LogicalKeyboardKey.keyM,
      ),
    };
    final accelerating = _pressed.contains(keys.throttle);
    final braking = _pressed.contains(keys.brake);
    return CarInput(
      throttle: accelerating && !braking ? 1 : 0,
      brake: braking ? 1 : 0,
      steering:
          (_pressed.contains(keys.right) ? 1.0 : 0.0) -
          (_pressed.contains(keys.left) ? 1.0 : 0.0),
      horn: _pressed.contains(keys.horn),
    );
  }
}

class _PlayerKeys {
  const _PlayerKeys({
    required this.throttle,
    required this.brake,
    required this.left,
    required this.right,
    required this.horn,
  });

  final LogicalKeyboardKey throttle;
  final LogicalKeyboardKey brake;
  final LogicalKeyboardKey left;
  final LogicalKeyboardKey right;
  final LogicalKeyboardKey horn;
}
