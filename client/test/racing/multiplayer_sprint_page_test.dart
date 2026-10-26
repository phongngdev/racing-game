import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/pages/multiplayer_setup_page.dart';
import 'package:racing_client/racing/apex_racing_game.dart';
import 'package:racing_client/racing/multiplayer_race_page.dart';
import 'package:racing_client/racing/race_mode.dart';
import 'package:racing_client/racing/tracks/track_definition.dart';
import 'package:racing_client/racing/tracks/sprint_track_generator.dart';

import 'helpers/room_fixture.dart';

void main() {
  testWidgets(
    'Lobby switches Lap/Sprint using the same room and controller session',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = RoomFixture();
      var creates = 0;
      RaceMode? startedMode;
      TrackDefinition? startedTrack;
      Object? startedSession;
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplayerSetupPage(
            onBack: () {},
            sessionFactory: (_) {
              creates++;
              return fixture.session;
            },
            onStart: (session, mode, sprintTrack) async {
              startedMode = mode;
              startedTrack = sprintTrack;
              startedSession = session;
            },
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextField).first,
        'ws://192.168.1.20:3000/controller',
      );
      await tester.tap(find.text('Tạo phòng'));
      await tester.pump();
      expect(find.textContaining('QR p1 chưa sẵn sàng'), findsNothing);
      await Scrollable.ensureVisible(
        tester.element(find.text('Sprint Race')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sprint Race'));
      await tester.pump();
      expect(find.textContaining('Sprint Race · Start'), findsOneWidget);
      expect(creates, 1);
      expect(fixture.session.roomId, 'room-test-01');
      expect(
        tester.getRect(find.text('Vào đường đua')).bottom,
        lessThan(tester.view.physicalSize.height),
      );
      await tester.tap(find.text('Vào đường đua'));
      await tester.pump();
      expect(startedMode, RaceMode.sprint);
      expect(identical(startedTrack, FixedTracks.sprint), isTrue);
      expect(identical(startedSession, fixture.session), isTrue);
      await tester.tap(find.text('Lap Race'));
      await tester.pump();
      expect(creates, 1);
      expect(fixture.connection.sentEvents, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Sprint HUD, Pause Restart, Results and Rematch keep the same room',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = RoomFixture();
      final generatedTrack = const SprintTrackGenerator()
          .generate('lifecycle-track')
          .track;
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplayerRacePage(
            session: fixture.session,
            mode: RaceMode.sprint,
            sprintTrack: generatedTrack,
          ),
        ),
      );
      final game = tester
          .widget<GameWidget<ApexRacingGame>>(
            find.byType(GameWidget<ApexRacingGame>),
          )
          .game!;
      await tester.runAsync(() async {
        await game.loaded;
        await game.ready();
      });
      await tester.pump();
      expect(identical(game.simulation.track, generatedTrack), isTrue);
      expect(identical(game.sprintTrack, generatedTrack), isTrue);
      expect(find.text('SPRINT RACE'), findsOneWidget);
      expect(
        find.textContaining('CP 0/${generatedTrack.checkpoints.length}'),
        findsNWidgets(2),
      );
      expect(find.textContaining('SEED lifecycle-track · v1'), findsOneWidget);
      expect(find.textContaining('Vòng'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Bắt đầu đua')).dy,
        lessThan(
          tester
              .getTopLeft(
                find
                    .textContaining('CP 0/${generatedTrack.checkpoints.length}')
                    .first,
              )
              .dy,
        ),
      );
      await tester.tap(find.text('Bắt đầu đua'));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('GO!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 20));
      expect(game.simulation.isRunning, isTrue);
      for (var i = 0; i < 60 && find.text('GO!').evaluate().isNotEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('GO!'), findsNothing);
      expect(find.text('ĐANG ĐUA'), findsNWidgets(2));
      expect(find.byType(DropdownButton<String>), findsNothing);
      await tester.tap(find.text('Tạm dừng'));
      await tester.pump();
      expect(game.simulation.isRunning, isFalse);
      expect(find.text('TẠM DỪNG'), findsNWidgets(3));
      expect(find.byType(DropdownButton<String>), findsNWidgets(2));
      await tester.tap(find.text('Tiếp tục').last);
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(game.simulation.isRunning, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('GO!'), findsOneWidget);
      expect(game.simulation.isRunning, isTrue);
      for (var i = 0; i < 60 && find.text('GO!').evaluate().isNotEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('GO!'), findsNothing);
      await tester.tap(find.text('Tạm dừng'));
      await tester.pump();
      await tester.tap(find.text('Restart từ vạch xuất phát'));
      await tester.pump();
      expect(find.text('Bắt đầu đua'), findsOneWidget);
      // Enter countdown, then host ends it from Pause: both DNF, no winner.
      await tester.tap(find.text('Bắt đầu đua'));
      await tester.pump();
      await tester.tap(find.text('Tạm dừng'));
      await tester.pump();
      await tester.tap(find.text('Kết thúc sớm và xem Results'));
      await tester.pump();
      expect(find.text('TANPA PEMENANG'), findsOneWidget);
      expect(find.text('DNF'), findsNWidgets(2));
      await tester.tap(find.text('Rematch · giữ nguyên room & controller'));
      await tester.pump();
      expect(find.text('SPRINT RACE'), findsOneWidget);
      expect(identical(game.simulation.track, generatedTrack), isTrue);
      expect(identical(game.sprintTrack, generatedTrack), isTrue);
      expect(fixture.session.roomId, 'room-test-01');
      expect(fixture.connection.sentEvents, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.session.dispose();
    },
  );

  testWidgets('Random Sprint keeps the room and passes the generated seed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = RoomFixture();
    var creates = 0;
    TrackDefinition? startedTrack;
    await tester.pumpWidget(
      MaterialApp(
        home: MultiplayerSetupPage(
          onBack: () {},
          sessionFactory: (_) {
            creates++;
            return fixture.session;
          },
          onStart: (session, mode, sprintTrack) async {
            startedTrack = sprintTrack;
          },
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField).first,
      'ws://192.168.1.20:3000/controller',
    );
    await tester.tap(find.text('Tạo phòng'));
    await tester.pump();
    await Scrollable.ensureVisible(
      tester.element(find.text('Sprint Race')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sprint Race'));
    await tester.pump();
    await tester.tap(find.text('Random'));
    await tester.pump();
    await tester.tap(find.text('New Track'));
    await tester.pumpAndSettle();
    final newSeed = tester
        .widget<TextField>(find.byType(TextField).last)
        .controller!
        .text;
    expect(newSeed, startsWith('Sprint-'));
    expect(find.textContaining('Seed: $newSeed · v1'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'demo-seed-42');
    await tester.tap(find.text('Tạo track'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Seed: demo-seed-42 · v1'), findsOneWidget);
    expect(find.text('Copy seed'), findsOneWidget);
    expect(creates, 1);
    await tester.tap(find.text('Vào đường đua'));
    await tester.pump();
    expect(startedTrack?.seed, 'demo-seed-42');
    expect(startedTrack?.generatorVersion, sprintGeneratorVersion);
    expect(creates, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
