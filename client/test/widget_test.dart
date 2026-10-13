import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/auth/auth_controller.dart';
import 'package:racing_client/auth/auth_pages.dart';
import 'package:racing_client/auth/session_user.dart';
import 'package:racing_client/chat/chat_message.dart';
import 'package:racing_client/chat/lm_studio_service.dart';
import 'package:racing_client/main.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('User keeps the racing demo flow and five destinations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _signedInAuth(AppRole.user);
    final catalog = FakeCatalogRepository();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MyApp(authController: auth, catalogRepository: catalog),
    );
    await tester.pumpAndSettle();

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
    expect(find.byType(IndexedStack), findsWidgets);

    await _tap(
      tester,
      find.widgetWithText(OutlinedButton, 'Bình chọn tái đấu'),
    );
    expect(find.text('Đã bình chọn tái đấu'), findsOneWidget);
    await _tap(tester, find.text('Chơi lại'));
    expect(find.text('Tinh chỉnh bộ điều khiển'), findsOneWidget);
  });

  testWidgets('User can open the catalog in read-only mode and log out', (
    tester,
  ) async {
    final auth = _signedInAuth(AppRole.user);
    final catalog = FakeCatalogRepository();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MyApp(authController: auth, catalogRepository: catalog),
    );
    await tester.pumpAndSettle();

    await _openAccountMenu(tester, 'racer_01');
    await _tap(tester, find.text('Sản phẩm & danh mục'));
    await tester.pumpAndSettle();
    expect(find.text('RC Buggy'), findsOneWidget);
    expect(find.text('Thêm'), findsNothing);
    expect(find.byTooltip('Sửa RC Buggy'), findsNothing);
    expect(find.byTooltip('Xóa RC Buggy'), findsNothing);

    await _openAccountMenu(tester, 'racer_01');
    await _tap(tester, find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(auth.accessToken, isNull);
  });

  testWidgets('Admin lands on catalog and can create a product', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _signedInAuth(AppRole.admin);
    final catalog = FakeCatalogRepository();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MyApp(authController: auth, catalogRepository: catalog),
    );
    await tester.pumpAndSettle();

    expect(find.text('Quản trị sản phẩm'), findsOneWidget);
    expect(find.text('Mở racing demo'), findsOneWidget);
    expect(find.byTooltip('Sửa RC Buggy'), findsOneWidget);
    await _tap(tester, find.byTooltip('Sửa RC Buggy'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'RC Buggy Pro');
    await _tap(tester, find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();
    expect(catalog.replaceProductCalls, 1);
    expect(find.text('RC Buggy Pro'), findsOneWidget);

    await _tap(tester, find.text('Thêm'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'RC Truck');
    await tester.enterText(find.byType(TextFormField).at(1), '240');
    await _tap(tester, find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();

    expect(catalog.createProductCalls, 1);
    expect(find.text('RC Truck'), findsOneWidget);

    await _tap(tester, find.byTooltip('Xóa RC Truck'));
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(FilledButton, 'Xóa'));
    await tester.pumpAndSettle();
    expect(catalog.deleteProductCalls, 1);
    expect(find.text('RC Truck'), findsNothing);

    await _tap(tester, find.text('Mở racing demo'));
    expect(find.text('Kết nối thiết bị'), findsOneWidget);
    await _openAccountMenu(tester, 'admin_racer');
    await _tap(tester, find.text('Quay lại quản trị'));
    expect(find.text('Quản trị sản phẩm'), findsOneWidget);
  });

  testWidgets('registration returns to login with username prefilled', (
    tester,
  ) async {
    final repository = FakeAuthRepository(user: testUser());
    final auth = AuthController(
      repository: repository,
      tokenStore: MemoryTokenStore(),
    );
    final catalog = FakeCatalogRepository();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MyApp(authController: auth, catalogRepository: catalog),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);

    await _tap(tester, find.text('Tạo tài khoản User'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'new_racer');
    await tester.enterText(find.byType(TextFormField).at(1), 'new@example.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'racing-pass-123');
    await _tap(tester, find.widgetWithText(FilledButton, 'Tạo tài khoản'));
    await tester.pumpAndSettle();

    expect(repository.registerCalls, 1);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'new_racer',
    );
  });

  testWidgets('racing shell keeps its bottom navigation on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _signedInAuth(AppRole.user);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MyApp(authController: auth, catalogRepository: FakeCatalogRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kết nối thiết bị'), findsOneWidget);
    expect(find.text('Đường đua'), findsOneWidget);
    await _tap(tester, find.text('Tinh chỉnh'));
    expect(find.text('Tinh chỉnh bộ điều khiển'), findsOneWidget);
  });

  testWidgets('desktop chat panel closes without changing the selected tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _signedInAuth(AppRole.user);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MyApp(
        authController: auth,
        catalogRepository: FakeCatalogRepository(),
        chatServiceFactory: _FakeChatService.new,
      ),
    );
    await tester.pumpAndSettle();

    await _tap(tester, find.text('Tinh chỉnh'));
    await _tap(tester, find.byTooltip('Mở trợ lý Apex RC'));
    expect(find.text('Trợ lý Apex RC'), findsOneWidget);
    await _tap(tester, find.byTooltip('Đóng chat'));

    expect(find.text('Tinh chỉnh bộ điều khiển'), findsOneWidget);
    expect(find.byTooltip('Mở trợ lý Apex RC'), findsOneWidget);
  });

  testWidgets('mobile chat page returns to the previously selected tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _signedInAuth(AppRole.user);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MyApp(
        authController: auth,
        catalogRepository: FakeCatalogRepository(),
        chatServiceFactory: _FakeChatService.new,
      ),
    );
    await tester.pumpAndSettle();

    await _tap(tester, find.text('Tinh chỉnh'));
    await _tap(tester, find.byTooltip('Mở chat với AI'));
    expect(find.text('Hỏi đáp bằng AI'), findsOneWidget);
    await _tap(tester, find.byTooltip('Quay lại'));

    expect(find.text('Tinh chỉnh bộ điều khiển'), findsOneWidget);
    expect(find.text('Tinh chỉnh'), findsOneWidget);
  });
}

class _FakeChatService implements ChatService {
  @override
  Future<ChatCompletion> complete(List<ChatMessage> history) async =>
      const ChatCompletion(content: 'Câu trả lời giả lập');

  @override
  void close() {}
}

AuthController _signedInAuth(AppRole role) {
  final token = testToken();
  return AuthController(
    repository: FakeAuthRepository(
      user: testUser(role: role),
      token: token,
    ),
    tokenStore: MemoryTokenStore(token),
  );
}

Future<void> _openAccountMenu(WidgetTester tester, String username) async {
  await _tap(tester, find.byTooltip('Tài khoản $username'));
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
