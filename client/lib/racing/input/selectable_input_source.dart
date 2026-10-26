import 'car_input.dart';
import 'remote_input_source.dart';

enum RacingInputMode { keyboard, phone }

/// Keeps keyboard fallback for both cars while routing the red car by mode.
class SelectableInputSource implements InputSource {
  SelectableInputSource({
    required this.keyboard,
    required this.remote,
    this.onPhoneTimeout,
  });

  final KeyboardInputSource keyboard;
  final RemoteInputSource remote;
  final void Function()? onPhoneTimeout;
  RacingInputMode _mode = RacingInputMode.keyboard;
  bool _timeoutReported = false;

  RacingInputMode get mode => _mode;
  bool get canStart => _mode == RacingInputMode.keyboard || remote.readyToStart;

  void select(RacingInputMode mode) {
    if (_mode == mode) return;
    keyboard.clear();
    remote.lockUntilNeutral();
    _timeoutReported = false;
    _mode = mode;
  }

  void clear() {
    keyboard.clear();
    remote.lockUntilNeutral();
    _timeoutReported = false;
  }

  @override
  CarInput inputFor(PlayerId player) {
    if (player != PlayerId.red || _mode == RacingInputMode.keyboard) {
      return keyboard.inputFor(player);
    }
    if (!remote.hasFreshInput) {
      if (remote.connected && !_timeoutReported) {
        _timeoutReported = true;
        onPhoneTimeout?.call();
      }
      return const CarInput(emergencyStop: true);
    }
    _timeoutReported = false;
    return remote.inputFor(player);
  }
}
