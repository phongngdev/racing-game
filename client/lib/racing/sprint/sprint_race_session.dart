import '../race_session.dart';
import '../tracks/track_definition.dart';
import 'sprint_player_tracker.dart';

class SprintRaceSession extends RaceSession<SprintPlayerProgress> {
  SprintRaceSession({
    required super.simulation,
    required super.inputSource,
    required super.canStart,
    required super.controllersAvailable,
    required super.clearInputs,
    required super.setGameRunning,
    required this.track,
    super.config,
  }) : super(
         redTracker: SprintPlayerTracker(
           player: simulation.red.player,
           track: track,
         ),
         blueTracker: SprintPlayerTracker(
           player: simulation.blue.player,
           track: track,
         ),
       );
  final TrackDefinition track;
}
