import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/auth/auth_controller.dart';
import 'package:racing_client/auth/auth_pages.dart';
import 'package:racing_client/auth/session_user.dart';
import 'package:racing_client/chat/chat_message.dart';
import 'package:racing_client/chat/lm_studio_service.dart';
import 'package:racing_client/main.dart';
import 'package:racing_client/racing/apex_racing_game.dart';
import 'package:racing_client/racing/racing_page.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('Android offers controller scan before sign in', (tester) async {
    final auth = _signedInAuth(AppRole.user);
    addTearDown(auth.dispose);
    await _pumpMyApp(
      tester,
      MyApp(authController: auth, catalogRepository: FakeCatalogRepository()),
      platform: TargetPlatform.android,
    );
    await tester.pumpAndSettle();

    expect(find.text('Mở Apex RC'), findsOneWidget);
    expect(find.text('Quét QR'), findsOneWidget);
    expect(auth.status, AuthStatus.restoring);
  });

  testWidgets('User can enter and leave the Practice game route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _signedInAuth(AppRole.user);
    final catalog = FakeCatalogRepository();
    addTearDown(auth.dispose);
    await _pumpMyApp(
      tester,
      MyApp(authController: auth, catalogRepository: catalog),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chào mừng đến với Apex RC'), findsOneWidget);
    expect(find.text('Trang chủ'), findsWidgets);
    expect(find.text('Chơi'), findsWidgets);
    expect(find.text('Cài đặt'), findsWidgets);
    expect(find.text('BƯỚC'), findsNothing);
    expect(find.text('Bản demo giao diện'), findsNothing);
    expect(find.byType(IndexedStack), findsWidgets);

    await _tap(tester, find.text('Chơi').first);
    expect(find.text('Practice'), findsOneWidget);
    expect(find.text('Multiplayer'), findsOneWidget);
    expect(find.text('Sắp ra mắt'), findsNothing);
    expect(find.byType(RacingPage, skipOffstage: false), findsNothing);
    expect(find.text('Bắt đầu đua'), findsNothing);

    await tester.tap(find.text('Practice'));
    await tester.pumpAndSettle();
    expect(find.text('Chuẩn bị Practice'), findsOneWidget);
    expect(find.text('Bắt đầu Practice'), findsOneWidget);
    expect(find.text('← ↑ ↓ →'), findsOneWidget);
    expect(find.text('Tạo mã QR'), findsNothing);
    expect(find.byType(RacingPage), findsNothing);

    await tester.tap(find.text('Điện thoại'));
    await tester.pumpAndSettle();
    expect(find.text('Tạo mã QR'), findsOneWidget);
    expect(find.textContaining('Nhập địa chỉ WebSocket LAN'), findsOneWidget);
    await tester.tap(find.text('Bàn phím · WASD'));
    await tester.pumpAndSettle();
    expect(find.text('Tạo mã QR'), findsNothing);

    await tester.tap(find.text('Bắt đầu Practice'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RacingPage), findsOneWidget);
    final game = tester
        .widget<GameWidget<ApexRacingGame>>(
          find.byType(GameWidget<ApexRacingGame>),
        )
        .game!;
    expect(game.simulation.isRunning, isFalse);
    expect(find.text('Bắt đầu đua'), findsOneWidget);
    await tester.tap(find.text('Bắt đầu đua'));
    await tester.pump();
    expect(game.simulation.isRunning, isTrue);

    await tester.tap(find.byTooltip('Quay lại').last);
    await tester.pumpAndSettle();
    expect(game.simulation.isRunning, isFalse);
    expect(find.text('Chuẩn bị Practice'), findsOneWidget);
    expect(find.byType(RacingPage), findsNothing);

    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.text('Practice'), findsOneWidget);

    await _tap(tester, find.text('Cài đặt').first);
    expect(find.text('racer_01'), findsOneWidget);
    expect(find.text('racer@example.com'), findsOneWidget);
    expect(find.text('Vai trò'), findsOneWidget);

    await _tap(tester, find.text('Chơi').first);
    await tester.tap(find.text('Practice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu Practice'));
    await tester.pump(const Duration(milliseconds: 400));
    final secondGame = tester
        .widget<GameWidget<ApexRacingGame>>(
          find.byType(GameWidget<ApexRacingGame>),
        )
        .game!;
    expect(identical(game, secondGame), isFalse);
    expect(secondGame.simulation.isRunning, isFalse);
    await tester.tap(find.byTooltip('Quay lại').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.text('Practice'), findsOneWidget);
  });

  testWidgets('system back returns from the game to setup and the Play tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _signedInAuth(AppRole.user);
    addTearDown(auth.dispose);
    await _pumpMyApp(
      tester,
      MyApp(authController: auth, catalogRepository: FakeCatalogRepository()),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Chơi').first);
    await tester.tap(find.text('Practice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu Practice'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RacingPage), findsOneWidget);
    final game = tester
        .widget<GameWidget<ApexRacingGame>>(
          find.byType(GameWidget<ApexRacingGame>),
        )
        .game!;
    await tester.tap(find.text('Bắt đầu đua'));
    await tester.pump();
    expect(game.simulation.isRunning, isTrue);

    final nestedPopScopes = tester
        .widgetList<PopScope<void>>(find.byType(PopScope<void>))
        .toList();
    expect(nestedPopScopes.any((scope) => scope.canPop == false), isTrue);
    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await tester.pumpAndSettle();
    expect(game.simulation.isRunning, isFalse);
    expect(find.byType(RacingPage), findsNothing);
    expect(find.text('Chuẩn bị Practice'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Chuẩn bị Practice'), findsNothing);
    expect(find.text('Practice'), findsOneWidget);
  });

  testWidgets('Racing page start and pause buttons toggle simulation state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: RacingPage()));
    await tester.pump();

    await tester.tap(find.text('Bắt đầu đua'));
    await tester.pump();
    expect(find.text('Tạm dừng'), findsOneWidget);

    await tester.tap(find.text('Tạm dừng'));
    await tester.pump();
    expect(find.text('Bắt đầu đua'), findsOneWidget);
  });

  testWidgets('User can open the catalog in read-only mode and log out', (
    tester,
  ) async {
    final auth = _signedInAuth(AppRole.user);
    final catalog = FakeCatalogRepository();
    addTearDown(auth.dispose);
    await _pumpMyApp(
      tester,
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
    await _pumpMyApp(
      tester,
      MyApp(authController: auth, catalogRepository: catalog),
    );
    await tester.pumpAndSettle();

    expect(find.text('Quản trị sản phẩm'), findsOneWidget);
    expect(find.text('Mở Apex RC'), findsOneWidget);
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

    await _tap(tester, find.text('Mở Apex RC'));
    expect(find.text('Chào mừng đến với Apex RC'), findsOneWidget);
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
    await _pumpMyApp(
      tester,
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

  testWidgets('main shell keeps three destinations on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _signedInAuth(AppRole.user);
    addTearDown(auth.dispose);
    await _pumpMyApp(
      tester,
      MyApp(authController: auth, catalogRepository: FakeCatalogRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    final destinations = find.byType(NavigationBar);
    expect(
      find.descendant(of: destinations, matching: find.text('Trang chủ')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: destinations, matching: find.text('Chơi')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: destinations, matching: find.text('Cài đặt')),
      findsOneWidget,
    );
    await _tap(
      tester,
      find.descendant(of: destinations, matching: find.text('Chơi')),
    );
    expect(find.text('Practice'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Practice'));
    await tester.pumpAndSettle();
    expect(find.text('Chuẩn bị Practice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('main shell switches navigation at the 920 pixel breakpoint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(919, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _signedInAuth(AppRole.user);
    addTearDown(auth.dispose);
    await _pumpMyApp(
      tester,
      MyApp(authController: auth, catalogRepository: FakeCatalogRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('ĐIỀU HƯỚNG'), findsNothing);

    tester.view.physicalSize = const Size(920, 1000);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('ĐIỀU HƯỚNG'), findsOneWidget);
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
    await _pumpMyApp(
      tester,
      MyApp(
        authController: auth,
        catalogRepository: FakeCatalogRepository(),
        chatServiceFactory: _FakeChatService.new,
      ),
    );
    await tester.pumpAndSettle();

    await _tap(tester, find.text('Chơi').first);
    await _tap(tester, find.byTooltip('Mở trợ lý Apex RC'));
    expect(find.text('Trợ lý Apex RC'), findsOneWidget);
    await _tap(tester, find.byTooltip('Đóng chat'));

    expect(find.text('Practice'), findsOneWidget);
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
    await _pumpMyApp(
      tester,
      MyApp(
        authController: auth,
        catalogRepository: FakeCatalogRepository(),
        chatServiceFactory: _FakeChatService.new,
      ),
    );
    await tester.pumpAndSettle();

    await _tap(
      tester,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Chơi'),
      ),
    );
    await _tap(tester, find.byTooltip('Mở chat với AI'));
    expect(find.text('Hỏi đáp bằng AI'), findsOneWidget);
    await _tap(tester, find.byTooltip('Quay lại'));

    expect(find.text('Practice'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Chơi'),
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpMyApp(
  WidgetTester tester,
  MyApp app, {
  TargetPlatform platform = TargetPlatform.linux,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
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
