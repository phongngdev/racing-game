import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_services.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_pages.dart';
import 'auth/session_user.dart';
import 'catalog/catalog_page.dart';
import 'catalog/catalog_repository.dart';
import 'chat/chat_controller.dart';
import 'chat/chat_widgets.dart';
import 'chat/lm_studio_service.dart';
import 'pages/app_pages.dart';
import 'pages/android_entry_page.dart';
import 'pages/practice_setup_page.dart';
import 'pages/multiplayer_setup_page.dart';
import 'controller/phone_controller_flow_page.dart';
import 'controller/qr_scanner_page.dart';
import 'controller/room_pairing_payload.dart';
import 'racing/practice_controller_session.dart';
import 'racing/multiplayer_room_session.dart';
import 'racing/multiplayer_race_page.dart';
import 'racing/race_mode.dart';
import 'racing/racing_page.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.authController,
    this.catalogRepository,
    this.chatServiceFactory,
  }) : assert((authController == null) == (catalogRepository == null));

  final AuthController? authController;
  final CatalogRepository? catalogRepository;
  final ChatServiceFactory? chatServiceFactory;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppServices? _services;
  late final AuthController _auth;
  late final CatalogRepository _catalog;

  @override
  void initState() {
    super.initState();
    if (widget.authController != null) {
      _auth = widget.authController!;
      _catalog = widget.catalogRepository!;
    } else {
      _services = AppServices.createDefault();
      _auth = _services!.auth;
      _catalog = _services!.catalog;
    }
  }

  @override
  void dispose() {
    _services?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF3267E3);
    return MaterialApp(
      title: 'Apex RC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
          surface: const Color(0xFFFFFFFF),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        fontFamily: 'Arial',
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            color: Color(0xFF172033),
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.25,
            color: Color(0xFF172033),
          ),
          bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF667085)),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE8EBF0)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F8FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: accent, width: 1.5),
          ),
        ),
      ),
      home: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? Builder(
              builder: (context) => AndroidEntryPage(
                onOpenApp: () => unawaited(
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      settings: const RouteSettings(name: '/app'),
                      builder: (_) => _AuthGate(
                        auth: _auth,
                        catalog: _catalog,
                        chatServiceFactory: widget.chatServiceFactory,
                      ),
                    ),
                  ),
                ),
                onScanQr: () => unawaited(_scanControllerQr(context)),
              ),
            )
          : _AuthGate(
              auth: _auth,
              catalog: _catalog,
              chatServiceFactory: widget.chatServiceFactory,
            ),
    );
  }

  Future<void> _scanControllerQr(BuildContext context) async {
    final pairing = await Navigator.of(context).push<ScannedControllerPayload>(
      MaterialPageRoute<ScannedControllerPayload>(
        settings: const RouteSettings(name: '/controller/scan'),
        builder: (_) => const QrScannerPage(),
      ),
    );
    if (!context.mounted || pairing == null) return;
    final practicePayload = switch (pairing) {
      PracticeControllerPayload(:final payload) => payload,
      RoomControllerPayload() => null,
    };
    final roomPayload = switch (pairing) {
      PracticeControllerPayload() => null,
      RoomControllerPayload(:final payload) => payload,
    };
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/controller'),
        builder: (routeContext) => PhoneControllerFlowPage(
          initialPairingPayload: practicePayload,
          initialRoomPairingPayload: roomPayload,
          onExit: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({
    required this.auth,
    required this.catalog,
    this.chatServiceFactory,
  });

  final AuthController auth;
  final CatalogRepository catalog;
  final ChatServiceFactory? chatServiceFactory;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  int? _navigatorSessionVersion;

  @override
  void initState() {
    super.initState();
    unawaited(widget.auth.initialize());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.auth,
    builder: (context, _) => switch (widget.auth.status) {
      AuthStatus.restoring => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      AuthStatus.configurationError => SessionMessagePage(
        title: 'Cần cấu hình API',
        message: widget.auth.message ?? 'API_BASE_URL chưa hợp lệ.',
      ),
      AuthStatus.unavailable => SessionMessagePage(
        title: 'Chưa kết nối được máy chủ',
        message: widget.auth.message ?? 'Hãy kiểm tra kết nối rồi thử lại.',
        actionLabel: 'Thử lại',
        onAction: () => unawaited(widget.auth.initialize()),
        secondaryLabel: 'Đăng xuất',
        onSecondary: () => unawaited(widget.auth.logout()),
      ),
      AuthStatus.signedOut => LoginPage(auth: widget.auth),
      AuthStatus.signedIn => _authenticatedNavigator(
        widget.auth,
        widget.catalog,
        widget.chatServiceFactory,
      ),
    },
  );

  Widget _authenticatedNavigator(
    AuthController auth,
    CatalogRepository catalog,
    ChatServiceFactory? chatServiceFactory,
  ) {
    final user = auth.user!;
    if (_navigatorSessionVersion != auth.sessionVersion) {
      _navigatorSessionVersion = auth.sessionVersion;
      _navigatorKey = GlobalKey<NavigatorState>();
    }
    return NavigatorPopHandler<void>(
      onPopWithResult: (_) => _navigatorKey.currentState?.pop(),
      child: Navigator(
        key: _navigatorKey,
        onGenerateInitialRoutes: (navigator, initialRoute) => [
          MaterialPageRoute<void>(
            settings: RouteSettings(name: initialRoute),
            builder: (context) => user.role == AppRole.admin
                ? CatalogPage(
                    repository: catalog,
                    auth: auth,
                    canManage: true,
                    onReturnToRacing: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DemoShell(
                          auth: auth,
                          chatServiceFactory: chatServiceFactory,
                          onReturnToAdmin: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  )
                : DemoShell(
                    auth: auth,
                    chatServiceFactory: chatServiceFactory,
                    onOpenCatalog: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            CatalogPage(repository: catalog, auth: auth),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class DemoShell extends StatefulWidget {
  const DemoShell({
    super.key,
    required this.auth,
    this.onOpenCatalog,
    this.onReturnToAdmin,
    this.chatServiceFactory,
  });

  final AuthController auth;
  final VoidCallback? onOpenCatalog;
  final VoidCallback? onReturnToAdmin;
  final ChatServiceFactory? chatServiceFactory;

  @override
  State<DemoShell> createState() => _DemoShellState();
}

class _DemoShellState extends State<DemoShell> {
  int _selectedIndex = 0;
  bool _practiceSetupOpen = false;
  bool _practiceGameOpen = false;
  bool _multiplayerSetupOpen = false;
  bool _multiplayerGameOpen = false;
  late final ChatController _chatController;

  @override
  void initState() {
    super.initState();
    _chatController = ChatController(
      (widget.chatServiceFactory ?? LMStudioService.new)(),
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  static const _destinations = <_DestinationData>[
    _DestinationData('Trang chủ', Icons.home_rounded),
    _DestinationData('Chơi', Icons.sports_esports_rounded),
    _DestinationData('Cài đặt', Icons.settings_rounded),
  ];

  void _goTo(int index) => setState(() => _selectedIndex = index);

  void _openPhoneController() {
    final navigator = Navigator.of(context);
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/controller'),
          builder: (routeContext) => PhoneControllerFlowPage(
            onExit: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    );
  }

  Future<void> _openPractice() async {
    if (_practiceSetupOpen) return;
    _practiceSetupOpen = true;
    final navigator = Navigator.of(context);
    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/practice/setup'),
          builder: (_) => PracticeSetupPage(
            onBack: () => navigator.pop(),
            onStart: (session) => _openPracticeGame(navigator, session),
          ),
        ),
      );
    } finally {
      _practiceSetupOpen = false;
    }
  }

  Future<void> _openPracticeGame(
    NavigatorState navigator,
    PracticeControllerSession? session,
  ) async {
    if (_practiceGameOpen) return;
    _practiceGameOpen = true;
    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/practice/game'),
          builder: (_) => RacingPage(
            mode: RacingPageMode.practice,
            practiceSession: session,
            onBack: () => navigator.pop(),
          ),
        ),
      );
    } finally {
      _practiceGameOpen = false;
    }
  }

  Future<void> _openMultiplayer() async {
    if (_multiplayerSetupOpen) return;
    _multiplayerSetupOpen = true;
    final navigator = Navigator.of(context);
    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/multiplayer/lobby'),
          builder: (_) => MultiplayerSetupPage(
            onBack: () => navigator.pop(),
            onStart: (session, mode) =>
                _openMultiplayerGame(navigator, session, mode),
          ),
        ),
      );
    } finally {
      _multiplayerSetupOpen = false;
    }
  }

  Future<void> _openMultiplayerGame(
    NavigatorState navigator,
    MultiplayerRoomSession session,
    RaceMode mode,
  ) async {
    if (_multiplayerGameOpen) return;
    _multiplayerGameOpen = true;
    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/multiplayer/game'),
          builder: (_) => MultiplayerRacePage(
            session: session,
            mode: mode,
            onBack: () => navigator.pop(),
          ),
        ),
      );
    } finally {
      _multiplayerGameOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 920;
    final pages = <Widget>[
      HomePage(onPlay: () => _goTo(1)),
      PlayPage(
        onPractice: () => unawaited(_openPractice()),
        onMultiplayer: () => unawaited(_openMultiplayer()),
      ),
      SettingsPage(
        user: widget.auth.user!,
        onOpenPhoneController:
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? _openPhoneController
            : null,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              _DesktopNavigation(
                selectedIndex: _selectedIndex,
                destinations: _destinations,
                onSelected: _goTo,
              ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    wide: wide,
                    currentTitle: _destinations[_selectedIndex].label,
                    auth: widget.auth,
                    onOpenCatalog: widget.onOpenCatalog,
                    onReturnToAdmin: widget.onReturnToAdmin,
                  ),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        IndexedStack(index: _selectedIndex, children: pages),
                        ChatbotHost(controller: _chatController, wide: wide),
                      ],
                    ),
                  ),
                  if (!wide)
                    NavigationBar(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _goTo,
                      height: 70,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysShow,
                      destinations: [
                        for (final item in _destinations)
                          NavigationDestination(
                            icon: Icon(item.icon),
                            label: item.label,
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationData {
  const _DestinationData(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<_DestinationData> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE8EBF0))),
      ),
      padding: const EdgeInsets.fromLTRB(18, 24, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandMark(),
          const SizedBox(height: 38),
          const _Eyebrow('ĐIỀU HƯỚNG'),
          const SizedBox(height: 12),
          for (var i = 0; i < destinations.length; i++)
            _NavigationItem(
              item: destinations[i],
              selected: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
          const Spacer(),
          const Text(
            'Apex RC',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF667085),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ứng dụng đua xe RC',
            style: TextStyle(fontSize: 11, color: Color(0xFF858D9B)),
          ),
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _DestinationData item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF3267E3) : const Color(0xFF667085);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? const Color(0xFFEEF3FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
            child: Row(
              children: [
                Icon(item.icon, size: 19, color: color),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? const Color(0xFF254FB2) : color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.wide,
    required this.currentTitle,
    required this.auth,
    this.onOpenCatalog,
    this.onReturnToAdmin,
  });
  final bool wide;
  final String currentTitle;
  final AuthController auth;
  final VoidCallback? onOpenCatalog;
  final VoidCallback? onReturnToAdmin;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: EdgeInsets.symmetric(horizontal: wide ? 30 : 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8EBF0))),
      ),
      child: Row(
        children: [
          if (!wide) const _BrandMark(compact: true),
          if (!wide) const SizedBox(width: 16),
          Expanded(
            child: Text(
              currentTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontSize: wide ? 18 : 14),
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'Tài khoản ${auth.user?.username ?? ''}',
            onSelected: (value) {
              if (value == 'catalog') onOpenCatalog?.call();
              if (value == 'admin') onReturnToAdmin?.call();
              if (value == 'logout') unawaited(auth.logout());
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  '${auth.user?.username ?? ''} · ${auth.user?.role.name == 'admin' ? 'Admin' : 'User'}',
                ),
              ),
              if (onOpenCatalog != null)
                const PopupMenuItem(
                  value: 'catalog',
                  child: Text('Sản phẩm & danh mục'),
                ),
              if (onReturnToAdmin != null)
                const PopupMenuItem(
                  value: 'admin',
                  child: Text('Quay lại quản trị'),
                ),
              const PopupMenuItem(value: 'logout', child: Text('Đăng xuất')),
            ],
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: CircleAvatar(
                radius: 16,
                child: Text(
                  (auth.user?.username ?? '?').substring(0, 1).toUpperCase(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF3267E3),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(
            Icons.sports_motorsports_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        if (!compact)
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'APEX RC',
                style: TextStyle(
                  fontSize: 15,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF172033),
                ),
              ),
              Text(
                'RACING CONTROL',
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 1.1,
                  color: Color(0xFF8A93A2),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontSize: 10,
      letterSpacing: 1.1,
      fontWeight: FontWeight.w700,
      color: Color(0xFF98A0AD),
    ),
  );
}
