import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flame/components.dart';

import '../input/car_input.dart';
import '../tracks/track_definition.dart';

class RaceTrackLayout {
  static const worldWidth = 960.0;
  static const worldHeight = 640.0;
  static const island = Rect.fromLTWH(280, 214, 400, 212);
  static const walls = <(String, Rect)>[
    ('outer-top', Rect.fromLTWH(0, 0, worldWidth, 64)),
    ('outer-bottom', Rect.fromLTWH(0, 576, worldWidth, 64)),
    ('outer-left', Rect.fromLTWH(0, 64, 64, 512)),
    ('outer-right', Rect.fromLTWH(896, 64, 64, 512)),
    ('island', island),
  ];
}

class RaceConfig {
  const RaceConfig({
    this.worldWidth = RaceTrackLayout.worldWidth,
    this.worldHeight = RaceTrackLayout.worldHeight,
    this.maxSpeed = 200,
    this.reverseSpeedRatio = 0.5,
    this.turnRate = 2.4,
    // Short arcade ramps: 83 ms forward launch and 50 ms full-speed release.
    this.forwardAcceleration = 2400,
    this.reverseAcceleration = 1800,
    this.coastDeceleration = 4000,
    this.brakeDeceleration = 5000,
    this.directionChangeDeceleration = 4000,
    this.smoothSteering = false,
    this.steeringAcceleration = 12,
    this.steeringReturn = 16,
    this.vehicleRadius = 16,
    this.collisionEventThreshold = 18,
  });

  final double worldWidth;
  final double worldHeight;
  final double maxSpeed;
  final double reverseSpeedRatio;
  final double turnRate;
  final double forwardAcceleration;
  final double reverseAcceleration;
  final double coastDeceleration;
  final double brakeDeceleration;
  final double directionChangeDeceleration;
  final bool smoothSteering;
  final double steeringAcceleration;
  final double steeringReturn;
  final double vehicleRadius;
  final double collisionEventThreshold;

  double get maxReverseSpeed => maxSpeed * reverseSpeedRatio;

  double get fixedStep => 1 / 120;
  int get maxSubSteps => 8;
}

class CarState {
  CarState({required this.player, required Vector2 position, this.heading = 0})
    : position = position,
      previousPosition = position.clone(),
      renderPosition = position.clone(),
      velocity = Vector2.zero(),
      previousHeading = heading,
      renderHeading = heading;

  final PlayerId player;
  final Vector2 position;
  final Vector2 previousPosition;
  final Vector2 renderPosition;

  /// Signed speed along the car's heading. Positive is forward, negative reverse.
  double driveSpeed = 0;
  double previousDriveSpeed = 0;
  double steering = 0;
  final Vector2 velocity;
  double heading;
  double previousHeading;
  double renderHeading;

  double get speed => driveSpeed.abs();

  void syncVelocity() {
    velocity.setValues(
      math.cos(heading) * driveSpeed,
      math.sin(heading) * driveSpeed,
    );
  }

  void stop() {
    driveSpeed = 0;
    velocity.setZero();
  }

  void capturePreviousPose() {
    previousPosition.setFrom(position);
    previousHeading = heading;
    previousDriveSpeed = driveSpeed;
  }

  void updateRenderPose(double alpha) {
    final amount = alpha.clamp(0.0, 1.0).toDouble();
    renderPosition.setFrom(
      previousPosition + (position - previousPosition) * amount,
    );
    final fullTurn = math.pi * 2;
    final turn = (heading - previousHeading + math.pi) % fullTurn - math.pi;
    renderHeading = previousHeading + turn * amount;
  }

  void snapRenderPose() {
    previousPosition.setFrom(position);
    renderPosition.setFrom(position);
    previousHeading = heading;
    renderHeading = heading;
  }
}

enum CollisionType { vehicle, wall }

/// A new physical impact. [intensity] is normalized to the range [0, 1].
class CollisionEvent {
  CollisionEvent({
    required this.type,
    required List<PlayerId> players,
    required this.intensity,
    this.position,
    this.normal,
  }) : players = List.unmodifiable(players);

