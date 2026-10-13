import 'dart:async';

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
import 'pages/collision_page.dart';
import 'pages/connect_page.dart';
import 'pages/race_page.dart';
import 'pages/result_page.dart';
import 'pages/tuning_page.dart';

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
      title: 'Apex RC · Bản trình diễn',
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
      home: _AuthGate(
        auth: _auth,
        catalog: _catalog,
        chatServiceFactory: widget.chatServiceFactory,
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
    return Navigator(
      key: ValueKey(auth.sessionVersion),
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
    _DestinationData('Kết nối', Icons.link_rounded, '01'),
    _DestinationData('Tinh chỉnh', Icons.tune_rounded, '02'),
    _DestinationData('Đường đua', Icons.speed_rounded, '03'),
    _DestinationData('Va chạm', Icons.warning_amber_rounded, '04'),
    _DestinationData('Kết quả', Icons.emoji_events_outlined, '05'),
  ];

  void _goTo(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 920;
    final pages = <Widget>[
      ConnectPage(onConnected: () => _goTo(1)),
      TuningPage(onStartRace: () => _goTo(2)),
      RacePage(onCollision: () => _goTo(3), onFinish: () => _goTo(4)),
      CollisionPage(onRecovered: () => _goTo(2)),
      ResultPage(onRematch: () => _goTo(1)),
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
                    currentStep: _selectedIndex + 1,
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
  const _DestinationData(this.label, this.icon, this.number);
  final String label;
  final IconData icon;
  final String number;
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
          const _Eyebrow('BẢN ĐIỀU KHIỂN'),
          const SizedBox(height: 12),
          for (var i = 0; i < destinations.length; i++)
            _NavigationItem(
              item: destinations[i],
              selected: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
          const Spacer(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Color(0xFF3267E3),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Bản demo giao diện',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF172033),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Dữ liệu minh họa · Web',
                    style: TextStyle(fontSize: 11, color: Color(0xFF858D9B)),
                  ),
                ],
              ),
            ),
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
                Text(
                  item.number,
                  style: TextStyle(fontSize: 10, color: color.withAlpha(150)),
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
    required this.currentStep,
    required this.auth,
    this.onOpenCatalog,
    this.onReturnToAdmin,
  });
  final bool wide;
  final int currentStep;
  final AuthController auth;
  final VoidCallback? onOpenCatalog;
  final VoidCallback? onReturnToAdmin;

  @override
  Widget build(BuildContext context) {
    final small = MediaQuery.sizeOf(context).width < 440;
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
          if (!wide) const Spacer(),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF31B47B),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            small ? 'Web demo' : 'Hệ thống sẵn sàng',
            style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
          ),
          if (!small) ...[
            const SizedBox(width: 18),
            Container(width: 1, height: 20, color: const Color(0xFFE8EBF0)),
            const SizedBox(width: 18),
            Text(
              'BƯỚC $currentStep / 5',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: Color(0xFF8A93A2),
              ),
            ),
          ],
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
