import 'dart:math' as math;
import 'dart:ui';

import '../lap/lap_race_track.dart';
import '../simulation/race_simulation.dart';
import '../tracks/track_definition.dart';
import 'race_scenery_data.dart';

/// Builds deterministic decorative layouts from existing track geometry.
/// This module does not call or consume the Sprint generator's random source.
abstract final class RaceSceneryLayout {
  static const _filterMargin = 2.0;
  static const _roadClearance = 22.0;
  static const _gateClearance = 22.0;
  static const _spriteGap = 8.0;

  static List<RaceSceneryPlacement> sprint(TrackDefinition track) {
    final salt = _trackHash(track);
    final gates = <TrackGate>[track.start, ...track.checkpoints, track.finish];
    final builder = _LayoutBuilder(
      gates: gates,
      isSafe: (bounds) =>
          _containsRect(track.worldBounds, bounds) &&
          !track.roadRects.any(
            (road) => road.inflate(_roadClearance).overlaps(bounds),
          ),
    );

    _addEventClusters(track, builder);
    for (var corner = 1; corner < track.centerline.length - 1; corner++) {
      _addCornerCluster(track, builder, corner);
    }

    final routeLength = track.stations.last;
    final naturalBudget = (routeLength * 24 / 1000).ceil();
    final skippedCluster = _mix(salt, 0x91) % 4;
    final clusters = <(int, double)>[];
    var clusterIndex = 0;
    for (var station = 120.0; station < routeLength - 60; station += 240) {
      if (clusterIndex % 4 != skippedCluster) {
        clusters.add((clusterIndex, station));
      }
      clusterIndex++;
    }
    final perClusterBudget = clusters.isEmpty
        ? 0
        : (naturalBudget / clusters.length).ceil();
    var naturalCount = 0;
    for (final (clusterIndex, station) in clusters) {
      var clusterCount = 0;
      final frame = _frameAt(track, station);
      final archetype = _mix(salt, clusterIndex * 17 + 3) % 3;
      final tangentOffsets = const [-102.0, -34.0, 34.0, 102.0];
      for (var side = -1; side <= 1; side += 2) {
        final kinds = _natureCluster(archetype, side, clusterIndex);
        for (var item = 0; item < kinds.length; item++) {
          if (clusterCount >= perClusterBudget ||
              naturalCount >= naturalBudget) {
            break;
          }
          final kind = kinds[item];
          final variation = _mix(salt, clusterIndex * 131 + item * 19 + side);
          final lateral =
              track.roadWidth / 2 +
              math.max(kind.width, kind.height) / 2 +
              _roadClearance +
              18;
          final center =
              frame.point +
              frame.tangent * tangentOffsets[item] +
              frame.normal * (side * lateral);
          final rotation = frame.heading + ((variation % 9) - 4) * math.pi / 32;
          if (builder.add(
            kind,
            center,
            rotation: rotation,
            area: 'nature',
            isSafe: builder.isSafe,
            filterMargin: _filterMargin,
            gap: _spriteGap,
          )) {
            naturalCount++;
            clusterCount++;
          }
        }
      }

      // A second, looser vegetation line gives each roadside cluster depth.
      // Its wider offset and smaller props keep shadows away from the kerb.
      for (var side = -1; side <= 1; side += 2) {
        final kinds = _outerNatureCluster(archetype, side, clusterIndex);
        for (var item = 0; item < kinds.length; item++) {
          if (clusterCount >= perClusterBudget ||
              naturalCount >= naturalBudget) {
            break;
          }
          final kind = kinds[item];
          final variation = _mix(
            salt,
            clusterIndex * 149 + item * 23 + side + 7,
          );
          final lateral =
              track.roadWidth / 2 +
              math.max(kind.width, kind.height) / 2 +
              _roadClearance +
              94;
          final center =
              frame.point +
              frame.tangent * tangentOffsets[item] +
              frame.normal * (side * lateral);
          final rotation = frame.heading + ((variation % 9) - 4) * math.pi / 32;
          if (builder.add(
            kind,
            center,
            rotation: rotation,
            area: 'nature',
            isSafe: builder.isSafe,
            filterMargin: _filterMargin,
            gap: _spriteGap,
          )) {
            naturalCount++;
            clusterCount++;
          }
        }
      }
    }

    // A route too close to its world bounds can reject scenery safely. Keep
    // those gaps while retaining deterministic geometry and density budgets.
    return builder.finish();
  }