  final CollisionType type;
  final List<PlayerId> players;
  final double intensity;
  final Offset? position;
  final Offset? normal;
}

typedef SimulationStepListener = void Function(double stepSeconds);

class _CircleRectContact {
  const _CircleRectContact(this.normal, this.penetration);

  final Vector2 normal;
  final double penetration;
}

/// Owns all car movement and collision resolution in the fixed-step game loop.
class RaceSimulation {
  RaceSimulation({
    this.config = const RaceConfig(),
    this.track,
    Vector2? redStartPosition,
    Vector2? blueStartPosition,
  }) : _redStart =
           redStartPosition?.clone() ??
           Vector2(
             track?.redSpawn.position.x ?? 150,
             track?.redSpawn.position.y ?? 112,
           ),
       _blueStart =
           blueStartPosition?.clone() ??
           Vector2(
             track?.blueSpawn.position.x ?? 150,
             track?.blueSpawn.position.y ?? 166,
           ),
       red = CarState(
         player: PlayerId.red,
         position:
             redStartPosition?.clone() ??
             Vector2(
               track?.redSpawn.position.x ?? 150,
               track?.redSpawn.position.y ?? 112,
             ),
         heading: track?.redSpawn.heading ?? 0,
       ),
       blue = CarState(
         player: PlayerId.blue,
         position:
             blueStartPosition?.clone() ??
             Vector2(
               track?.blueSpawn.position.x ?? 150,
               track?.blueSpawn.position.y ?? 166,
             ),
         heading: track?.blueSpawn.heading ?? 0,
       );

  final RaceConfig config;
  final TrackDefinition? track;
  final Vector2 _redStart;
  final Vector2 _blueStart;
  final CarState red;
  final CarState blue;
  final _collisionEvents = StreamController<CollisionEvent>.broadcast(
    sync: true,
  );
  final Set<String> _activeContacts = {};
  final Set<PlayerId> _finishedPlayers = {};
  final List<SimulationStepListener> _stepListeners = [];
  double _accumulator = 0;
  bool isRunning = false;
  int _resetRevision = 0;
  int get resetRevision => _resetRevision;

  bool isPlayerFinished(PlayerId player) => _finishedPlayers.contains(player);

  void finishPlayer(PlayerId player) {
    _finishedPlayers.add(player);
    final car = player == PlayerId.red ? red : blue;
    car.stop();
    car.steering = 0;
    car.previousDriveSpeed = 0;
  }

  Stream<CollisionEvent> get collisionEvents => _collisionEvents.stream;

  void addStepListener(SimulationStepListener listener) {
    if (!_stepListeners.contains(listener)) _stepListeners.add(listener);
  }

  void removeStepListener(SimulationStepListener listener) {
    _stepListeners.remove(listener);
  }

  void setRunning(bool value) {
    isRunning = value;
    if (!value) {
      _accumulator = 0;
      red.stop();
      red.steering = 0;
      red.snapRenderPose();
      blue.stop();
      blue.steering = 0;
      blue.snapRenderPose();
    }
  }

  void reset() {
    _resetRevision++;
    red.position.setFrom(_redStart);
    red.stop();
    red.steering = 0;
    red.previousDriveSpeed = 0;
    red.heading = track?.redSpawn.heading ?? 0;
    red.snapRenderPose();
    blue.position.setFrom(_blueStart);
    blue.stop();
    blue.steering = 0;
    blue.previousDriveSpeed = 0;
    blue.heading = track?.blueSpawn.heading ?? 0;
    blue.snapRenderPose();
    _accumulator = 0;
    _activeContacts.clear();
    _finishedPlayers.clear();
    isRunning = false;
  }

