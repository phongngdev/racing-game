import 'car_input.dart';

/// Holds the newest phone sample. The race loop reads it synchronously.
class RemoteInputSource implements InputSource {
  RemoteInputSource({
    int Function()? clockMicros,
    this.timeout = const Duration(milliseconds: 300),
    this.player = PlayerId.red,
    this.requireNeutralAfterTimeout = false,
  }) : _clockMicros = clockMicros ?? _monotonicClock();

  final int Function() _clockMicros;
  final Duration timeout;
  final PlayerId player;
  final bool requireNeutralAfterTimeout;
  CarInput _latest = const CarInput();
  int? _receivedAt;
  int? _generation;
  int _lastSequence = -1;
  bool _connected = false;
  bool _requiresNeutral = true;

  bool get connected => _connected;
  int? get generation => _generation;
  bool get hasFreshInput {
    _expireIfStale();
    return _connected &&
        _receivedAt != null &&
        _clockMicros() - _receivedAt! <= timeout.inMicroseconds;
  }

  bool get readyToStart =>
      hasFreshInput &&
      !_requiresNeutral &&
      _latest.throttle == 0 &&
      _latest.reverse == 0 &&
      _latest.brake == 0;

  void setConnected(bool value, {int? generation}) {
    if (!value || generation != _generation) {
      _clear();
      _requiresNeutral = true;
    }
    _connected = value;
    if (value) _generation = generation;
  }

  bool accept({
    required int sequence,
    required int generation,
    required double steering,
    required double throttle,
    required double brake,
    double reverse = 0,
  }) {
    if (!_connected || generation != _generation || sequence <= _lastSequence) {
      return false;
    }
    _expireIfStale();
    if (!steering.isFinite ||
        !throttle.isFinite ||
        !reverse.isFinite ||
        !brake.isFinite ||
        steering < -1 ||
        steering > 1 ||
        throttle < 0 ||
        throttle > 1 ||
        reverse < 0 ||
        reverse > 1 ||
        brake < 0 ||
        brake > 1) {
      return false;
    }
    _lastSequence = sequence;
    _latest = CarInput(
      steering: steering,
      throttle: throttle,
      reverse: reverse,
      brake: brake,
    );
    _receivedAt = _clockMicros();
    if (throttle == 0 && reverse == 0 && brake == 0) {
      _requiresNeutral = false;
    }
    return true;
  }

  /// Call when pausing, resetting, or changing input modes.
  void lockUntilNeutral() {
    _latest = const CarInput();
    _requiresNeutral = true;
  }

  /// Keeps the phone connected while forcing a fresh neutral sample before use.
  void markUnavailable() {
    _latest = const CarInput();
    _receivedAt = null;
    _requiresNeutral = true;
  }

  void clear() {
    _clear();
    _requiresNeutral = true;
  }

  void _clear() {
    _latest = const CarInput();
    _receivedAt = null;
    _generation = null;
    _lastSequence = -1;
  }

  @override
  CarInput inputFor(PlayerId player) {
    if (player != this.player) {
      return const CarInput();
    }
    if (!hasFreshInput || _requiresNeutral) {
      return const CarInput(emergencyStop: true);
    }
    return _latest;
  }

  void _expireIfStale() {
    if (!requireNeutralAfterTimeout || _receivedAt == null) return;
    if (_clockMicros() - _receivedAt! > timeout.inMicroseconds) {
      _latest = const CarInput();
      _requiresNeutral = true;
    }
  }

  static int Function() _monotonicClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsedMicroseconds;
  }
}
