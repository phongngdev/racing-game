import '../race_session.dart';
import 'lap_player_tracker.dart';
import 'lap_race_rules.dart';
import 'lap_race_track.dart';

typedef LapRacePhase = RacePhase;
typedef LapRaceEndReason = RaceEndReason;

/// Compatibility entry point for the existing three-lap race.
class LapRaceSession extends RaceSession<LapPlayerProgress> {
  LapRaceSession({
    required super.simulation,
    required super.inputSource,
    required super.canStart,
    required super.controllersAvailable,
    required super.clearInputs,
    required super.setGameRunning,
    LapRaceConfig config = const LapRaceConfig(),
    this.track = LapRaceTrack.standard,
  }) : super(
         config: config,
         redTracker: LapPlayerTracker(
           player: simulation.red.player,
           lapCount: config.lapCount,
           track: track,
         ),
         blueTracker: LapPlayerTracker(
           player: simulation.blue.player,
           lapCount: config.lapCount,
           track: track,
         ),
       );
  final LapRaceTrack track;

  @override
  LapRaceConfig get config => super.config as LapRaceConfig;
}
