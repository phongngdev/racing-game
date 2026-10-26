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
      expect(
        tester.getTopLeft(find.text('Bắt đầu đua')).dy,
        lessThan(tester.getTopLeft(find.textContaining('CP 0/8').first).dy),
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
      expect(fixture.session.roomId, 'room-test-01');
      expect(fixture.connection.sentEvents, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.session.dispose();
    },
  );
}
