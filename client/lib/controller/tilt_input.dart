import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

class TiltInput {
  TiltInput({
    required this.onSteering,
    required this.onUnavailable,
    int Function()? clockMicros,
    this.calibrationDuration = const Duration(milliseconds: 500),
    this.sampleTimeout = const Duration(milliseconds: 200),
  }) : _clockMicros = clockMicros ?? _monotonicClock();

  final void Function(double steering) onSteering;
  final void Function() onUnavailable;
  final int Function() _clockMicros;
  final Duration calibrationDuration;
  final Duration sampleTimeout;

  StreamSubscription<AccelerometerEvent>? _subscription;
  Completer<bool>? _calibration;
  int? _calibrationStartedAt;
  int? _lastSampleAt;
  int _calibrationSamples = 0;
  double _sinTotal = 0;
  double _cosTotal = 0;
  double? _centerRadians;
  double _filteredRadians = 0;
  int? _lastFilterAt;
  double _steering = 0;

  bool get isCalibrated => _centerRadians != null;
  bool get hasFreshSample =>
      _lastSampleAt != null &&
      _clockMicros() - _lastSampleAt! <= sampleTimeout.inMicroseconds;
  double get steering => hasFreshSample ? _steering : 0;

  Future<void> start({Stream<AccelerometerEvent>? events}) async {
    await stop();
    _lastSampleAt = null;
    _centerRadians = null;
    try {
      _subscription =
          (events ??
                  accelerometerEventStream(
                    samplingPeriod: const Duration(milliseconds: 20),
                  ))
              .listen(_handleSample, onError: (_) => _handleError());
    } catch (_) {
      _handleError();
    }
  }

  Future<bool> calibrate() {
    if (!hasFreshSample) return Future.value(false);
    final completer = Completer<bool>();
    _calibration = completer;
    _calibrationStartedAt = _clockMicros();
    _calibrationSamples = 0;
    _sinTotal = 0;
    _cosTotal = 0;
    return completer.future;
  }

  void _handleSample(AccelerometerEvent event) {
    final now = _clockMicros();
    _lastSampleAt = now;
    // With portrait-natural Android devices locked to landscape, a roll moves
    // gravity between the device's x axis and the screen-normal z axis. The
    // sign is checked on the target phone during setup.
    final angle = math.atan2(event.z, event.x);
    final calibration = _calibration;
    final startedAt = _calibrationStartedAt;
    if (calibration != null && startedAt != null) {
      _sinTotal += math.sin(angle);
      _cosTotal += math.cos(angle);
      _calibrationSamples++;
      if (now - startedAt >= calibrationDuration.inMicroseconds &&
          _calibrationSamples >= 15) {
        _centerRadians = math.atan2(_sinTotal, _cosTotal);
        _filteredRadians = 0;
        _lastFilterAt = now;
        _calibration = null;
        _calibrationStartedAt = null;
        calibration.complete(true);
      }
      return;
    }
    final center = _centerRadians;
    if (center == null) {
      onSteering(0);
      return;
    }

    final delta = _wrapRadians(angle - center);
    final previous = _lastFilterAt;
    final elapsed = previous == null
        ? 0.02
        : ((now - previous) / Duration.microsecondsPerSecond).clamp(0.0, 0.2);
    _lastFilterAt = now;
    final alpha = 1 - math.exp(-elapsed / 0.08);
    _filteredRadians += alpha * _wrapRadians(delta - _filteredRadians);
    final absoluteDegrees = _filteredRadians.abs() * 180 / math.pi;
    if (absoluteDegrees <= 3) {
      _steering = 0;
    } else {
      final normalized = ((absoluteDegrees - 3) / 27).clamp(0.0, 1.0);
      _steering = _filteredRadians.isNegative ? -normalized : normalized;
    }
    onSteering(_steering);
  }

  void _handleError() {
    markUnavailable();
    onUnavailable();
  }

  void markUnavailable() {
    _lastSampleAt = null;
    _steering = 0;
    _centerRadians = null;
    _filteredRadians = 0;
    _lastFilterAt = null;
    _calibration?.complete(false);
    _calibration = null;
    _calibrationStartedAt = null;
    onSteering(0);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _calibration?.complete(false);
    _calibration = null;
    _calibrationStartedAt = null;
    _lastSampleAt = null;
    _steering = 0;
    onSteering(0);
  }

  static double _wrapRadians(double value) {
    while (value > math.pi) {
      value -= math.pi * 2;
    }
    while (value < -math.pi) {
      value += math.pi * 2;
    }
    return value;
  }

  static int Function() _monotonicClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsedMicroseconds;
  }
}