  static List<RaceSceneryPlacement> lap() {
    final gates = <TrackGate>[
      LapRaceTrack.standard.finish,
      ...LapRaceTrack.standard.checkpoints,
    ];
    final island = RaceTrackLayout.island.deflate(26);
    final outerWallRegions = <Rect>[
      const Rect.fromLTWH(12, 12, 936, 40),
      const Rect.fromLTWH(12, 588, 936, 40),
      const Rect.fromLTWH(12, 76, 40, 488),
      const Rect.fromLTWH(908, 76, 40, 488),
    ];
    final builder = _LayoutBuilder(gates: gates, isSafe: (_) => false);

    final islandBudget = (island.width * island.height / 1800).ceil();
    var islandCount = 0;
    bool addIsland(_SceneryKind kind, Offset center, {double rotation = 0}) {
      if (islandCount >= islandBudget) return false;
      final added = builder.add(
        kind,
        center,
        rotation: rotation,
        area: 'lapIsland',
        isSafe: (bounds) => _containsRect(island, bounds),
        filterMargin: _filterMargin,
        gap: 2,
      );
      if (added) islandCount++;
      return added;
    }

    // A small race-facility centerpiece gives the infield a clear identity.
    addIsland(
      _kind('tribune_full', width: 100, height: 50),
      const Offset(480, 326),
    );

    final islandKinds = <_SceneryKind>[
      _kind('tree_small', width: 32, height: 32),
      _kind('tree_large', width: 34, height: 34),
      _kind('rock1', width: 31, height: 25),
      _kind('rock2', width: 30, height: 28),
      _kind('rock3', width: 32, height: 25),
      _kind('tent_red', width: 34, height: 34),
      _kind('tent_blue', width: 34, height: 34),
      _kind('tires_red_alt', width: 28, height: 28),
      _kind('barrel_red', width: 28, height: 28),
    ];
    var cellIndex = 0;
    for (final y in const <double>[260, 320, 380]) {
      for (final x in const <double>[326, 370, 414, 458, 502, 546, 590, 634]) {
        final rank = _mix(0x4c415031, cellIndex++);
        final kind = islandKinds[rank % islandKinds.length];
        final rotation = ((rank >>> 8) % 4) * math.pi / 2;
        addIsland(kind, Offset(x, y), rotation: rotation);
        if (islandCount >= islandBudget) break;
      }
      if (islandCount >= islandBudget) break;
    }

    final outerArea =
        RaceTrackLayout.worldWidth * RaceTrackLayout.worldHeight - 832 * 512;
    final outerBudget = (outerArea / 5000).ceil();
    var outerCount = 0;
    final outerKinds = <_SceneryKind>[
      _kind('cone_straight'),
      _kind('cone_down'),
      _kind('barrel_blue'),
      _kind('barrel_red'),
      _kind('tires_white_alt'),
      _kind('tires_red'),
      _kind('arrow_yellow', width: 28, height: 17),
      _kind('arrow_white', width: 28, height: 17),
    ];
    bool addOuter(Offset center, int index, double rotation) {
      if (outerCount >= outerBudget) return false;
      final kind = outerKinds[_mix(0x4f555445, index) % outerKinds.length];
      for (final region in outerWallRegions) {
        final added = builder.add(
          kind,
          center,
          rotation: rotation,
          area: 'lapWall',
          isSafe: (bounds) => _containsRect(region, bounds),
          filterMargin: _filterMargin,
          gap: _spriteGap,
        );
        if (added) {
          outerCount++;
          return true;
        }
      }
      return false;
    }

    var edgeIndex = 0;
    for (var x = 52.0; x <= 888; x += 76) {
      addOuter(Offset(x, 32), edgeIndex++, 0);
      addOuter(Offset(x, 608), edgeIndex++, math.pi);
    }
    for (var y = 100.0; y <= 540; y += 76) {
      addOuter(Offset(32, y), edgeIndex++, -math.pi / 2);
      addOuter(Offset(928, y), edgeIndex++, math.pi / 2);
    }
    return builder.finish();
  }

