import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/controller/controller_config.dart';
import 'package:racing_client/controller/controller_connection.dart';
import 'package:racing_client/controller/controller_protocol.dart';
import 'package:racing_client/racing/apex_racing_game.dart';
import 'package:racing_client/racing/racing_page.dart';

void main() {
  testWidgets('Practice starts stopped and keyboard controls both cars', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: RacingPage(mode: RacingPageMode.practice)),
    );
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

    expect(game.simulation.isRunning, isFalse);
    expect(find.text('Bắt đầu đua'), findsOneWidget);
    expect(find.text('Điện thoại'), findsNothing);

    await tester.tap(find.text('Bắt đầu đua'));
    await tester.pump();
    expect(game.simulation.isRunning, isTrue);
    final redStart = game.simulation.red.position.x;
    final blueStart = game.simulation.blue.position.x;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await _pumpFrames(tester, 20);
    expect(game.simulation.red.position.x, greaterThan(redStart));
    expect(game.simulation.blue.position.x, blueStart);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await _pumpFrames(tester, 20);
    expect(game.simulation.blue.position.x, greaterThan(blueStart));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Practice does not create ControllerConnection with a valid relay URL',
    (tester) async {
      final connectionFactory = _ConnectionFactorySpy();
      await tester.pumpWidget(
        MaterialApp(
          home: RacingPage(
            mode: RacingPageMode.practice,
            controllerConnectionFactory: connectionFactory.create,
          ),
        ),
      );
      await tester.pump();

      expect(ControllerConfig.parse(ControllerConfig.webSocketUrl), isNotNull);
      expect(connectionFactory.calls, 0);
      expect(connectionFactory.connection?.connectCalls ?? 0, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(connectionFactory.calls, 0);
    },
    skip: ControllerConfig.parse(ControllerConfig.webSocketUrl) == null,
  );

  testWidgets(
    'Practice game layout fits desktop, mobile, and short landscape',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final size in const [
        Size(1280, 900),
        Size(390, 844),
        Size(873, 393),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          const MaterialApp(home: RacingPage(mode: RacingPageMode.practice)),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'viewport $size');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );
}

class _ConnectionFactorySpy {
  int calls = 0;
  _RecordingControllerConnection? connection;

  ControllerConnection create({
    required Uri uri,
    required ControllerRole role,
    required void Function(ControllerMessage) onEvent,
  }) {
    calls++;
    return connection = _RecordingControllerConnection(
      uri: uri,
      role: role,
      onEvent: onEvent,
    );
  }
}

class _RecordingControllerConnection extends ControllerConnection {
  _RecordingControllerConnection({
    required super.uri,
    required super.role,
    required super.onEvent,
  });

  int connectCalls = 0;

  @override
  void connect() => connectCalls++;

  @override
  Future<void> disconnect() async {}
}

Future<void> _pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