  void update(
    double elapsed,
    InputSource inputSource, {
    void Function(double stepSeconds)? onFixedStep,
  }) {
    if (!isRunning || elapsed <= 0) return;
    _accumulator += math.min(elapsed, config.fixedStep * config.maxSubSteps);
    var steps = 0;
    while (isRunning &&
        _accumulator >= config.fixedStep &&
        steps < config.maxSubSteps) {
      _accumulator -= config.fixedStep;
      red.capturePreviousPose();
      blue.capturePreviousPose();
      _step(config.fixedStep, inputSource);
      for (final listener in _stepListeners) {
        listener(config.fixedStep);
      }
      steps++;
      onFixedStep?.call(config.fixedStep);
    }
    if (steps == config.maxSubSteps && _accumulator >= config.fixedStep) {
      _accumulator = 0;
    }
    updateRenderPoses();
  }

  void updateRenderPoses() {
    if (!isRunning) {
      red.snapRenderPose();
      blue.snapRenderPose();
      return;
    }
    final alpha = (_accumulator / config.fixedStep).clamp(0.0, 1.0).toDouble();
    red.updateRenderPose(alpha);
    blue.updateRenderPose(alpha);
  }

  void _step(double dt, InputSource inputSource) {
    if (!isPlayerFinished(PlayerId.red)) {
      _move(red, inputSource.inputFor(PlayerId.red), dt);
    }
    if (!isPlayerFinished(PlayerId.blue)) {
      _move(blue, inputSource.inputFor(PlayerId.blue), dt);
    }

    final contacts = <String>{};
    if (!isPlayerFinished(PlayerId.red)) _resolveWallContacts(red, contacts);
    if (!isPlayerFinished(PlayerId.blue)) _resolveWallContacts(blue, contacts);
    _resolveCars(contacts);
    _activeContacts
      ..clear()
      ..addAll(contacts);
  }

  void _move(CarState car, CarInput input, double dt) {
    if (input.emergencyStop) {
      car.stop();
      car.steering = 0;
      return;
    }

    final throttle = input.throttle.clamp(0.0, 1.0).toDouble();
    final reverse = input.reverse.clamp(0.0, 1.0).toDouble();
    final brake = input.brake.clamp(0.0, 1.0).toDouble();
    final targetSpeed = brake > 0
        ? 0.0
        : reverse > 0
        ? -config.maxReverseSpeed * reverse
        : config.maxSpeed * throttle;
    if (brake > 0) {
      car.driveSpeed = _moveToward(
        car.driveSpeed,
        0,
        config.brakeDeceleration * brake * dt,
      );
    } else if (car.driveSpeed != 0 &&
        targetSpeed != 0 &&
        car.driveSpeed.sign != targetSpeed.sign) {
      car.driveSpeed = _moveToward(
        car.driveSpeed,
        0,
        config.directionChangeDeceleration * dt,
      );
    } else {
      final accelerating = targetSpeed.abs() > car.driveSpeed.abs();
      final acceleration = accelerating
          ? targetSpeed < 0
                ? config.reverseAcceleration
                : config.forwardAcceleration
          : config.coastDeceleration;
      car.driveSpeed = _moveToward(
        car.driveSpeed,
        targetSpeed,
        acceleration * dt,
      );
    }
    if (car.driveSpeed.abs() < 0.01) car.driveSpeed = 0;

    final targetSteering = input.steering.clamp(-1.0, 1.0).toDouble();
    final returningToCenter =
        targetSteering == 0 ||
        (car.steering * targetSteering < 0 &&
            targetSteering.abs() < car.steering.abs());
    car.steering = !config.smoothSteering
        ? targetSteering
        : _moveToward(
            car.steering,
            targetSteering,
            (returningToCenter
                    ? config.steeringReturn
                    : config.steeringAcceleration) *
                dt,
          );
    if (car.driveSpeed.abs() > 0.01) {
      car.heading += car.steering * config.turnRate * car.driveSpeed.sign * dt;
    }
    car.syncVelocity();
    car.position.add(car.velocity * dt);
  }

  double _moveToward(double current, double target, double maxDelta) {
    if ((target - current).abs() <= maxDelta) return target;
    return current + (target - current).sign * maxDelta;
  }

