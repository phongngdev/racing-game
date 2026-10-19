import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/controller/phone_controller_page.dart';

void main() {
  for (final size in [
    const Size(873, 393),
    const Size(700, 320),
    const Size(960, 600),
  ]) {
    testWidgets('controller fits landscape $size with system bars', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: PhoneControllerPage()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('GA'), findsOneWidget);
      expect(find.text('LÙI'), findsOneWidget);
      expect(find.text('Cân tâm'), findsOneWidget);
      expect(find.text('Thử rung'), findsOneWidget);

      // Entering the relay address must remain possible with a landscape IME.
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.tap(find.byType(TextField));
      await tester.enterText(
        find.byType(TextField),
        'ws://192.168.101.13:3000/controller',
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('LÙI'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('QR scanner entry is opt-in and leaves manual URL visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: PhoneControllerPage(enableQrPairing: true)),
    );
    await tester.pump();

    expect(find.text('Quét QR'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
