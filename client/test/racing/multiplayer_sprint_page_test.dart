import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/pages/multiplayer_setup_page.dart';
import 'package:racing_client/racing/apex_racing_game.dart';
import 'package:racing_client/racing/multiplayer_race_page.dart';
import 'package:racing_client/racing/race_mode.dart';

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
      Object? startedSession;
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplayerSetupPage(
            onBack: () {},
            sessionFactory: (_) {
              creates++;
              return fixture.session;
            },
            onStart: (session, mode) async {
              startedMode = mode;
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
      await tester.ensureVisible(find.text('Sprint Race'));
      await tester.tap(find.text('Sprint Race'));
      await tester.pump();
      expect(find.textContaining('Sprint Race · Start'), findsOneWidget);
      expect(creates, 1);
      expect(fixture.session.roomId, 'room-test-01');
      await tester.ensureVisible(find.text('Vào đường đua'));
      await tester.tap(find.text('Vào đường đua'));
      await tester.pump();
      expect(startedMode, RaceMode.sprint);
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
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplayerRacePage(
            session: fixture.session,
            mode: RaceMode.sprint,
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
      expect(find.text('SPRINT RACE'), findsOneWidget);
      expect(find.textContaining('CP 0/8'), findsNWidgets(2));
      expect(find.textContaining('Vòng'), findsNothing);
      await tester.tap(find.text('Countdown & mulai'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 20));
      expect(game.simulation.isRunning, isTrue);
      await tester.tap(find.text('Tạm dừng'));
      await tester.pump();
      expect(game.simulation.isRunning, isFalse);
      await tester.tap(find.text('Restart từ vạch xuất phát'));
      await tester.pump();
      expect(find.text('Countdown & mulai'), findsOneWidget);
      // Enter countdown, then host ends it from Pause: both DNF, no winner.
      await tester.tap(find.text('Countdown & mulai'));
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
      expect(fixture.session.roomId, 'room-test-01');
      expect(fixture.connection.sentEvents, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.session.dispose();
    },
  );
}