  void _resolveWallContacts(CarState car, Set<String> contacts) {
    final radius = config.vehicleRadius;
    for (final wall in track?.walls ?? RaceTrackLayout.walls) {
      final contact = _circleRectContact(car.position, radius, wall.$2);
      if (contact == null) continue;
      final key = 'wall:${car.player.name}:${wall.$1}';
      contacts.add(key);
      if (contact.penetration > 0) {
        car.position.add(contact.normal * contact.penetration);
      }
      final incomingSpeed = -car.velocity.dot(contact.normal);
      if (incomingSpeed <= 0) continue;
      _emitNewContact(
        key,
        CollisionType.wall,
        [car.player],
        incomingSpeed / config.maxSpeed,
        incomingSpeed,
        position: Offset(
          car.position.x - contact.normal.x * radius,
          car.position.y - contact.normal.y * radius,
        ),
        normal: Offset(contact.normal.x, contact.normal.y),
      );
      car.stop();
    }
  }

  _CircleRectContact? _circleRectContact(
    Vector2 position,
    double radius,
    Rect rect,
  ) {
    final closestX = position.x.clamp(rect.left, rect.right).toDouble();
    final closestY = position.y.clamp(rect.top, rect.bottom).toDouble();
    final dx = position.x - closestX;
    final dy = position.y - closestY;
    final distance = math.sqrt(dx * dx + dy * dy);
    const contactSlop = 0.5;
    if (distance > radius + contactSlop) return null;
    if (distance > 0.0001) {
      return _CircleRectContact(
        Vector2(dx / distance, dy / distance),
        math.max(0, radius - distance),
      );
    }

    final edges = [
      (position.x - rect.left, Vector2(-1, 0)),
      (rect.right - position.x, Vector2(1, 0)),
      (position.y - rect.top, Vector2(0, -1)),
      (rect.bottom - position.y, Vector2(0, 1)),
    ];
    final nearest = edges.reduce((a, b) => a.$1 < b.$1 ? a : b);
    return _CircleRectContact(nearest.$2, nearest.$1 + radius);
  }

  void _resolveCars(Set<String> contacts) {
    if (isPlayerFinished(PlayerId.red) || isPlayerFinished(PlayerId.blue)) {
      return;
    }

    final delta = blue.position - red.position;
    final distance = delta.length;
    final minDistance = config.vehicleRadius * 2;
    const contactSlop = 0.5;
    if (distance > minDistance + contactSlop) return;

    final normal = distance > 0.0001 ? delta / distance : Vector2(1, 0);
    const key = 'vehicle:red:blue';
    contacts.add(key);
    final penetration = minDistance - distance;
    if (penetration > 0) {
      final correction = normal * (penetration / 2);
      red.position.sub(correction);
      blue.position.add(correction);
    }

    final redIncomingSpeed = red.velocity.dot(normal);
    final blueIncomingSpeed = -blue.velocity.dot(normal);
    final impactSpeed = redIncomingSpeed + blueIncomingSpeed;
    if (impactSpeed <= 0) return;
    _emitNewContact(
      key,
      CollisionType.vehicle,
      const [PlayerId.red, PlayerId.blue],
      impactSpeed / (config.maxSpeed * 2),
      impactSpeed,
      position: Offset(
        (red.position.x + blue.position.x) / 2,
        (red.position.y + blue.position.y) / 2,
      ),
      normal: Offset(normal.x, normal.y),
    );
    if (redIncomingSpeed > 0) red.stop();
    if (blueIncomingSpeed > 0) blue.stop();
  }

  void _emitNewContact(
    String key,
    CollisionType type,
    List<PlayerId> players,
    double intensity,
    double impactSpeed, {
    Offset? position,
    Offset? normal,
  }) {
    if (_activeContacts.contains(key) ||
        impactSpeed < config.collisionEventThreshold) {
      return;
    }
    _collisionEvents.add(
      CollisionEvent(
        type: type,
        players: players,
        intensity: intensity.clamp(0.0, 1.0).toDouble(),
        position: position,
        normal: normal,
      ),
    );
  }

  void dispose() {
    _stepListeners.clear();
    _collisionEvents.close();
  }
}
