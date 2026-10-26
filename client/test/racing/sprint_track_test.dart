import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/tracks/track_definition.dart';
import 'package:racing_client/racing/tracks/track_geometry.dart';
import 'package:racing_client/racing/simulation/race_simulation.dart';

void main() {
  final track = FixedTracks.sprint;
  test('corridor is connected, has clearance at all turns and fair spawns', () {
    expect(track.stations.last, 7160);
    expect(track.finishStation - track.gridStation, 7000);
    expect(track.checkpoints.length, 8);
    expect(track.walls.length, lessThan(128));
    expect(track.redSpawn.position.x, track.blueSpawn.position.x);
    expect(track.redSpawn.heading, track.blueSpawn.heading);
    for (var i = 0; i < track.centerline.length - 1; i++) {
      for (var n = 0; n <= 200; n++) {
        expect(
          track.isDrivable(
            track.centerline[i].lerpTo(track.centerline[i + 1], n / 200),
            radius: 32,
          ),
          isTrue,
          reason: 'segment $i sample $n',
        );
      }
    }
  });
  test('walls exactly cover the world outside the road union', () {
    for (var x = 10.0; x < 3600; x += 37) {
      for (var y = 10.0; y < 2200; y += 37) {
        final point = Offset(x, y);
        expect(
          track.walls.any((wall) => wall.$2.contains(point)),
          !track.roadRects.any((road) => road.contains(point)),
        );
      }
    }
  });
  test(
    'all gates are inside the same road geometry and ordered along route',
    () {
      var previous = track.gridStation;
      for (var i = 0; i < track.checkpoints.length; i++) {
        final gate = track.checkpoints[i];
        expect(track.checkpointStations[i], greaterThan(previous));
        previous = track.checkpointStations[i];
        expect(track.isDrivable(gate.start.lerpTo(gate.end, 0.5)), isTrue);
      }
      expect(track.finishStation, greaterThan(previous));
    },
  );
  test('diagonal and intersecting corridors are rejected', () {
    expect(
      () => TrackDefinition.corridor(
        id: 'bad',
        worldBounds: const Rect.fromLTWH(0, 0, 2000, 2000),
        centerline: const [TrackPoint(200, 200), TrackPoint(800, 800)],
      ),
      throwsArgumentError,
    );
    expect(
      () => TrackDefinition.corridor(
        id: 'bad',
        worldBounds: const Rect.fromLTWH(0, 0, 2000, 2000),
        centerline: const [
          TrackPoint(200, 200),
          TrackPoint(1200, 200),
          TrackPoint(1200, 1000),
          TrackPoint(600, 1000),
          TrackPoint(600, 200),
        ],
      ),
      throwsArgumentError,
    );
  });
  test('track pose and finished collision flags reset without changing Practice defaults', () {
    final simulation = RaceSimulation(track: track);
    addTearDown(simulation.dispose);
    simulation.red.position.setValues(0, 0);
    simulation.finishPlayer(simulation.red.player);
    simulation.reset();
    expect(simulation.red.position.x, track.redSpawn.position.x);
    expect(simulation.red.heading, track.redSpawn.heading);
    expect(simulation.isPlayerFinished(simulation.red.player), isFalse);
    final practice = RaceSimulation();
    addTearDown(practice.dispose);
    expect(practice.red.position.x, 150);
    expect(practice.red.position.y, 112);
  });
}
