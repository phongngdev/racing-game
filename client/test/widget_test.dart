import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:racing_client/main.dart';

void main() {
  testWidgets('demo đi hết luồng kết nối, đua và tái đấu', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MyApp());

    expect(find.text('Kết nối thiết bị'), findsOneWidget);
    await _tap(tester, find.text('Mô phỏng quét mã QR'));
    await _tap(tester, find.text('Tiếp tục'));
    expect(find.text('Tinh chỉnh bộ điều khiển'), findsOneWidget);

    await _tap(tester, find.text('Sẵn sàng đua'));
    expect(find.text('Bảng điều khiển đường đua'), findsOneWidget);
    await _tap(tester, find.text('Mô phỏng va chạm'));
    expect(find.text('Cảnh báo va chạm'), findsOneWidget);

    await _tap(tester, find.text('Đưa xe về trạng thái an toàn'));
    expect(find.text('Bảng điều khiển đường đua'), findsOneWidget);
    await _tap(tester, find.byTooltip('Kết thúc phiên đua giả lập'));
    expect(find.text('Kết quả phiên đua'), findsOneWidget);

    await _tap(
      tester,
      find.widgetWithText(OutlinedButton, 'Bình chọn tái đấu'),
    );
    expect(find.text('Đã bình chọn tái đấu'), findsOneWidget);
    await _tap(tester, find.text('Chơi lại'));
    expect(find.text('Tinh chỉnh bộ điều khiển'), findsOneWidget);
  });

  testWidgets('menu và nội dung co lại ở màn hình hẹp', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MyApp());

    expect(find.text('Kết nối thiết bị'), findsOneWidget);
    expect(find.text('Đường đua'), findsOneWidget);
    await _tap(tester, find.text('Tinh chỉnh'));
    expect(find.text('Tinh chỉnh bộ điều khiển'), findsOneWidget);
  });
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
