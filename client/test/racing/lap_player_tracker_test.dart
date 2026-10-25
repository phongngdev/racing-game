import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/lap/lap_player_tracker.dart';
import 'package:racing_client/racing/lap/lap_race_track.dart';

void main() {
  const track = LapRaceTrack.standard;

  test('first finish crossing and out-of-order gates do not count a lap', () {
    final tracker = LapPlayerTracker(
      player: PlayerId.red,
      track: track,
      lapCount: 1,
    );

    expect(
      cross(
        tracker,
        track.finish,
        0,
        const TrackPoint(470, 112),
        const TrackPoint(490, 112),
      ),
      isNull,
      reason: 'The grid crossing cannot finish a lap.',
    );
    cross(
      tracker,
      track.checkpoints[1],
      1,
      const TrackPoint(490, 500),
      const TrackPoint(470, 500),
    );
    cross(
      tracker,
      track.checkpoints[2],
      2,
      const TrackPoint(170, 330),
      const TrackPoint(170, 310),
    );
    cross(
      tracker,
      track.finish,
      3,
      const TrackPoint(470, 112),
      const TrackPoint(490, 112),
    );
    expect(tracker.progressAt(4).completedLaps, 0);
    expect(tracker.progressAt(4).nextGateId, 'cp1-right');
  });

  test('counter-clockwise circuit crossings do not advance any checkpoint', () {
    final tracker = LapPlayerTracker(player: PlayerId.red, track: track);

    cross(
      tracker,
      track.finish,
      0,
      const TrackPoint(490, 112),
      const TrackPoint(470, 112),
    );
    cross(
      tracker,
      track.checkpoints[2],
      1,
      const TrackPoint(170, 310),
      const TrackPoint(170, 330),
    );
    cross(
      tracker,
      track.checkpoints[1],
      2,
      const TrackPoint(470, 500),
      const TrackPoint(490, 500),
    );
    cross(
      tracker,
      track.checkpoints[0],
      3,
      const TrackPoint(800, 330),
      const TrackPoint(800, 310),
    );

    expect(tracker.progressAt(4).completedLaps, 0);
    expect(tracker.progressAt(4).nextGateId, 'cp1-right');
  });

  test(
    'backtracking across an accepted checkpoint invalidates this lap progress',
    () {
      final tracker = LapPlayerTracker(
        player: PlayerId.red,
        track: track,
        lapCount: 1,
      );
      cross(
        tracker,
        track.checkpoints[0],
        0,
        const TrackPoint(800, 310),
        const TrackPoint(800, 330),
      );

      final reverse = cross(
        tracker,
        track.checkpoints[0],
        1,
        const TrackPoint(800, 330),
        const TrackPoint(800, 310),
      );
      expect(reverse?.invalidatedProgress, isTrue);
      expect(tracker.progressAt(2).nextGateId, 'cp1-right');

      cross(
        tracker,
        track.checkpoints[1],
        2,
        const TrackPoint(490, 500),
        const TrackPoint(470, 500),
      );
      cross(
        tracker,
        track.checkpoints[2],
        3,
        const TrackPoint(170, 330),
        const TrackPoint(170, 310),
      );
      cross(
        tracker,
        track.finish,
        4,
        const TrackPoint(470, 112),
        const TrackPoint(490, 112),
      );
      expect(tracker.progressAt(5).status, LapPlayerStatus.racing);
      expect(tracker.progressAt(5).completedLaps, 0);
    },
  );

  test('ordered forward route counts laps and interpolates finish time', () {
    final tracker = LapPlayerTracker(
      player: PlayerId.blue,
      track: track,
      lapCount: 2,
    );
    for (var lap = 0; lap < 2; lap++) {
      final start = lap * 4.0;
      cross(
        tracker,
        track.checkpoints[0],
        start,
        const TrackPoint(800, 310),
        const TrackPoint(800, 330),
      );
      cross(
        tracker,
        track.checkpoints[1],
        start + 1,
        const TrackPoint(490, 500),
        const TrackPoint(470, 500),
      );
      cross(
        tracker,
        track.checkpoints[2],
        start + 2,
        const TrackPoint(170, 330),
        const TrackPoint(170, 310),
      );
      final finish = cross(
        tracker,
        track.finish,
        start + 3,
        const TrackPoint(470, 112),
        const TrackPoint(490, 112),
      );
      expect(finish?.completedLap, lap + 1);
      expect(finish?.eventTime, closeTo(start + 3.5, 1e-9));
    }

    final progress = tracker.progressAt(8);
    expect(progress.completedLaps, 2);
    expect(progress.status, LapPlayerStatus.finished);
    expect(progress.lapTimes, [3.5, 4]);
    expect(progress.finishTime, closeTo(7.5, 1e-9));
  });

  test('finish and DNF are terminal states', () {
    final tracker = LapPlayerTracker(
      player: PlayerId.red,
      track: track,
      lapCount: 1,
    );
    tracker.markDnf();
    expect(tracker.progressAt(1).status, LapPlayerStatus.dnf);
    expect(
      cross(
        tracker,
        track.checkpoints[0],
        1,
        const TrackPoint(800, 310),
        const TrackPoint(800, 330),
      ),
      isNull,
    );
  });
}

LapProgressEvent? cross(
  LapPlayerTracker tracker,
  LapGate gate,
  double start,
  TrackPoint from,
  TrackPoint to,
) => tracker.advanceSegment(
  from: from,
  to: to,
  stepStartTime: start,
  stepSeconds: 1,
);