  static void _addEventClusters(TrackDefinition track, _LayoutBuilder builder) {
    final lastSegment = track.centerline.length - 2;
    for (var event = 0; event < 2; event++) {
      final isStart = event == 0;
      final gate = isStart ? track.start : track.finish;
      final segment = isStart ? 0 : lastSegment;
      final frame = _frameForSegment(track, segment);
      final direction = isStart ? 1.0 : -1.0;
      for (var side = -1; side <= 1; side += 2) {
        final structure = side > 0
            ? _kind('tribune_full', width: 160, height: 80)
            : _kind('tribune_overhang_striped', width: 160, height: 52);
        final tent = side > 0
            ? _kind('tent_blue_large', width: 70, height: 70)
            : _kind('tent_red_large', width: 70, height: 70);
        final barrier = side > 0
            ? _kind('barrier_red_race', width: 132, height: 39)
            : _kind('barrier_white_race', width: 132, height: 39);
        final items = <(double, double, _SceneryKind)>[
          (200, 184, structure),
          (390, 185, barrier),
          (560, 190, tent),
          (
            710,
            185,
            _kind(
              side > 0 ? 'light_yellow' : 'light_white',
              width: 22,
              height: 53,
            ),
          ),
          (
            840,
            185,
            _kind(side > 0 ? 'tires_red' : 'barrel_red', width: 28, height: 28),
          ),
        ];
        for (var index = 0; index < items.length; index++) {
          final (along, lateral, kind) = items[index];
          final center =
              _gateCenter(gate) +
              frame.tangent * (along * direction) +
              frame.normal * (side * lateral);
          builder.add(
            kind,
            center,
            rotation: frame.heading,
            area: 'startFinish',
            isSafe: builder.isSafe,
            filterMargin: _filterMargin,
            gap: _spriteGap,
          );
        }
      }
      for (var side = -1; side <= 1; side += 2) {
        final center = _gateCenter(gate) + frame.normal * (side * 285);
        builder.add(
          _kind('lights', width: 54, height: 22),
          center,
          rotation: frame.heading,
          area: 'startFinish',
          isSafe: builder.isSafe,
          filterMargin: _filterMargin,
          gap: _spriteGap,
        );
      }
    }
  }

  static void _addCornerCluster(
    TrackDefinition track,
    _LayoutBuilder builder,
    int cornerIndex,
  ) {
    final previous = track.centerline[cornerIndex - 1];
    final corner = track.centerline[cornerIndex];
    final next = track.centerline[cornerIndex + 1];
    final incoming = _direction(previous, corner);
    final outgoing = _direction(corner, next);
    final cross = incoming.dx * outgoing.dy - incoming.dy * outgoing.dx;
    final outsideSide = cross > 0 ? -1.0 : 1.0;
    final normal = Offset(-outgoing.dy, outgoing.dx);
    final centerline = Offset(corner.x, corner.y);
    final lateral = track.roadWidth / 2 + _roadClearance + 44;
    final outgoingHeading = math.atan2(outgoing.dy, outgoing.dx);
    final chevronRotation = outgoingHeading + math.pi / 2;
    final decorations = <(double, _SceneryKind, double)>[
      (-78, _kind('arrow_yellow', width: 42, height: 25), chevronRotation),
      (-18, _kind('arrow_white', width: 42, height: 25), chevronRotation),
      (54, _kind('tires_red_alt', width: 30, height: 30), outgoingHeading),
      (112, _kind('cone_down', width: 27, height: 26), outgoingHeading),
    ];
    for (var index = 0; index < decorations.length; index++) {
      final (along, kind, rotation) = decorations[index];
      builder.add(
        kind,
        centerline + outgoing * along + normal * (outsideSide * lateral),
        rotation: rotation,
        area: 'corner',
        isSafe: builder.isSafe,
        filterMargin: _filterMargin,
        gap: _spriteGap,
      );
    }
  }

