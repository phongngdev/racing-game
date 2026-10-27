import 'package:flutter/services.dart';

import '../input/car_input.dart';
import '../input/remote_input_source.dart';

/// Academy keyboard mapping drives the visible red car with either WASD or
/// arrows. Phone sessions keep the existing tilt and pedal protocol intact.
class AcademyInputSource implements InputSource {
  AcademyInputSource({required this.remote, required this.usePhone});

  final RemoteInputSource remote;
  final bool usePhone;
  final Set<LogicalKeyboardKey> _pressed = {};

  static final _forward = {LogicalKeyboardKey.keyW, LogicalKeyboardKey.arrowUp};
  static final _reverse = {
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.arrowDown,
  };
  static final _left = {LogicalKeyboardKey.keyA, LogicalKeyboardKey.arrowLeft};
  static final _right = {
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.arrowRight,
  };

  void handleKey(LogicalKeyboardKey key, bool down) {
    if (down) {
      _pressed.add(key);
    } else {
      _pressed.remove(key);
    }
  }

  void clear() {
    _pressed.clear();
    if (usePhone) remote.lockUntilNeutral();
  }

  @override
  CarInput inputFor(PlayerId player) {
    if (player != PlayerId.red) return const CarInput();
    if (usePhone) {
      return remote.hasFreshInput
          ? remote.inputFor(player)
          : const CarInput(emergencyStop: true);
    }
    return CarInput(
      throttle: _pressed.any(_forward.contains) ? 1 : 0,
      reverse: _pressed.any(_reverse.contains) ? 1 : 0,
      steering:
          (_pressed.any(_right.contains) ? 1.0 : 0.0) -
          (_pressed.any(_left.contains) ? 1.0 : 0.0),
    );
  }
}
