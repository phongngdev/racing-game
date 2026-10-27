enum HistoryRaceMode { lap, sprint }

enum HistoryPlayerStatus { finished, dnf }

class RaceHistoryPlayer {
  const RaceHistoryPlayer({
    required this.slot,
    required this.vehicle,
    required this.source,
    required this.status,
    required this.finishTime,
    required this.lapCount,
    required this.completedLaps,
    required this.lapTimes,
    required this.completedCheckpoints,
    required this.totalCheckpoints,
  });

  final String slot;
  final String vehicle;
  final String source;
  final HistoryPlayerStatus status;
  final double? finishTime;
  final int? lapCount;
  final int? completedLaps;
  final List<double> lapTimes;
  final int? completedCheckpoints;
  final int? totalCheckpoints;

  factory RaceHistoryPlayer.fromJson(Map<String, dynamic> json) =>
      RaceHistoryPlayer(
        slot: json['slot'] as String,
        vehicle: json['vehicle'] as String,
        source: json['source'] as String,
        status: HistoryPlayerStatus.values.byName(json['status'] as String),
        finishTime: (json['finishTime'] as num?)?.toDouble(),
        lapCount: (json['lapCount'] as num?)?.toInt(),
        completedLaps: (json['completedLaps'] as num?)?.toInt(),
        lapTimes: (json['lapTimes'] as List? ?? const [])
            .map((value) => (value as num).toDouble())
            .toList(growable: false),
        completedCheckpoints: (json['completedCheckpoints'] as num?)?.toInt(),
        totalCheckpoints: (json['totalCheckpoints'] as num?)?.toInt(),
      );
}

class RaceHistory {
  const RaceHistory({
    required this.id,
    required this.raceId,
    required this.roomId,
    required this.mode,
    required this.trackId,
    required this.trackSeed,
    required this.generatorVersion,
    required this.startedAt,
    required this.endedAt,
    required this.durationMs,
    required this.endReason,
    required this.isDraw,
    required this.winnerSlot,
    required this.players,
  });

  final String id;
  final String raceId;
  final String roomId;
  final HistoryRaceMode mode;
  final String trackId;
  final String? trackSeed;
  final int? generatorVersion;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationMs;
  final String endReason;
  final bool isDraw;
  final String? winnerSlot;
  final List<RaceHistoryPlayer> players;

  factory RaceHistory.fromJson(Map<String, dynamic> json) {
    final players = json['players'];
    if (players is! List || players.length != 2) {
      throw const FormatException('The API returned invalid race history.');
    }
    final mode = HistoryRaceMode.values.byName(json['mode'] as String);
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    final endedAt = DateTime.tryParse(json['endedAt'] as String? ?? '');
    if (startedAt == null || endedAt == null) {
      throw const FormatException('The API returned invalid race history.');
    }
    return RaceHistory(
      id: json['id'] as String,
      raceId: json['raceId'] as String,
      roomId: json['roomId'] as String,
      mode: mode,
      trackId: json['trackId'] as String,
      trackSeed: json['trackSeed'] as String?,
      generatorVersion: (json['generatorVersion'] as num?)?.toInt(),
      startedAt: startedAt.toLocal(),
      endedAt: endedAt.toLocal(),
      durationMs: (json['durationMs'] as num).toInt(),
      endReason: json['endReason'] as String,
      isDraw: json['isDraw'] as bool,
      winnerSlot: json['winnerSlot'] as String?,
      players: players
          .map(
            (value) =>
                RaceHistoryPlayer.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

class RaceHistorySubmission {
  const RaceHistorySubmission({
    required this.raceId,
    required this.roomId,
    required this.mode,
    required this.trackId,
    required this.trackSeed,
    required this.generatorVersion,
    required this.startedAt,
    required this.endedAt,
    required this.durationMs,
    required this.endReason,
    required this.isDraw,
    required this.winnerSlot,
    required this.players,
  });

  final String raceId;
  final String roomId;
  final HistoryRaceMode mode;
  final String trackId;
  final String? trackSeed;
  final int? generatorVersion;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationMs;
  final String endReason;
  final bool isDraw;
  final String? winnerSlot;
  final List<Map<String, Object?>> players;

  Map<String, Object?> toJson() => {
    'raceId': raceId,
    'roomId': roomId,
    'mode': mode.name,
    'trackId': trackId,
    'trackSeed': trackSeed,
    'generatorVersion': generatorVersion,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'durationMs': durationMs,
    'endReason': endReason,
    'isDraw': isDraw,
    'winnerSlot': winnerSlot,
    'players': players,
  };
}

class RaceHistoryListResult {
  const RaceHistoryListResult({required this.items, required this.nextCursor});

  final List<RaceHistory> items;
  final String? nextCursor;

  factory RaceHistoryListResult.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('The API returned an invalid history list.');
    }
    return RaceHistoryListResult(
      items: items
          .map((value) => RaceHistory.fromJson(value as Map<String, dynamic>))
          .toList(growable: false),
      nextCursor: json['nextCursor'] as String?,
    );
  }
}