  static List<_SceneryKind> _natureCluster(
    int archetype,
    int side,
    int clusterIndex,
  ) {
    return switch (archetype) {
      0 => <_SceneryKind>[
        _kind('tree_large', width: 62, height: 61),
        _kind('tree_small', width: 46, height: 46),
        _kind(clusterIndex.isEven ? 'rock1' : 'rock3', width: 38, height: 31),
        _kind('tree_small', width: 40, height: 40),
      ],
      1 => <_SceneryKind>[
        _kind('tent_blue_large', width: 70, height: 70),
        _kind(side > 0 ? 'tent_red' : 'tent_blue', width: 42, height: 42),
        _kind(side > 0 ? 'barrel_red' : 'barrel_blue', width: 29, height: 29),
        _kind('tree_small', width: 42, height: 42),
      ],
      _ => <_SceneryKind>[
        _kind('tree_small', width: 43, height: 43),
        _kind('rock2', width: 34, height: 32),
        _kind('rock3', width: 37, height: 29),
        _kind(
          clusterIndex.isEven ? 'rock1' : 'tires_white_alt',
          width: 36,
          height: 30,
        ),
      ],
    };
  }

  static List<_SceneryKind> _outerNatureCluster(
    int archetype,
    int side,
    int clusterIndex,
  ) {
    return switch (archetype) {
      0 => <_SceneryKind>[
        _kind('tree_small', width: 38, height: 38),
        _kind('rock2', width: 30, height: 28),
        _kind('tree_small', width: 34, height: 34),
        _kind('rock3', width: 31, height: 24),
      ],
      1 => <_SceneryKind>[
        _kind(side > 0 ? 'tent_red' : 'tent_blue', width: 36, height: 36),
        _kind('tree_small', width: 34, height: 34),
        _kind(side > 0 ? 'barrel_red' : 'barrel_blue', width: 28, height: 28),
        _kind('tires_white_alt', width: 28, height: 28),
      ],
      _ => <_SceneryKind>[
        _kind('rock1', width: 32, height: 26),
        _kind('rock3', width: 31, height: 24),
        _kind('tree_small', width: 36, height: 36),
        _kind(
          clusterIndex.isEven ? 'rock2' : 'tires_red',
          width: 30,
          height: 28,
        ),
      ],
    };
  }

  static _RouteFrame _frameAt(TrackDefinition track, double station) {
    var index = 0;
    while (index < track.stations.length - 2 &&
        station > track.stations[index + 1]) {
      index++;
    }
    final a = track.centerline[index];
    final b = track.centerline[index + 1];
    final tangent = _direction(a, b);
    final point =
        Offset(a.x, a.y) + tangent * (station - track.stations[index]);
    return _RouteFrame(
      point: point,
      tangent: tangent,
      normal: Offset(-tangent.dy, tangent.dx),
      heading: math.atan2(tangent.dy, tangent.dx),
    );
  }

  static _RouteFrame _frameForSegment(TrackDefinition track, int segment) =>
      _frameAt(
        track,
        (track.stations[segment] + track.stations[segment + 1]) / 2,
      );

  static Offset _gateCenter(TrackGate gate) =>
      Offset((gate.start.x + gate.end.x) / 2, (gate.start.y + gate.end.y) / 2);

