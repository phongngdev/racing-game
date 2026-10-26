import 'dart:math' as math;
import 'dart:ui';

import 'track_definition.dart';
import 'track_geometry.dart';

/// Increment whenever a generator change can alter geometry for a seed.
const sprintGeneratorVersion = 1;
const sprintMaximumWallRectangles = 128;
const sprintMaximumGenerationAttempts = 32;
const sprintMaximumSearchNodesPerAttempt = 1024;

class SprintTrackGenerationException implements Exception {
  const SprintTrackGenerationException({
    required this.seed,
    required this.reason,
    required this.attempts,
    required this.searchNodes,
  });

  final String seed;
  final String reason;
  final int attempts;
  final int searchNodes;

  @override
  String toString() =>
      'Could not generate Sprint track for seed "$seed" '
      '(generator v$sprintGeneratorVersion, attempts: $attempts, '
      'search nodes: $searchNodes): $reason';
}

class SprintTrackGeneration {
  const SprintTrackGeneration({
    required this.track,
    required this.seed,
    required this.attempts,
    required this.searchNodes,
    required this.elapsed,
  });

  final TrackDefinition track;
  final String seed;
  final int attempts;
  final int searchNodes;
  final Duration elapsed;

  int get generatorVersion => sprintGeneratorVersion;
  String get fingerprint => sprintTrackFingerprint(track);
}

/// Stable across Dart VM and Web: hashes UTF-16 code units with 32-bit wrap.
String normalizeSprintSeed(String input) {
  final seed = input.trim();
  if (seed.isEmpty) throw const FormatException('Seed cannot be empty.');
  if (seed.length > 64) {
    throw const FormatException('Seed must be at most 64 characters.');
  }
  return seed;
}

int sprintSeedHash(String input) {
  final seed = normalizeSprintSeed(input);
  var hash = 5381;
  for (final codeUnit in seed.codeUnits) {
    hash = ((hash * 33) + codeUnit) & 0xffffffff;
  }
  return hash;
}

/// A small explicit xorshift32 PRNG; its sequence is part of generator v1.
class _SprintRandom {
  _SprintRandom(int seed) : _state = seed == 0 ? 0x6d2b79f5 : seed;
  int _state;

  int nextUint32() {
    var value = _state;
    value = (value ^ (value << 13)) & 0xffffffff;
    value = value ^ (value >>> 17);
    value = (value ^ (value << 5)) & 0xffffffff;
    _state = value;
    return value;
  }

  int nextInt(int maximum) => nextUint32() % maximum;
}

/// Generates one complete, validated Sprint corridor before a race starts.
class SprintTrackGenerator {
  const SprintTrackGenerator();

  SprintTrackGeneration generate(String inputSeed) {
    final stopwatch = Stopwatch()..start();
    final seed = normalizeSprintSeed(inputSeed);
    final random = _SprintRandom(sprintSeedHash(seed));
    var searchNodes = 0;
    var lastReason = 'No route met the length and geometry constraints.';

    for (
      var attempt = 1;
      attempt <= sprintMaximumGenerationAttempts;
      attempt++
    ) {
      final segmentCount = 8 + random.nextInt(5);
      final lengths = List<int>.generate(
        segmentCount,
        (_) => 500 + random.nextInt(6) * 100,
      );
      final routeLength = lengths.fold<int>(0, (sum, length) => sum + length);
      // gridStation is 60 and finishStation is 100 before the route endpoint.
      final raceLength = routeLength - 160;
      if (raceLength < 5000 || raceLength > 9000) {
        lastReason = 'Generated route length $raceLength is outside 5000–9000.';
        continue;
      }

      final directions = <int>[random.nextInt(4)];
      final points = <TrackPoint>[const TrackPoint(0, 0)];
      final roads = <Rect>[];
      final attemptNodes = [0];
      if (!_searchRoute(
        index: 0,
        lengths: lengths,
        directions: directions,
        points: points,
        roads: roads,
        random: random,
        nodes: attemptNodes,
      )) {
        searchNodes += attemptNodes[0];
        lastReason = 'Bounded route search found no non-intersecting layout.';
        continue;
      }
      searchNodes += attemptNodes[0];

      try {
        final roadHalf = 100.0;
        final minX = points.map((point) => point.x).reduce(math.min);
        final maxX = points.map((point) => point.x).reduce(math.max);
        final minY = points.map((point) => point.y).reduce(math.min);
        final maxY = points.map((point) => point.y).reduce(math.max);
        const margin = 240.0;
        final offsetX = margin - minX;
        final offsetY = margin - minY;
        final translated = points
            .map((point) => TrackPoint(point.x + offsetX, point.y + offsetY))
            .toList(growable: false);
        final bounds = Rect.fromLTRB(
          0,
          0,
          maxX - minX + margin * 2,
          maxY - minY + margin * 2,
        );
        final track = TrackDefinition.corridor(
          id: 'sprint-v$sprintGeneratorVersion:$seed',
          worldBounds: bounds,
          centerline: translated,
          roadWidth: roadHalf * 2,
          seed: seed,
          generatorVersion: sprintGeneratorVersion,
        );
        if (track.walls.length > sprintMaximumWallRectangles) {
          lastReason =
              'Generated ${track.walls.length} wall rectangles; limit is '
              '$sprintMaximumWallRectangles.';
          continue;
        }
        if (!_hasRequiredClearance(track)) {
          lastReason = 'Spawn or route lacks required vehicle clearance.';
          continue;
        }
        stopwatch.stop();
        return SprintTrackGeneration(
          track: track,
          seed: seed,
          attempts: attempt,
          searchNodes: searchNodes,
          elapsed: stopwatch.elapsed,
        );
      } on ArgumentError catch (error) {
        lastReason = error.message?.toString() ?? error.toString();
      }
    }
    stopwatch.stop();
    throw SprintTrackGenerationException(
      seed: seed,
      reason: lastReason,
      attempts: sprintMaximumGenerationAttempts,
      searchNodes: searchNodes,
    );
  }

