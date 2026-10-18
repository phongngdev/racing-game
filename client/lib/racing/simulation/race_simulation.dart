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
    this.maxSpeed = 260,
    this.acceleration = 180,
    this.braking = 360,
    this.naturalDeceleration = 70,
    this.turnRate = 2.4,
    this.lateralGrip = 5,
    this.vehicleRadius = 16,
    this.collisionEventThreshold = 18,
  });

  final double worldWidth;
  final double worldHeight;
  final double maxSpeed;
  final double acceleration;
  final double braking;
  final double naturalDeceleration;
  final double turnRate;
  final double lateralGrip;
  final double vehicleRadius;
  final double collisionEventThreshold;

  double get fixedStep => 1 / 120;
  int get maxSubSteps => 8;
}

class CarState {
  CarState({required this.player, required this.position, this.heading = 0})
    : velocity = Vector2.zero();

  final PlayerId player;
  final Vector2 position;
  final Vector2 velocity;
  double heading;

  double get speed => velocity.length;
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

/// Owns all car movement and collision resolution in the fixed-step game loop.
class RaceSimulation {
  RaceSimulation({this.config = const RaceConfig()})
    : red = CarState(player: PlayerId.red, position: Vector2(150, 112)),
      blue = CarState(player: PlayerId.blue, position: Vector2(150, 166));

  final RaceConfig config;
  final CarState red;
  final CarState blue;
  final _collisionEvents = StreamController<CollisionEvent>.broadcast(
    sync: true,
  );
  final Set<String> _activeContacts = {};
  double _accumulator = 0;
  bool isRunning = false;

  Stream<CollisionEvent> get collisionEvents => _collisionEvents.stream;

  void setRunning(bool value) {
    isRunning = value;
    if (!value) _accumulator = 0;
  }

  void reset() {
    red.position.setValues(150, 112);
    red.velocity.setZero();
    red.heading = 0;
    blue.position.setValues(150, 166);
    blue.velocity.setZero();
    blue.heading = 0;
    _accumulator = 0;
    _activeContacts.clear();
    isRunning = false;
  }

  void update(double elapsed, InputSource inputSource) {
    if (!isRunning || elapsed <= 0) return;
    _accumulator += math.min(elapsed, config.fixedStep * config.maxSubSteps);
    var steps = 0;
    while (_accumulator >= config.fixedStep && steps < config.maxSubSteps) {
      _step(config.fixedStep, inputSource);
      _accumulator -= config.fixedStep;
      steps++;
    }
    if (steps == config.maxSubSteps && _accumulator >= config.fixedStep) {
      _accumulator = 0;
    }
  }

  void _step(double dt, InputSource inputSource) {
    _move(red, inputSource.inputFor(PlayerId.red), dt);
    _move(blue, inputSource.inputFor(PlayerId.blue), dt);

    final contacts = <String>{};
    _resolveWallContacts(red, contacts);
    _resolveWallContacts(blue, contacts);
    _resolveCars(contacts);
    _activeContacts
      ..clear()
      ..addAll(contacts);
  }

  void _move(CarState car, CarInput input, double dt) {
    final forward = Vector2(math.cos(car.heading), math.sin(car.heading));
    final lateral = Vector2(-forward.y, forward.x);
    final forwardSpeed = car.velocity.dot(forward);
    final lateralSpeed = car.velocity.dot(lateral);
    final steeringSpeed = (forwardSpeed.abs() / config.maxSpeed)
        .clamp(0.0, 1.0)
        .toDouble();
    final direction = forwardSpeed < -1 ? -1.0 : 1.0;
    car.heading +=
        input.steering.clamp(-1.0, 1.0) *
        config.turnRate *
        steeringSpeed *
        direction *
        dt;

    final throttle = input.throttle.clamp(0.0, 1.0);
    final brake = input.brake.clamp(0.0, 1.0);
    if (brake > 0) {
      _applyDeceleration(car.velocity, config.braking * brake * dt);
    } else if (throttle > 0) {
      car.velocity.add(forward * (config.acceleration * throttle * dt));
    } else {
      _applyDeceleration(car.velocity, config.naturalDeceleration * dt);
    }

    if (lateralSpeed.abs() > 0.01) {
      car.velocity.add(lateral * (-lateralSpeed * config.lateralGrip * dt));
    }
    final speed = car.velocity.length;
    if (speed > config.maxSpeed) car.velocity.scale(config.maxSpeed / speed);
    car.position.add(car.velocity * dt);
  }

  void _applyDeceleration(Vector2 velocity, double amount) {
    final speed = velocity.length;
    if (speed <= amount || speed == 0) {
      velocity.setZero();
    } else {
      velocity.scale((speed - amount) / speed);
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
      car.velocity.add(contact.normal * (incomingSpeed * 1.18));
      _emitNewContact(
        key,
        CollisionType.wall,
        [car.player],
        incomingSpeed / config.maxSpeed,
        incomingSpeed,
      );
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

    final relativeSpeed = (blue.velocity - red.velocity).dot(normal);
    if (relativeSpeed >= 0) return;
    final impactSpeed = -relativeSpeed;
    final impulse = (1.25 * impactSpeed) / 2;
    red.velocity.sub(normal * impulse);
    blue.velocity.add(normal * impulse);
    _emitNewContact(
      key,
      CollisionType.vehicle,
      const [PlayerId.red, PlayerId.blue],
      impactSpeed / (config.maxSpeed * 2),
      impactSpeed,
    );
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
}
