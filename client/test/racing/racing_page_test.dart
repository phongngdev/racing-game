import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/apex_racing_game.dart';
import 'package:racing_client/racing/racing_page.dart';

void main() {
  testWidgets(
    'camera shows the track and real keyboard events move both cars',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: RacingPage()));
      await tester.pump();
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

      final visible = game.camera.visibleWorldRect;
      expect(visible.left, closeTo(0, 0.001));
      expect(visible.top, closeTo(0, 0.001));
      expect(visible.right, closeTo(960, 0.001));
      expect(visible.bottom, closeTo(640, 0.001));

      await tester.tap(find.text('Bắt đầu đua'));
      await tester.pump();
      final initialRedX = game.simulation.red.position.x;
      final initialBlueX = game.simulation.blue.position.x;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await _pumpFrames(tester, 20);
      expect(game.simulation.red.position.x, greaterThan(initialRedX));
      expect(game.simulation.blue.position.x, initialBlueX);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await _pumpFrames(tester, 20);
      expect(game.simulation.blue.position.x, greaterThan(initialBlueX));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(game.simulation.isRunning, isFalse);
      final pausedX = game.simulation.red.position.x;
      await _pumpFrames(tester, 10);
      expect(game.simulation.red.position.x, pausedX);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
