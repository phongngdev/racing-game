import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/race_progress.dart';
import 'package:racing_client/racing/sprint/sprint_player_tracker.dart';
import 'package:racing_client/racing/tracks/sprint_track_generator.dart';

void main() {
  const generator = SprintTrackGenerator();

  test('same seed and generator version produce the same full track', () {
    final first = generator.generate('demo-seed-42');
    final second = generator.generate('demo-seed-42');
    expect(first.generatorVersion, 1);
    expect(first.seed, 'demo-seed-42');
    expect(first.fingerprint, second.fingerprint);
    expect(
      sprintGeometryFingerprint(first.track),
      sprintGeometryFingerprint(second.track),
    );
  });

  test('stable seed hash and generator v1 fingerprint golden values', () {
    final result = generator.generate('demo-seed-42');
    // These values change only with an intentional generator version bump.
    expect(sprintSeedHash('demo-seed-42'), 1588301931);
    expect(result.fingerprint, '59f99fe8');
  });

  test('1000 fixed seeds generate valid, varied tracks within bounded retries', () {
    final stopwatch = Stopwatch()..start();
    final fingerprints = <String>{};
    final attempts = <int>[];
    final generationMicros = <int>[];
    var minimumLength = double.infinity;
    var maximumLength = 0.0;
    var minimumCheckpoints = 99;
    var maximumCheckpoints = 0;
    var maximumWalls = 0;
    final failures = <String>[];
    for (var i = 0; i < 1000; i++) {
      final seed = 'milestone6-seed-$i';
      try {
        final result = generator.generate(seed);
        final track = result.track;
        fingerprints.add(sprintGeometryFingerprint(track));
        attempts.add(result.attempts);
        generationMicros.add(result.elapsed.inMicroseconds);
        final distance = track.finishStation - track.gridStation;
        minimumLength = minimumLength < distance ? minimumLength : distance;
        maximumLength = maximumLength > distance ? maximumLength : distance;
        minimumCheckpoints = minimumCheckpoints < track.checkpoints.length
            ? minimumCheckpoints
            : track.checkpoints.length;
        maximumCheckpoints = maximumCheckpoints > track.checkpoints.length
            ? maximumCheckpoints
            : track.checkpoints.length;
        maximumWalls = maximumWalls > track.walls.length
            ? maximumWalls
            : track.walls.length;
        expect(distance, inInclusiveRange(5000, 9000), reason: seed);
        expect(track.checkpoints.length, inInclusiveRange(7, 11), reason: seed);
        expect(track.walls.length, lessThanOrEqualTo(128), reason: seed);
        expect(track.isDrivable(track.redSpawn.position, radius: 32), isTrue);
        expect(track.isDrivable(track.blueSpawn.position, radius: 32), isTrue);
      } on SprintTrackGenerationException catch (error) {
        failures.add('$seed: $error');
      }
    }
    stopwatch.stop();
    final sortedAttempts = [...attempts]..sort();
    final averageAttempts = attempts.isEmpty
        ? 0
        : attempts.reduce((a, b) => a + b) / attempts.length;
    final sortedGenerationMicros = [...generationMicros]..sort();
    final averageGenerationMicros = generationMicros.isEmpty
        ? 0
        : generationMicros.reduce((a, b) => a + b) / generationMicros.length;
    final p95GenerationMicros = sortedGenerationMicros.isEmpty
        ? 0
        : sortedGenerationMicros[
            ((sortedGenerationMicros.length - 1) * .95).round()
          ];
    final p95Attempts = sortedAttempts.isEmpty
        ? 0
        : sortedAttempts[((sortedAttempts.length - 1) * .95).round()];
    // This summary makes failures and the requested 1,000-seed measurements
    // visible in CI and in local Windows test output.
    // ignore: avoid_print
    print(
      'Sprint v1 seed sweep: success=${1000 - failures.length}/1000 '
      '(${(100 * (1000 - failures.length) / 1000).toStringAsFixed(1)}%), '
      'unique=${fingerprints.length}/1000, '
      'attempts avg=${averageAttempts.toStringAsFixed(2)} '
      'p95=$p95Attempts max=${sortedAttempts.isEmpty ? 0 : sortedAttempts.last}, '
      'length=$minimumLength–$maximumLength, '
      'checkpoints=$minimumCheckpoints–$maximumCheckpoints, '
      'maxWalls=$maximumWalls, '
      'generation avg=${averageGenerationMicros.toStringAsFixed(0)}us '
      'p95=${p95GenerationMicros}us '
      'max=${sortedGenerationMicros.isEmpty ? 0 : sortedGenerationMicros.last}us, '
      'sweep=${stopwatch.elapsedMilliseconds}ms',
    );
    for (final failure in failures) {
      // ignore: avoid_print
      print('Sprint v1 failure: $failure');
    }
    expect(failures, isEmpty, reason: failures.take(10).join('\n'));
    expect(fingerprints.length, greaterThanOrEqualTo(950));
    expect(attempts, isNotEmpty);
  });

  test('different seeds give deterministic but different layouts', () {
    final samples = [
      generator.generate('harbor-loop').track,
      generator.generate('ridge-turn').track,
      generator.generate('orchard-run').track,
    ];
    expect(samples.map(sprintTrackFingerprint).toSet(), hasLength(3));
    expect(
      samples.map(sprintGeometryFingerprint).toSet(),
      hasLength(3),
    );
    expect(
      samples.map((track) => track.centerline.length).toSet().length,
      greaterThan(1),
    );
    for (var sample = 0; sample < samples.length; sample++) {
      final track = samples[sample];
      final directions = <String>[];
      final lengths = <String>[];
      for (var i = 0; i < track.centerline.length - 1; i++) {
        final a = track.centerline[i];
        final b = track.centerline[i + 1];
        directions.add(
          b.x > a.x
              ? 'E'
              : b.x < a.x
              ? 'W'
              : b.y > a.y
              ? 'S'
              : 'N',
        );
        lengths.add((track.stations[i + 1] - track.stations[i]).toStringAsFixed(0));
      }
      // ignore: avoid_print
      print(
        'Sprint sample ${track.seed}: ${track.finishStation - track.gridStation}'
        ' units, ${track.checkpoints.length} CP, ${track.walls.length} walls, '
        '${directions.join("-")}, legs=${lengths.join(",")}',
      );
    }
  });

  test('generated route completes every checkpoint before Finish', () {
    final track = generator.generate('checkpoint-route').track;
    final tracker = SprintPlayerTracker(player: PlayerId.red, track: track);
    var from = track.redSpawn.position;
    for (var segment = 0; segment < track.centerline.length - 1; segment++) {
      final to = track.centerline[segment + 1];
      tracker.advanceSegment(
        from: from,
        to: to,
        stepStartTime: segment.toDouble(),
        stepSeconds: 1,
      );
      from = to;
    }
    final progress = tracker.progressAt(track.centerline.length.toDouble());
    expect(progress.completedCheckpoints, track.checkpoints.length);
    expect(progress.status, RacePlayerStatus.finished);
    expect(progress.fraction, 1);
  });

  test('rejects invalid seeds and never silently changes one', () {
    expect(() => generator.generate('   '), throwsFormatException);
    expect(() => generator.generate('x' * 65), throwsFormatException);
    final result = generator.generate('  named-seed  ');
    expect(result.seed, 'named-seed');
    expect(result.track.seed, 'named-seed');
  });
}
