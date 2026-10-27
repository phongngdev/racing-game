import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/history/race_history.dart';
import 'package:racing_client/history/race_history_repository.dart';
import 'package:racing_client/pages/race_history_page.dart';

RaceHistory sampleHistory() => RaceHistory(
  id: 'history-1',
  raceId: '0123456789abcdef0123456789abcdef',
  roomId: 'f00542a1-3f6d-49b3-b746-00216f5d5c58',
  mode: HistoryRaceMode.lap,
  trackId: 'apex-loop',
  trackSeed: null,
  generatorVersion: null,
  startedAt: DateTime(2026, 10, 27, 10),
  endedAt: DateTime(2026, 10, 27, 10, 0, 20),
  durationMs: 19000,
  endReason: 'completed',
  isDraw: false,
  winnerSlot: 'p1',
  players: const [
    RaceHistoryPlayer(
      slot: 'p1',
      vehicle: 'red',
      source: 'phone',
      status: HistoryPlayerStatus.finished,
      finishTime: 18,
      lapCount: 3,
      completedLaps: 3,
      lapTimes: [6, 6, 6],
      completedCheckpoints: null,
      totalCheckpoints: null,
    ),
    RaceHistoryPlayer(
      slot: 'p2',
      vehicle: 'blue',
      source: 'keyboard',
      status: HistoryPlayerStatus.finished,
      finishTime: 19,
      lapCount: 3,
      completedLaps: 3,
      lapTimes: [6, 6, 7],
      completedCheckpoints: null,
      totalCheckpoints: null,
    ),
  ],
);

class FakeRaceHistoryRepository implements RaceHistoryRepository {
  FakeRaceHistoryRepository({this.page, this.listError, this.pendingList});

  RaceHistoryListResult? page;
  Object? listError;
  Completer<RaceHistoryListResult>? pendingList;
  int listCalls = 0;
  int detailCalls = 0;

  @override
  Future<RaceHistory> findOne(String id) async {
    detailCalls++;
    return sampleHistory();
  }

  @override
  Future<RaceHistoryListResult> list({String? cursor}) async {
    listCalls++;
    if (pendingList case final pending?) return pending.future;
    if (listError case final error?) throw error;
    return page ?? const RaceHistoryListResult(items: [], nextCursor: null);
  }

  @override
  Future<RaceHistory> save(RaceHistorySubmission submission) async =>
      sampleHistory();
}

void main() {
  testWidgets('shows loading, empty and error states with retry', (
    tester,
  ) async {
    final pending = Completer<RaceHistoryListResult>();
    final loadingRepository = FakeRaceHistoryRepository(pendingList: pending);
    await tester.pumpWidget(
      MaterialApp(home: RaceHistoryPage(repository: loadingRepository)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(const RaceHistoryListResult(items: [], nextCursor: null));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có trận nào trong lịch sử.'), findsOneWidget);

    final failing = FakeRaceHistoryRepository(listError: StateError('offline'));
    await tester.pumpWidget(
      MaterialApp(home: RaceHistoryPage(repository: failing)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Chưa tải được lịch sử đấu.'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(failing.listCalls, 2);
  });

  testWidgets('opens the detail endpoint and shows both players', (
    tester,
  ) async {
    final repository = FakeRaceHistoryRepository(
      page: RaceHistoryListResult(items: [sampleHistory()], nextCursor: null),
    );
    await tester.pumpWidget(
      MaterialApp(home: RaceHistoryPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('P1 thắng · Lap Race'), findsOneWidget);
    await tester.tap(find.text('P1 thắng · Lap Race'));
    await tester.pumpAndSettle();

    expect(repository.detailCalls, 1);
    expect(find.text('P1 chiến thắng'), findsOneWidget);
    expect(
      find.text('Thời gian từng vòng: 00:06.000 · 00:06.000 · 00:06.000'),
      findsOneWidget,
    );
    expect(find.text('P2 · Xe xanh'), findsOneWidget);
  });
}
