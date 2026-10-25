import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flame/components.dart';

import '../input/car_input.dart';

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
    // this.maxSpeed = 260,
    this.maxSpeed = 200,
    this.reverseSpeedRatio = 0.5,
    this.turnRate = 2.4,
    this.vehicleRadius = 16,
    this.collisionEventThreshold = 18,
  });

  final double worldWidth;
  final double worldHeight;
  final double maxSpeed;
  final double reverseSpeedRatio;
  final double turnRate;
  final double vehicleRadius;
  final double collisionEventThreshold;

  double get maxReverseSpeed => maxSpeed * reverseSpeedRatio;

  double get fixedStep => 1 / 120;
  int get maxSubSteps => 8;
}

class CarState {
  CarState({required this.player, required this.position, this.heading = 0})
    : velocity = Vector2.zero();

  final PlayerId player;
  final Vector2 position;

  /// Signed speed along the car's heading. Positive is forward, negative reverse.
  double driveSpeed = 0;
  final Vector2 velocity;
  double heading;

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
}

enum CollisionType { vehicle, wall }

/// A new physical impact. [intensity] is normalized to the range [0, 1].
class CollisionEvent {
  CollisionEvent({
    required this.type,
    required List<PlayerId> players,
    required this.intensity,
  }) : players = List.unmodifiable(players);

  final CollisionType type;
  final List<PlayerId> players;
  final double intensity;
}

class _CircleRectContact {
  const _CircleRectContact(this.normal, this.penetration);

  final Vector2 normal;
  final double penetration;
}

class _DirectionTransition {
  _DirectionTransition({required this.startSpeed, required this.targetSpeed});

  final double startSpeed;
  double targetSpeed;
  double elapsed = 0;
}

/// Owns all car movement and collision resolution in the fixed-step game loop.
class RaceSimulation {
  RaceSimulation({
    this.config = const RaceConfig(),
    Vector2? redStartPosition,
    Vector2? blueStartPosition,
  }) : _redStart = redStartPosition?.clone() ?? Vector2(150, 112),
       _blueStart = blueStartPosition?.clone() ?? Vector2(150, 166),
       red = CarState(
         player: PlayerId.red,
         position: redStartPosition?.clone() ?? Vector2(150, 112),
       ),
       blue = CarState(
         player: PlayerId.blue,
         position: blueStartPosition?.clone() ?? Vector2(150, 166),
       );

  final RaceConfig config;
  final Vector2 _redStart;
  final Vector2 _blueStart;
  final CarState red;
  final CarState blue;
  final _collisionEvents = StreamController<CollisionEvent>.broadcast(
    sync: true,
  );
  final Set<String> _activeContacts = {};
  final Map<PlayerId, _DirectionTransition> _directionTransitions = {};
  final Set<PlayerId> _finishedPlayers = {};
  double _accumulator = 0;
  bool isRunning = false;

  bool isPlayerFinished(PlayerId player) => _finishedPlayers.contains(player);

  void finishPlayer(PlayerId player) {
    _finishedPlayers.add(player);
    (player == PlayerId.red ? red : blue).stop();
    _directionTransitions.remove(player);
  }

  Stream<CollisionEvent> get collisionEvents => _collisionEvents.stream;

  void setRunning(bool value) {
    isRunning = value;
    if (!value) {
      _accumulator = 0;
      red.stop();
      blue.stop();
      _directionTransitions.clear();
    }
  }

  void reset() {
    red.position.setFrom(_redStart);
    red.stop();
    red.heading = 0;
    blue.position.setFrom(_blueStart);
    blue.stop();
    blue.heading = 0;
    _accumulator = 0;
    _activeContacts.clear();
    _directionTransitions.clear();
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
      _step(config.fixedStep, inputSource);
      steps++;
      onFixedStep?.call(config.fixedStep);
    }
    if (steps == config.maxSubSteps && _accumulator >= config.fixedStep) {
      _accumulator = 0;
    }
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
    final throttle = input.throttle.clamp(0.0, 1.0).toDouble();
    final reverse = input.reverse.clamp(0.0, 1.0).toDouble();
    final brake = input.brake.clamp(0.0, 1.0).toDouble();
    final targetSpeed = brake > 0
        ? 0.0
        : reverse > 0
        ? -config.maxReverseSpeed * reverse
        : config.maxSpeed * throttle;
    _updateDriveSpeed(car, targetSpeed, dt);

    if (car.driveSpeed.abs() > 0.01) {
      car.heading +=
          input.steering.clamp(-1.0, 1.0) *
          config.turnRate *
          car.driveSpeed.sign *
          dt;
    }
    car.syncVelocity();
    car.position.add(car.velocity * dt);
  }

  void _updateDriveSpeed(CarState car, double targetSpeed, double dt) {
    if (targetSpeed == 0) {
      _directionTransitions.remove(car.player);
      car.driveSpeed = 0;
      return;
    }

    final isChangingDirection =
        car.driveSpeed != 0 && car.driveSpeed.sign != targetSpeed.sign;
    if (!isChangingDirection) {
      _directionTransitions.remove(car.player);
      car.driveSpeed = targetSpeed;
      return;
    }

    final transition = _directionTransitions.putIfAbsent(
      car.player,
      () => _DirectionTransition(
        startSpeed: car.driveSpeed,
        targetSpeed: targetSpeed,
      ),
    );
    transition.targetSpeed = targetSpeed;
    transition.elapsed = math.min(
      _directionChangeDuration,
      transition.elapsed + dt,
    );
    final progress = transition.elapsed / _directionChangeDuration;
    if (progress >= 1) {
      car.driveSpeed = transition.targetSpeed;
      _directionTransitions.remove(car.player);
    } else {
      car.driveSpeed = transition.startSpeed * (1 - progress);
    }
  }

  void _resolveWallContacts(CarState car, Set<String> contacts) {
    final radius = config.vehicleRadius;
    for (final wall in RaceTrackLayout.walls) {
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
    );
    if (redIncomingSpeed > 0) red.stop();
    if (blueIncomingSpeed > 0) blue.stop();
  }

  void _emitNewContact(
    String key,
    CollisionType type,
    List<PlayerId> players,
    double intensity,
    double impactSpeed,
  ) {
    if (_activeContacts.contains(key) ||
        impactSpeed < config.collisionEventThreshold) {
      return;
    }
    _collisionEvents.add(
      CollisionEvent(
        type: type,
        players: players,
        intensity: intensity.clamp(0.0, 1.0).toDouble(),
      ),
    );
  }

  void dispose() => _collisionEvents.close();

  static const _directionChangeDuration = 0.15;
}