  bool _searchRoute({
    required int index,
    required List<int> lengths,
    required List<int> directions,
    required List<TrackPoint> points,
    required List<Rect> roads,
    required _SprintRandom random,
    required List<int> nodes,
  }) {
    if (index == lengths.length) return true;
    if (nodes[0] >= sprintMaximumSearchNodesPerAttempt) return false;

    final direction = directions[index];
    final start = points.last;
    final length = lengths[index].toDouble();
    final end = switch (direction) {
      0 => TrackPoint(start.x + length, start.y),
      1 => TrackPoint(start.x, start.y + length),
      2 => TrackPoint(start.x - length, start.y),
      _ => TrackPoint(start.x, start.y - length),
    };
    final road = Rect.fromLTRB(
      math.min(start.x, end.x) - 100,
      math.min(start.y, end.y) - 100,
      math.max(start.x, end.x) + 100,
      math.max(start.y, end.y) + 100,
    );
    for (var previous = 0; previous < roads.length - 1; previous++) {
      if (roads[previous].inflate(16).overlaps(road.inflate(16))) return false;
    }

    nodes[0]++;
    roads.add(road);
    points.add(end);
    if (index == lengths.length - 1) return true;

    final firstTurn = random.nextInt(2) == 0 ? 3 : 1;
    for (final turn in [firstTurn, 4 - firstTurn]) {
      if (nodes[0] >= sprintMaximumSearchNodesPerAttempt) break;
      directions.add((direction + turn) % 4);
      if (_searchRoute(
        index: index + 1,
        lengths: lengths,
        directions: directions,
        points: points,
        roads: roads,
        random: random,
        nodes: nodes,
      )) {
        return true;
      }
      directions.removeLast();
    }
    points.removeLast();
    roads.removeLast();
    return false;
  }

  bool _hasRequiredClearance(TrackDefinition track) {
    if (!track.isDrivable(track.redSpawn.position, radius: 32) ||
        !track.isDrivable(track.blueSpawn.position, radius: 32)) {
      return false;
    }
    for (var segment = 0; segment < track.centerline.length - 1; segment++) {
      final a = track.centerline[segment];
      final b = track.centerline[segment + 1];
      final length = track.stations[segment + 1] - track.stations[segment];
      for (var sample = 0; sample <= length ~/ 32; sample++) {
        if (!track.isDrivable(
          a.lerpTo(b, math.min(1, sample * 32 / length)),
          radius: 32,
        )) {
          return false;
        }
      }
    }
    return true;
  }
}

/// Canonical geometry digest for golden tests and reproducible bug reports.
String sprintTrackFingerprint(TrackDefinition track) {
  return _fingerprint(track, includeIdentity: true);
}

/// Geometry-only digest for measuring diversity across different seed labels.
String sprintGeometryFingerprint(TrackDefinition track) =>
    _fingerprint(track, includeIdentity: false);

String _fingerprint(TrackDefinition track, {required bool includeIdentity}) {
  String n(double value) => value.toStringAsFixed(3);
  String point(TrackPoint value) => '${n(value.x)},${n(value.y)}';
  String rect(Rect value) =>
      '${n(value.left)},${n(value.top)},${n(value.right)},${n(value.bottom)}';
  final values = <String>[
    'generator=${track.generatorVersion ?? 0}',
    if (includeIdentity) 'seed=${track.seed ?? ""}',
    if (includeIdentity) 'id=${track.id}',
    'bounds=${rect(track.worldBounds)}',
    'width=${n(track.roadWidth)}',
    for (final center in track.centerline) 'center=${point(center)}',
    for (final road in track.roadRects) 'road=${rect(road)}',
    for (final wall in track.walls) 'wall=${wall.$1}:${rect(wall.$2)}',
    'red=${point(track.redSpawn.position)}:${n(track.redSpawn.heading)}',
    'blue=${point(track.blueSpawn.position)}:${n(track.blueSpawn.heading)}',
    'start=${track.start.direction.name}:${point(track.start.start)}:${point(track.start.end)}',
    for (var i = 0; i < track.checkpoints.length; i++)
      'checkpoint=${track.checkpoints[i].id}:${track.checkpoints[i].direction.name}:'
          '${point(track.checkpoints[i].start)}:${point(track.checkpoints[i].end)}:'
          '${n(track.checkpointStations[i])}',
    'finish=${track.finish.direction.name}:${point(track.finish.start)}:'
        '${point(track.finish.end)}:${n(track.finishStation)}',
  ];
  var hash = 5381;
  for (final codeUnit in values.join('|').codeUnits) {
    hash = ((hash * 33) + codeUnit) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
