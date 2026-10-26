import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset, Paint, PaintingStyle, Rect, StrokeCap;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../input/car_input.dart';
import '../simulation/race_simulation.dart';

/// Presentation tuning only; simulation and controller units are untouched.
class RaceEffectsConfig {
  const RaceEffectsConfig({
    this.maximumDust = 144,
    this.maximumImpacts = 96,
    this.maximumSkids = 256,
    this.edgeClearance = 22,
    this.edgeDustPeriod = 1 / 24,
    this.launchDustPeriod = 1 / 18,
    this.brakingDustPeriod = 1 / 28,
    this.dustRadius = 5.5,
    this.dustLifetime = 0.65,
    this.skidMinimumSpeed = 45,
    this.skidLifetime = 8,
    this.skidWidth = 3.6,
    this.skidAlpha = 210,
    this.impactLifetime = 0.32,
    this.finishLifetime = 1,
  });

  final int maximumDust, maximumImpacts, maximumSkids, skidAlpha;
  final double edgeClearance,
      edgeDustPeriod,
      launchDustPeriod,
      brakingDustPeriod;
  final double dustRadius, dustLifetime, skidMinimumSpeed, skidLifetime;
  final double skidWidth, impactLifetime, finishLifetime;
}

/// One world-owned visual-effects store shared by every camera rendering it.
class RaceEffectsComponent extends Component {
  RaceEffectsComponent({
    required RaceSimulation simulation,
    required InputSource inputSource,
    required List<Rect> drivableWalls,
    bool enabled = true,
    bool useKenneyVehicleGeometry = false,
    this.config = const RaceEffectsConfig(),
  }) : _simulation = simulation,
       _drivableWalls = List.unmodifiable(drivableWalls),
       _lastResetRevision = simulation.resetRevision {
    _inputSource = inputSource;
    _enabled = enabled;
    _useKenneyVehicleGeometry = useKenneyVehicleGeometry;
    _stepListener = _onSimulationStep;
    _simulation.addStepListener(_stepListener);
    _collisionSubscription = _simulation.collisionEvents.listen(_onCollision);
    _finished[PlayerId.red] = simulation.isPlayerFinished(PlayerId.red);
    _finished[PlayerId.blue] = simulation.isPlayerFinished(PlayerId.blue);
  }

  static const _cellSize = 128.0;
  final RaceEffectsConfig config;
  late final Component overlay = _RaceEffectsOverlay(this);
  int get _maximumDust => config.maximumDust;
  int get _maximumImpacts => config.maximumImpacts;
  int get _maximumSkids => config.maximumSkids;
  double get _skidLifetime => config.skidLifetime;

  final RaceSimulation _simulation;
  late final InputSource _inputSource;
  final List<Rect> _drivableWalls;
  final List<_EffectParticle> _dust = [];
  final List<_EffectParticle> _impacts = [];
  final List<_FinishPulse> _finishPulses = [];
  final List<_ImpactFlash> _flashes = [];
  final List<_SkidMark> _skids = [];
  final Map<(int, int), List<_SkidMark>> _skidCells = {};
  final Map<PlayerId, double> _dustElapsed = {
    PlayerId.red: 0,
    PlayerId.blue: 0,
  };
  final Map<PlayerId, Offset?> _lastLeftWheel = {
    PlayerId.red: null,
    PlayerId.blue: null,
  };
  final Map<PlayerId, Offset?> _lastRightWheel = {
    PlayerId.red: null,
    PlayerId.blue: null,
  };
  final Map<PlayerId, bool> _finished = {};
  final Map<PlayerId, int> _dustMode = {};
  final Paint _dustPaint = Paint()..isAntiAlias = true;
  final Paint _impactPaint = Paint()
    ..isAntiAlias = true
    ..strokeCap = StrokeCap.round;
  final Paint _skidPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _finishPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke;

