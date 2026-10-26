import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/race_progress.dart';
import 'package:racing_client/racing/sprint/sprint_player_tracker.dart';
import 'package:racing_client/racing/tracks/track_definition.dart';
import 'package:racing_client/racing/tracks/track_geometry.dart';

void main() {
  final track = FixedTracks.sprint;
  SprintPlayerTracker tracker() =>
      SprintPlayerTracker(player: PlayerId.red, track: track);
  RaceProgressEvent? cross(
    SprintPlayerTracker tracker,
    TrackGate gate, {
    bool reverse = false,
    double time = 0,
  }) {
    final center = gate.start.lerpTo(gate.end, 0.5);
    final delta = switch (gate.direction) {
      TrackDirection.east => const TrackPoint(10, 0),
      TrackDirection.west => const TrackPoint(-10, 0),
      TrackDirection.south => const TrackPoint(0, 10),
      TrackDirection.north => const TrackPoint(0, -10),
    };
    final before = TrackPoint(center.x - delta.x, center.y - delta.y);
    final after = TrackPoint(center.x + delta.x, center.y + delta.y);
    return tracker.advanceSegment(
      from: reverse ? after : before,
      to: reverse ? before : after,
      stepStartTime: time,
      stepSeconds: 1,
    );
  }

  test('finish and later checkpoints cannot skip the validated sequence', () {
    final t = tracker();
    expect(cross(t, track.finish), isNull);
    expect(cross(t, track.checkpoints[1]), isNull);
    expect(t.progressAt(2).completedCheckpoints, 0);
    expect(t.progressAt(2).fraction, lessThan(1));
  });
  test(
    'forward gates finish with interpolated time; wrong direction does not',
    () {
      final t = tracker();
      for (var i = 0; i < track.checkpoints.length; i++) {
        expect(cross(t, track.checkpoints[i], reverse: true), isNull);
        expect(cross(t, track.checkpoints[i], time: i.toDouble()), isNotNull);
      }
      expect(cross(t, track.finish, reverse: true), isNull);
      final finish = cross(t, track.finish, time: 10);
      expect(finish?.finished, isTrue);
      expect(t.progressAt(11).finishTime, 10.5);
      expect(t.progressAt(11).fraction, 1);
      expect(cross(t, track.finish), isNull);
    },
  );
  test('backtracking rolls back only to the crossed checkpoint', () {
    final t = tracker();
    cross(t, track.checkpoints[0]);
    cross(t, track.checkpoints[1]);
    final before = t.progressAt(2).fraction;
    expect(
      cross(t, track.checkpoints[1], reverse: true)?.invalidatedProgress,
      isTrue,
    );
    expect(t.progressAt(3).completedCheckpoints, 1);
    expect(t.progressAt(3).fraction, lessThan(before));
    expect(cross(t, track.checkpoints[2]), isNull);
    cross(t, track.checkpoints[1]);
    expect(t.progressAt(4).completedCheckpoints, 2);
  });
  test('outside finite gate endpoints does not count; reset clears DNF', () {
    final t = tracker();
    final gate = track.checkpoints.first;
    expect(
      t.advanceSegment(
        from: TrackPoint(gate.start.x - 10, gate.start.y - 20),
        to: TrackPoint(gate.start.x + 10, gate.start.y - 20),
        stepStartTime: 0,
        stepSeconds: 1,
      ),
      isNull,
    );
    t.markDnf();
    expect(cross(t, gate), isNull);
    t.reset();
    expect(t.progressAt(0).status, RacePlayerStatus.racing);
    expect(t.progressAt(0).fraction, 0);
  });
}