  static Rect _gateBounds(TrackGate gate) => Rect.fromPoints(
    Offset(gate.start.x, gate.start.y),
    Offset(gate.end.x, gate.end.y),
  );

  static Offset _direction(TrackPoint start, TrackPoint end) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final length = math.sqrt(dx * dx + dy * dy);
    return Offset(dx / length, dy / length);
  }

  static bool _containsRect(Rect outer, Rect inner) =>
      outer.contains(inner.topLeft) && outer.contains(inner.bottomRight);

  static int _trackHash(TrackDefinition track) {
    var hash = _hashString('${track.seed ?? track.id}|${track.roadWidth}');
    for (final point in track.centerline) {
      hash = _hashString('${point.x},${point.y}', seed: hash);
    }
    return hash;
  }

  static int _hashString(String value, {int seed = 0x811c9dc5}) {
    var hash = seed;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  static int _mix(int seed, int value) =>
      ((seed ^ (value * 0x9e3779b9)) * 0x85ebca6b) & 0xffffffff;

  static _SceneryKind _kind(String name, {double? width, double? height}) {
    final dimensions = switch (name) {
      'tree_large' => (64.0, 63.0),
      'tree_small' => (46.0, 46.0),
      'rock1' => (38.0, 31.0),
      'rock2' => (34.0, 32.0),
      'rock3' => (37.0, 29.0),
      'tent_blue_large' || 'tent_red_large' => (76.0, 76.0),
      'tent_blue' || 'tent_red' => (44.0, 44.0),
      'tribune_full' || 'tribune_empty' => (168.0, 84.0),
      'tribune_overhang_striped' => (140.0, 45.0),
      'barrier_red_race' || 'barrier_white_race' => (150.0, 44.0),
      'arrow_yellow' || 'arrow_white' => (44.0, 26.0),
      'lights' => (54.0, 22.0),
      'light_white' || 'light_yellow' => (25.0, 60.0),
      'cone_straight' || 'cone_down' => (28.0, 27.0),
      _ => (30.0, 30.0),
    };
    return _SceneryKind(
      'scenery/$name.png',
      width ?? dimensions.$1,
      height ?? dimensions.$2,
    );
  }
}

class _LayoutBuilder {
  _LayoutBuilder({required this.gates, required this.isSafe});

  final List<TrackGate> gates;
  final bool Function(Rect bounds) isSafe;
  final List<RaceSceneryPlacement> _placements = [];

  bool add(
    _SceneryKind kind,
    Offset center, {
    double rotation = 0,
    required String area,
    bool Function(Rect bounds)? isSafe,
    required double filterMargin,
    required double gap,
  }) {
    final placement = RaceSceneryPlacement(
      assetKey: kind.assetKey,
      center: center,
      spriteWidth: kind.width,
      spriteHeight: kind.height,
      rotation: rotation,
      area: area,
      filterMargin: filterMargin,
    );
    if (!(isSafe ?? this.isSafe)(placement.cullBounds) ||
        gates.any(
          (gate) =>
              RaceSceneryLayout._gateBounds(gate)
                  .inflate(RaceSceneryLayout._gateClearance)
                  .overlaps(placement.cullBounds),
        ) ||
        _placements.any(
          (existing) =>
              existing.cullBounds.inflate(gap).overlaps(placement.cullBounds),
        )) {
      return false;
    }
    _placements.add(placement);
    return true;
  }

  List<RaceSceneryPlacement> finish() =>
      List<RaceSceneryPlacement>.unmodifiable(_placements);
}

class _SceneryKind {
  const _SceneryKind(this.assetKey, this.width, this.height);

  final String assetKey;
  final double width;
  final double height;
}

class _RouteFrame {
  const _RouteFrame({
    required this.point,
    required this.tangent,
    required this.normal,
    required this.heading,
  });

  final Offset point;
  final Offset tangent;
  final Offset normal;
  final double heading;
}