  late final SimulationStepListener _stepListener;
  late final StreamSubscription<CollisionEvent> _collisionSubscription;
  late bool _enabled;
  late bool _useKenneyVehicleGeometry;
  bool _clockAdvances = true;
  int _lastResetRevision;
  int _nextSkidId = 0;
  int _particleSequence = 0;
  final Map<PlayerId, double> _leftWheelDistance = {
    PlayerId.red: 0,
    PlayerId.blue: 0,
  };
  final Map<PlayerId, double> _rightWheelDistance = {
    PlayerId.red: 0,
    PlayerId.blue: 0,
  };

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    clear();
  }

  set useKenneyVehicleGeometry(bool value) {
    if (_useKenneyVehicleGeometry == value) return;
    _useKenneyVehicleGeometry = value;
    clear();
  }

  set clockAdvances(bool value) => _clockAdvances = value;

  int get dustCount => _dust.length;
  int get impactCount => _impacts.length;
  int get skidCount => _skids.length;
  int get finishCount => _finishPulses.length;
  int get flashCount => _flashes.length;
  bool get enabled => _enabled;

  @visibleForTesting
  List<(Offset, Offset)> get skidSegmentsForTesting => [
    for (final mark in _skids) (mark.start, mark.end),
  ];

  void clear() {
    _dust.clear();
    _impacts.clear();
    _finishPulses.clear();
    _flashes.clear();
    _skids.clear();
    _skidCells.clear();
    for (final player in PlayerId.values) {
      _dustElapsed[player] = 0;
      _dustMode[player] = 0;
      _lastLeftWheel[player] = null;
      _lastRightWheel[player] = null;
      _leftWheelDistance[player] = 0;
      _rightWheelDistance[player] = 0;
      _finished[player] = _simulation.isPlayerFinished(player);
    }
    _lastResetRevision = _simulation.resetRevision;
  }

  void _onSimulationStep(double dt) {
    if (!_enabled) return;
    for (final car in [_simulation.red, _simulation.blue]) {
      final input = _inputSource.inputFor(car.player);
      _emitBrakeSkid(car, input);
      _emitDrivingDust(car, input, dt);
    }
  }

  void _emitBrakeSkid(CarState car, CarInput input) {
    final previousSpeed = car.previousDriveSpeed;
    final reversing =
        previousSpeed > config.skidMinimumSpeed && input.reverse > 0 ||
        previousSpeed < -config.skidMinimumSpeed && input.throttle > 0;
    final braking =
        input.brake >= 0.5 && previousSpeed.abs() >= config.skidMinimumSpeed;
    if (input.emergencyStop ||
        _simulation.isPlayerFinished(car.player) ||
        (!braking && !reversing)) {
      _lastLeftWheel[car.player] = null;
      _lastRightWheel[car.player] = null;
      _leftWheelDistance[car.player] = 0;
      _rightWheelDistance[car.player] = 0;
      return;
    }

    final previousLeft = _rearWheel(
      Offset(car.previousPosition.x, car.previousPosition.y),
      car.previousHeading,
      -_rearWheelHalfTrack,
    );
    final previousRight = _rearWheel(
      Offset(car.previousPosition.x, car.previousPosition.y),
      car.previousHeading,
      _rearWheelHalfTrack,
    );
    final currentPosition = Offset(car.position.x, car.position.y);
    final currentLeft = _rearWheel(
      currentPosition,
      car.heading,
      -_rearWheelHalfTrack,
    );
    final currentRight = _rearWheel(
      currentPosition,
      car.heading,
      _rearWheelHalfTrack,
    );
    _emitWheelMark(
      car.player,
      currentLeft,
      previousLeft,
      _lastLeftWheel,
      _leftWheelDistance,
    );
    _emitWheelMark(
      car.player,
      currentRight,
      previousRight,
      _lastRightWheel,
      _rightWheelDistance,
    );
  }

  void _emitWheelMark(
    PlayerId player,
    Offset current,
    Offset previous,
    Map<PlayerId, Offset?> lastWheel,
    Map<PlayerId, double> accumulatedDistance,
  ) {
    final anchor = lastWheel[player] ?? previous;
    final distance = (current - anchor).distance;
    if (distance >= 1 && _skids.length < _maximumSkids) {
      _addSkid(anchor, current);
      lastWheel[player] = current;
      accumulatedDistance[player] = 0;
    } else {
      accumulatedDistance[player] =
          (accumulatedDistance[player] ?? 0) + (current - previous).distance;
      if (accumulatedDistance[player]! >= 1) {
        if (_skids.length < _maximumSkids) _addSkid(anchor, current);
        lastWheel[player] = current;
        accumulatedDistance[player] = 0;
      } else {
        lastWheel[player] ??= anchor;
      }
    }
  }

  void _emitDrivingDust(CarState car, CarInput input, double dt) {
    if (input.emergencyStop ||
        _simulation.isPlayerFinished(car.player) ||
        (car.speed < 12 && car.previousDriveSpeed.abs() < 45)) {
      _dustElapsed[car.player] = 0;
      _dustMode[car.player] = 0;
      return;
    }
    final position = Offset(car.position.x, car.position.y);
    var nearestDistance = double.infinity;
    var nearestPoint = position;
    for (final wall in _drivableWalls) {
      final point = Offset(
        position.dx.clamp(wall.left, wall.right).toDouble(),
        position.dy.clamp(wall.top, wall.bottom).toDouble(),
      );
      final distance = (point - position).distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestPoint = point;
      }
    }
    final nearEdge =
        car.speed >= 35 &&
        nearestDistance > 0 &&
        nearestDistance <=
            _simulation.config.vehicleRadius + config.edgeClearance;
    final accelerating =
        (car.speed - car.previousDriveSpeed.abs()) / dt > 100 &&
        (input.throttle > 0 || input.reverse > 0);
    final braking =
        car.speed > 0 &&
        car.previousDriveSpeed.abs() >= 45 &&
        (car.previousDriveSpeed.abs() - car.speed) / dt >= 2000;
    final mode = braking
        ? 3
        : nearEdge
        ? 2
        : accelerating
        ? 1
        : 0;
    if (mode == 0) {
      _dustElapsed[car.player] = 0;
      _dustMode[car.player] = 0;
      return;
    }

    final period = mode == 3
        ? config.brakingDustPeriod
        : mode == 2
        ? config.edgeDustPeriod
        : config.launchDustPeriod;
    final accumulated = (_dustElapsed[car.player] ?? 0) + dt;
    final burstStarted = mode > (_dustMode[car.player] ?? 0);
    _dustMode[car.player] = mode;
    if (!burstStarted && accumulated < period) {
      _dustElapsed[car.player] = accumulated;
      return;
    }
    _dustElapsed[car.player] = burstStarted ? 0 : accumulated % period;
    final towardWall = nearEdge
        ? (nearestPoint - position) / nearestDistance
        : Offset.zero;
    final direction = Offset(math.cos(car.heading), math.sin(car.heading));
    final travelSign = car.driveSpeed == 0
        ? car.previousDriveSpeed.sign
        : car.driveSpeed.sign;
    final rear = _rearWheel(position, car.heading, 0);
    final count = mode == 3
        ? 4
        : mode == 2
        ? 3
        : 2;
    for (var index = 0; index < count; index++) {
      final side = index - (count - 1) / 2;
      final lateral = Offset(-direction.dy, direction.dx);
      _addDust(
        rear + towardWall * 4 + lateral * (side * 5),
        towardWall * 15 - direction * (travelSign * 24) + lateral * (side * 10),
        color: nearEdge ? const Color(0xFFE0CBA3) : const Color(0xFFD1D3C4),
      );
    }
  }

  void _onCollision(CollisionEvent event) {
    if (!_enabled || event.position == null) return;
    final point = event.position!;
    final normal = event.normal ?? const Offset(0, -1);
    final tangent = Offset(-normal.dy, normal.dx);
    if (_flashes.length >= 8) _flashes.removeAt(0);
    _flashes.add(_ImpactFlash(point, event.intensity));
    for (var side = -2; side <= 2; side++) {
      _addDust(
        point + tangent * (side * 2),
        normal * 24 + tangent * (side * 10),
      );
    }
    final count = 8 + (event.intensity * 8).round();
    for (var index = 0; index < count; index++) {
      final sequence = _particleSequence++;
      final spread = ((sequence * 37) % 101) / 100 - 0.5;
      final angle = math.atan2(normal.dy, normal.dx) + spread * 3.8;
      final direction = Offset(math.cos(angle), math.sin(angle));
      _addImpact(
        point,
        direction * (70 + 90 * event.intensity),
        size: 3 + event.intensity * 2.5,
        lifetime: config.impactLifetime + event.intensity * 0.14,
      );
    }
    for (final player in event.players) {
      final car = player == PlayerId.red ? _simulation.red : _simulation.blue;
      if (car.previousDriveSpeed.abs() >= config.skidMinimumSpeed) {
        _addCollisionSkids(car);
      }
    }
  }

  void _addCollisionSkids(CarState car) {
    if (_skids.length + 2 > _maximumSkids) return;
    final direction = Offset(math.cos(car.heading), math.sin(car.heading));
    final left = _rearWheel(
      Offset(car.position.x, car.position.y),
      car.heading,
      -_rearWheelHalfTrack,
    );
    final right = _rearWheel(
      Offset(car.position.x, car.position.y),
      car.heading,
      _rearWheelHalfTrack,
    );
    final travel = direction * (car.previousDriveSpeed.sign * 10);
    _addSkid(left - travel, left);
    _addSkid(right - travel, right);
  }

  void _addDust(
    Offset position,
    Offset velocity, {
    Color color = const Color(0xFFE0CBA3),
  }) {
    if (_dust.length >= _maximumDust) _dust.removeAt(0);
    final sequence = _particleSequence++;
    _dust.add(
      _EffectParticle(
        position: position,
        velocity: velocity,
        size: config.dustRadius + (sequence % 4) * 0.8,
        lifetime: config.dustLifetime + (sequence % 3) * 0.07,
        color: color,
      ),
    );
  }

  void _addImpact(
    Offset position,
    Offset velocity, {
    required double size,
    required double lifetime,
    Color color = const Color(0xFFFFDA70),
  }) {
    if (_impacts.length >= _maximumImpacts) _impacts.removeAt(0);
    _impacts.add(
      _EffectParticle(
        position: position,
        velocity: velocity,
        size: size,
        lifetime: lifetime,
        color: color,
      ),
    );
  }

  void _addSkid(Offset start, Offset end) {
    final mark = _SkidMark(
      id: _nextSkidId++,
      start: start,
      end: end,
      bounds: Rect.fromPoints(start, end).inflate(2),
    );
    _skids.add(mark);
    final firstColumn = _cell(mark.bounds.left);
    final lastColumn = _cell(mark.bounds.right);
    final firstRow = _cell(mark.bounds.top);
    final lastRow = _cell(mark.bounds.bottom);
    for (var column = firstColumn; column <= lastColumn; column++) {
      for (var row = firstRow; row <= lastRow; row++) {
        (_skidCells[(column, row)] ??= <_SkidMark>[]).add(mark);
      }
    }
  }

  Offset _rearWheel(Offset center, double heading, double side) =>
      center +
      Offset(-math.cos(heading), -math.sin(heading)) * _rearAxleOffset +
      Offset(-math.sin(heading), math.cos(heading)) * side;

  double get _rearAxleOffset => _useKenneyVehicleGeometry ? 12 : 9;
  double get _rearWheelHalfTrack => _useKenneyVehicleGeometry ? 5.5 : 11.5;

  int _cell(double coordinate) => (coordinate / _cellSize).floor();

  @override
  void update(double dt) {
    advanceEffects(dt);
    super.update(dt);
  }

  @visibleForTesting
  void advanceEffects(double dt) {
    if (_lastResetRevision != _simulation.resetRevision) clear();
    if (_clockAdvances) {
      final activeDt = dt.clamp(0.0, 0.05).toDouble();
      for (var index = _dust.length - 1; index >= 0; index--) {
        _dust[index].advance(activeDt);
        if (_dust[index].age >= _dust[index].lifetime) {
          _dust.removeAt(index);
        }
      }
      for (var index = _impacts.length - 1; index >= 0; index--) {
        _impacts[index].advance(activeDt);
        if (_impacts[index].age >= _impacts[index].lifetime) {
          _impacts.removeAt(index);
        }
      }
      _finishPulses.removeWhere((pulse) {
        pulse.age += activeDt;
        return pulse.age >= pulse.lifetime;
      });
      _flashes.removeWhere((flash) {
        flash.age += activeDt;
        return flash.age >= 0.28;
      });
      _expireSkids(activeDt);
      if (_enabled) _updateFinishPulses();
    }
  }

  void _updateFinishPulses() {
    for (final player in PlayerId.values) {
      final finished = _simulation.isPlayerFinished(player);
      if (finished && !(_finished[player] ?? false)) {
        final car = player == PlayerId.red ? _simulation.red : _simulation.blue;
        _finishPulses.add(
          _FinishPulse(
            position: Offset(car.position.x, car.position.y),
            lifetime: config.finishLifetime,
            color: player == PlayerId.red
                ? const Color(0xFFFF777C)
                : const Color(0xFF78B2FF),
          ),
        );
        for (var index = 0; index < 18; index++) {
          final angle = index * math.pi * 2 / 18;
          _addImpact(
            Offset(car.position.x, car.position.y),
            Offset(math.cos(angle), math.sin(angle)) * (65 + index % 3 * 18),
            size: 3.5,
            lifetime: config.finishLifetime * 0.9,
            color: index.isEven
                ? const Color(0xFFFFE381)
                : player == PlayerId.red
                ? const Color(0xFFFF8991)
                : const Color(0xFF8CCBFF),
          );
        }
        if (_finishPulses.length > 4) _finishPulses.removeAt(0);
      }
      _finished[player] = finished;
    }
  }

  void _expireSkids(double dt) {
    for (var index = _skids.length - 1; index >= 0; index--) {
      final mark = _skids[index];
      mark.age += dt;
      if (mark.age < _skidLifetime) continue;
      _skids.removeAt(index);
      for (
        var column = _cell(mark.bounds.left);
        column <= _cell(mark.bounds.right);
        column++
      ) {
        for (
          var row = _cell(mark.bounds.top);
          row <= _cell(mark.bounds.bottom);
          row++
        ) {
          final key = (column, row);
          final cell = _skidCells[key];
          cell?.remove(mark);
          if (cell?.isEmpty == true) _skidCells.remove(key);
        }
      }
    }
  }

  @override
  void render(ui.Canvas canvas) {
    if (!_enabled) return;
    final visible = CameraComponent.currentCamera?.visibleWorldRect;
    if (visible == null) return;
    _renderSkids(canvas, visible);
    _renderParticles(canvas, visible, _dust, isDust: true);
  }

  void _renderOverlay(ui.Canvas canvas) {
    if (!_enabled) return;
    final visible = CameraComponent.currentCamera?.visibleWorldRect;
    if (visible == null) return;
    _renderParticles(canvas, visible, _impacts, isDust: false);
    for (final flash in _flashes) {
      if (!visible.inflate(40).contains(flash.position)) continue;
      final progress = flash.age / 0.28;
      final radius = 8 + progress * (22 + flash.intensity * 12);
      _dustPaint.color = Color.fromARGB(
        ((1 - progress) * 110).round(),
        255,
        245,
        205,
      );
      canvas.drawCircle(flash.position, radius * 0.65, _dustPaint);
      _finishPaint
        ..color = Color.fromARGB(((1 - progress) * 245).round(), 255, 220, 115)
        ..strokeWidth = 3.5 * (1 - progress * 0.7);
      canvas.drawCircle(flash.position, radius, _finishPaint);
    }
    for (final pulse in _finishPulses) {
      if (!visible.inflate(90).contains(pulse.position)) continue;
      final progress = pulse.age / pulse.lifetime;
      final radius = 22 + progress * 58;
      final alpha = ((1 - progress) * 235).round().clamp(0, 255);
      _finishPaint
        ..color = pulse.color.withAlpha(alpha)
        ..strokeWidth = 4 * (1 - progress * 0.5);
      canvas.drawCircle(pulse.position, radius, _finishPaint);
      for (var index = 0; index < 12; index++) {
        final angle = index * math.pi / 6 + progress * 0.5;
        final direction = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(
          pulse.position + direction * (radius + 5),
          pulse.position + direction * (radius + 14),
          _finishPaint,
        );
      }
    }
  }

  void _renderSkids(ui.Canvas canvas, Rect visible) {
    final visited = <int>{};
    for (
      var column = _cell(visible.left);
      column <= _cell(visible.right);
      column++
    ) {
      for (var row = _cell(visible.top); row <= _cell(visible.bottom); row++) {
        for (final mark in _skidCells[(column, row)] ?? const <_SkidMark>[]) {
          if (!visited.add(mark.id) || !visible.overlaps(mark.bounds)) continue;
          final fade = (1 - mark.age / _skidLifetime).clamp(0.0, 1.0);
          _skidPaint
            ..color = Color.fromARGB(
              (fade * config.skidAlpha).round(),
              12,
              17,
              22,
            )
            ..strokeWidth = config.skidWidth;
          canvas.drawLine(mark.start, mark.end, _skidPaint);
        }
      }
    }
  }

  void _renderParticles(
    ui.Canvas canvas,
    Rect visible,
    List<_EffectParticle> particles, {
    required bool isDust,
  }) {
    for (final particle in particles) {
      if (!visible.inflate(particle.size * 2 + 8).contains(particle.position)) {
        continue;
      }
      final remaining = (1 - particle.age / particle.lifetime).clamp(0.0, 1.0);
      final alpha = (remaining * (isDust ? 170 : 255)).round().clamp(0, 255);
      if (isDust) {
        _dustPaint.color = particle.color.withAlpha(alpha);
        canvas.drawCircle(
          particle.position,
          particle.size * (1 + (1 - remaining) * 0.7),
          _dustPaint,
        );
      } else {
        _impactPaint
          ..color = particle.color.withAlpha(alpha)
          ..strokeWidth = particle.size;
        canvas.drawLine(
          particle.position,
          particle.position - particle.velocity * 0.055,
          _impactPaint,
        );
      }
    }
  }

  @override
  void onRemove() {
    _simulation.removeStepListener(_stepListener);
    unawaited(_collisionSubscription.cancel());
    super.onRemove();
  }
}

class _EffectParticle {
  _EffectParticle({
    required this.position,
    required this.velocity,
    required this.size,
    required this.lifetime,
    required this.color,
  });

  Offset position;
  final Offset velocity;
  final double size;
  final double lifetime;
  final Color color;
  double age = 0;

  void advance(double dt) {
    age += dt;
    position += velocity * dt;
  }
}

class _FinishPulse {
  _FinishPulse({
    required this.position,
    required this.color,
    required this.lifetime,
  });

  final Offset position;
  final Color color;
  final double lifetime;
  double age = 0;
}

class _ImpactFlash {
  _ImpactFlash(this.position, this.intensity);
  final Offset position;
  final double intensity;
  double age = 0;
}

/// Stateless foreground pass: all spawning, lifetime and pools stay in one store.
class _RaceEffectsOverlay extends Component {
  _RaceEffectsOverlay(this.effects);
  final RaceEffectsComponent effects;

  @override
  void render(ui.Canvas canvas) => effects._renderOverlay(canvas);
}

class _SkidMark {
  _SkidMark({
    required this.id,
    required this.start,
    required this.end,
    required this.bounds,
  });

  final int id;
  final Offset start;
  final Offset end;
  final Rect bounds;
  double age = 0;
}
