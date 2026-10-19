import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

typedef VibrationPlayer = Future<void> Function({
  required int duration,
  int? amplitude,
});

enum VibrationResult { played, unsupported, failed, ignored }

/// Sends short phone motor vibrations for collisions and local diagnostics.
class CollisionHaptics {
  CollisionHaptics({
    Future<bool> Function()? hasVibrator,
    Future<bool> Function()? hasAmplitudeControl,
    VibrationPlayer? vibrate,
    Future<void> Function()? cancel,
    void Function(String message)? log,
    DateTime Function()? clock,
  }) : _hasVibrator = hasVibrator ?? Vibration.hasVibrator,
       _hasAmplitudeControl =
           hasAmplitudeControl ?? Vibration.hasAmplitudeControl,
       _vibrate =
           vibrate ??
           (({required int duration, int? amplitude}) => Vibration.vibrate(
             duration: duration,
             amplitude: amplitude ?? -1,
           )),
       _cancel = cancel ?? Vibration.cancel,
       _log = log ?? debugPrint,
       _clock = clock ?? DateTime.now;

  final Future<bool> Function() _hasVibrator;
  final Future<bool> Function() _hasAmplitudeControl;
  final VibrationPlayer _vibrate;
  final Future<void> Function() _cancel;
  final void Function(String message) _log;
  final DateTime Function() _clock;

  Future<bool>? _availability;
  DateTime? _lastCollisionAt;
  int _operation = 0;

  Future<VibrationResult> playForSession({
    required bool foreground,
    required int? currentGeneration,
    required int? eventGeneration,
    bool Function()? isStillCurrent,
  }) {
    if (!foreground ||
        currentGeneration == null ||
        eventGeneration != currentGeneration) {
      return Future.value(VibrationResult.ignored);
    }

    final now = _clock();
    final lastCollisionAt = _lastCollisionAt;
    if (lastCollisionAt != null &&
        now.difference(lastCollisionAt) < const Duration(milliseconds: 250)) {
      return Future.value(VibrationResult.ignored);
    }
    _lastCollisionAt = now;
    return _play(
      reason: 'collision',
      isEligible: () =>
          foreground &&
          currentGeneration == eventGeneration &&
          (isStillCurrent?.call() ?? true),
    );
  }

  Future<VibrationResult> test({required bool foreground}) =>
      _play(reason: 'manual test', isEligible: () => foreground);

  Future<VibrationResult> _play({
    required String reason,
    required bool Function() isEligible,
  }) async {
    if (!isEligible()) return VibrationResult.ignored;
    final operation = _operation;
    try {
      bool supported;
      try {
        supported = await (_availability ??= _hasVibrator());
      } catch (_) {
        _availability = null;
        rethrow;
      }
      if (operation != _operation || !isEligible()) {
        return VibrationResult.ignored;
      }
      if (!supported) {
        _log('[ApexRC] Vibration unavailable on this device.');
        return VibrationResult.unsupported;
      }

      var hasAmplitudeControl = false;
      try {
        hasAmplitudeControl = await _hasAmplitudeControl();
      } catch (error) {
        _log('[ApexRC] Could not check vibration amplitude support: $error');
      }
      if (operation != _operation || !isEligible()) {
        return VibrationResult.ignored;
      }
      if (hasAmplitudeControl) {
        try {
          await _vibrate(duration: 80, amplitude: 180);
        } catch (error) {
          _log(
            '[ApexRC] Vibration amplitude call failed; retrying default: $error',
          );
          if (operation != _operation || !isEligible()) {
            return VibrationResult.ignored;
          }
          await _vibrate(duration: 80);
        }
      } else {
        await _vibrate(duration: 80);
      }
      _log('[ApexRC] Vibration motor called ($reason, 80 ms).');
      return VibrationResult.played;
    } catch (error) {
      _log('[ApexRC] Vibration call failed ($reason): $error');
      return VibrationResult.failed;
    }
  }

  Future<void> cancel() async {
    _operation++;
    try {
      await _cancel();
    } catch (error) {
      _log('[ApexRC] Could not cancel vibration: $error');
    }
  }
}
