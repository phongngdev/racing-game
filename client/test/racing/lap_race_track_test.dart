import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/lap/lap_race_track.dart';

void main() {
  const track = LapRaceTrack.standard;

  test('standard map has four unique gates on the drivable ring', () {
    expect(track.hasValidGateGeometry, isTrue);
    expect(track.orderedLapGates.map((gate) => gate.id).toSet(), {
      'cp1-right',
      'cp2-bottom',
      'cp3-left',
      'finish',
    });
    expect(track.checkpoints, hasLength(3));
  });

  test('each gate only accepts a center crossing in its route direction', () {
    final from = <TrackPoint>[
      const TrackPoint(470, 112),
      const TrackPoint(800, 310),
      const TrackPoint(490, 500),
      const TrackPoint(170, 330),
    ];
    final to = <TrackPoint>[
      const TrackPoint(490, 112),
      const TrackPoint(800, 330),
      const TrackPoint(470, 500),
      const TrackPoint(170, 310),
    ];

    final gates = [track.finish, ...track.checkpoints];
    for (var i = 0; i < gates.length; i++) {
      final gate = gates[i];
      final crossing = gate.crossing(from[i], to[i], forward: true);
      expect(crossing, isNotNull, reason: gate.id);
      expect(crossing!.t, closeTo(0.5, 1e-9), reason: gate.id);
      expect(gate.crossing(to[i], from[i], forward: true), isNull);
    }
  });

  test('gate segment rejects crossing outside its finite endpoints', () {
    final finish = track.finish;
    expect(
      finish.crossing(
        const TrackPoint(470, 250),
        const TrackPoint(490, 250),
        forward: true,
      ),
      isNull,
    );
  });

  test('grid positions are separated and clear of the island', () {
    expect(track.redGrid.x, track.blueGrid.x);
    expect(track.redGrid.y, lessThan(track.blueGrid.y));
    expect(track.redGrid.x, lessThan(track.finish.start.x));
    expect(track.redGrid.y, lessThan(214));
    expect(track.blueGrid.y + 16, lessThan(214));
  });
}
