import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:racing_client/api/api_client.dart';
import 'package:racing_client/history/race_history.dart';
import 'package:racing_client/history/race_history_repository.dart';

Map<String, Object?> historyJson({String id = 'history-1'}) => {
  'id': id,
  'ownerUserId': '0123456789abcdef01234567',
  'raceId': '0123456789abcdef0123456789abcdef',
  'roomId': 'f00542a1-3f6d-49b3-b746-00216f5d5c58',
  'mode': 'lap',
  'trackId': 'apex-loop',
  'trackSeed': null,
  'generatorVersion': null,
  'startedAt': '2026-10-27T10:00:00.000Z',
  'endedAt': '2026-10-27T10:00:20.000Z',
  'durationMs': 19000,
  'endReason': 'completed',
  'isDraw': false,
  'winnerSlot': 'p1',
  'players': [
    {
      'slot': 'p1',
      'vehicle': 'red',
      'source': 'phone',
      'status': 'finished',
      'finishTime': 18,
      'lapCount': 3,
      'completedLaps': 3,
      'lapTimes': [6, 6, 6],
      'completedCheckpoints': null,
      'totalCheckpoints': null,
    },
    {
      'slot': 'p2',
      'vehicle': 'blue',
      'source': 'keyboard',
      'status': 'finished',
      'finishTime': 19,
      'lapCount': 3,
      'completedLaps': 3,
      'lapTimes': [6, 6, 7],
      'completedCheckpoints': null,
      'totalCheckpoints': null,
    },
  ],
};

http.Response jsonResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

void main() {
  test('posts an immutable result with the saved access token', () async {
    http.Request? request;
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      readAccessToken: () => 'host-token',
      client: MockClient((value) async {
        request = value;
        return jsonResponse(historyJson());
      }),
    );
    final repository = HttpRaceHistoryRepository(client);
    final submission = RaceHistorySubmission(
      raceId: '0123456789abcdef0123456789abcdef',
      roomId: 'f00542a1-3f6d-49b3-b746-00216f5d5c58',
      mode: HistoryRaceMode.lap,
      trackId: 'apex-loop',
      trackSeed: null,
      generatorVersion: null,
      startedAt: DateTime.utc(2026, 10, 27, 10),
      endedAt: DateTime.utc(2026, 10, 27, 10, 0, 20),
      durationMs: 19000,
      endReason: 'completed',
      isDraw: false,
      winnerSlot: 'p1',
      players: [],
    );

    final result = await repository.save(submission);

    expect(request!.method, 'POST');
    expect(request!.url.path, '/race-histories');
    expect(request!.headers['authorization'], 'Bearer host-token');
    expect(jsonDecode(request!.body), submission.toJson());
    expect(result.players, hasLength(2));
    expect(result.players.first.lapTimes, [6, 6, 6]);
  });

  test('reads the owner scoped list and detail endpoints', () async {
    final paths = <String>[];
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      readAccessToken: () => 'host-token',
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/me')) {
          return jsonResponse({
            'items': [historyJson()],
            'nextCursor': 'cursor',
          });
        }
        return jsonResponse(historyJson());
      }),
    );
    final repository = HttpRaceHistoryRepository(client);

    final page = await repository.list();
    final detail = await repository.findOne('history-1');

    expect(paths, ['/race-histories/me', '/race-histories/history-1']);
    expect(page.items.single.id, 'history-1');
    expect(page.nextCursor, 'cursor');
    expect(detail.winnerSlot, 'p1');
  });
}
