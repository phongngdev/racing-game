import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apex_racing_game.dart';
import '../controller/controller_config.dart';
import '../controller/controller_connection.dart';
import '../controller/controller_protocol.dart';
import 'input/car_input.dart';
import 'input/remote_input_source.dart';
import 'input/selectable_input_source.dart';
import 'simulation/race_simulation.dart';

class RacingPage extends StatefulWidget {
  const RacingPage({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<RacingPage> createState() => _RacingPageState();
}

class _RacingPageState extends State<RacingPage> with WidgetsBindingObserver {
  static final _drivingKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.keyM,
  };

  final _keyboard = KeyboardInputSource();
  final _remote = RemoteInputSource();
  late final SelectableInputSource _input;
  final _simulation = RaceSimulation();
  final _snapshot = ValueNotifier(const RaceSnapshot());
  final _pageFocusNode = FocusNode(debugLabel: 'Apex RC racing page');
  final _focusNode = FocusNode(debugLabel: 'Apex RC racing game');
  late final ApexRacingGame _game;
  ControllerConnection? _connection;
  Timer? _remoteWatchdog;
  String _controllerError = '';
  bool _hasBeenFocused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input = SelectableInputSource(keyboard: _keyboard, remote: _remote);
    _game = ApexRacingGame(
      simulation: _simulation,
      inputSource: _input,
      snapshot: _snapshot,
      onKeyboardEvent: _handleKeyEvent,
    );
    _focusNode.addListener(_handleFocusChange);
    final uri = ControllerConfig.parse(ControllerConfig.webSocketUrl);
    if (uri != null) {
      _connection = ControllerConnection(
        uri: uri,
        role: ControllerRole.game,
        onEvent: _handleControllerMessage,
      )..addListener(_handleConnectionChange);
      _connection!.connect();
    } else if (ControllerConfig.webSocketUrl.isNotEmpty) {
      _controllerError = 'CONTROLLER_WS_URL chưa hợp lệ.';
    }
    _remoteWatchdog = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_simulation.isRunning &&
          _input.mode == RacingInputMode.phone &&
          !_remote.hasFreshInput) {
        _controllerError = 'Mất tín hiệu điện thoại · cuộc đua đã tạm dừng.';
        _pauseRace();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _pageFocusNode.dispose();
    _remoteWatchdog?.cancel();
    _connection?.removeListener(_handleConnectionChange);
    _connection?.dispose();
    _input.clear();
    _simulation.dispose();
    _snapshot.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pauseRace();
    }
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      _hasBeenFocused = true;
    } else if (_hasBeenFocused && _simulation.isRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_pageFocusNode.hasFocus) _pauseRace();
      });
    }
  }

  void _handleConnectionChange() {
    if (_connection?.isConnected != true) {
      _remote.setConnected(false);
      if (_input.mode == RacingInputMode.phone && _simulation.isRunning) {
        _controllerError = 'Mất kết nối relay · cuộc đua đã tạm dừng.';
        _pauseRace();
      }
    }
    if (mounted) setState(() {});
  }

  void _handleControllerMessage(ControllerMessage message) {
    final data = message.data;
    switch (message.event) {
      case ControllerEvents.status:
        if (data['phoneConnected'] == true && data['generation'] is int) {
          _remote.setConnected(true, generation: data['generation'] as int);
          _controllerError = '';
        } else if (data['phoneConnected'] == false) {
          _remote.setConnected(false);
          if (_input.mode == RacingInputMode.phone && _simulation.isRunning) {
            _controllerError = 'Điện thoại đã ngắt kết nối · cuộc đua đã dừng.';
            _pauseRace();
          }
        }
        break;
      case ControllerEvents.input:
        final seq = data['seq'];
        final generation = data['generation'];
        final steering = data['steering'];
        final throttle = data['throttle'];
        final brake = data['brake'];
        if (seq is int &&
            generation is int &&
            steering is num &&
            throttle is num &&
            brake is num) {
          _remote.accept(
            sequence: seq,
            generation: generation,
            steering: steering.toDouble(),
            throttle: throttle.toDouble(),
            brake: brake.toDouble(),
          );
        }
        break;
      case ControllerEvents.unavailable:
        if (data['generation'] == _remote.generation) {
          _remote.markUnavailable();
          if (_input.mode == RacingInputMode.phone && _simulation.isRunning) {
            _controllerError = 'Cảm biến chưa sẵn sàng · cuộc đua đã dừng.';
            _pauseRace();
          }
        }
        break;
      case ControllerEvents.error:
        _controllerError = data['code'] == 'role_in_use'
            ? 'Đã có một phiên đua khác kết nối relay.'
            : 'Relay từ chối kết nối.';
        unawaited(_connection?.disconnect());
        break;
    }
    if (mounted) setState(() {});
  }

  void _selectInputMode(RacingInputMode mode) {
    if (mode == _input.mode) return;
    _pauseRace();
    _input.select(mode);
    _controllerError = '';
    if (mounted) setState(() {});
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.escape) {
        _pauseRace();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyR) {
        _resetRace();
        return KeyEventResult.handled;
      }
      if (_isDrivingKey(key)) _keyboard.handleKey(key, true);
    } else if (event is KeyUpEvent && _isDrivingKey(key)) {
      _keyboard.handleKey(key, false);
    }
    return _isDrivingKey(key) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  bool _isDrivingKey(LogicalKeyboardKey key) => _drivingKeys.contains(key);

  void _toggleRace() {
    if (_simulation.isRunning) {
      _pauseRace();
    } else {
      if (!_input.canStart) {
        _controllerError = _input.mode == RacingInputMode.phone
            ? 'Kết nối điện thoại, cân tâm rồi nhả ga/phanh trước khi bắt đầu.'
            : 'Chưa nhận được input điều khiển.';
        setState(() {});
        return;
      }
      _controllerError = '';
      _simulation.setRunning(true);
      _focusNode.requestFocus();
      setState(() {});
    }
  }

  void _pauseRace() {
    if (!_simulation.isRunning) {
      _input.clear();
      return;
    }
    _simulation.setRunning(false);
    _input.clear();
    if (mounted) setState(() {});
  }

  void _resetRace() {
    _simulation.reset();
    _input.clear();
    _snapshot.value = const RaceSnapshot();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 860;
    return Focus(
      focusNode: _pageFocusNode,
      child: Scaffold(
        backgroundColor: const Color(0xFF111916),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              wide ? 26 : 15,
              14,
              wide ? 26 : 15,
              18,
            ),
            child: Column(
              children: [
                _header(wide),
                const SizedBox(height: 14),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _gameField()),
                            const SizedBox(width: 18),
                            SizedBox(width: 250, child: _controlPanel()),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(child: _gameField()),
                            const SizedBox(height: 12),
                            _compactControls(),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                _footer(wide),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool wide) => Row(
    children: [
      if (widget.onBack != null) ...[
        IconButton(
          tooltip: 'Quay lại',
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFFE8ECE8)),
        ),
        const SizedBox(width: 5),
      ],
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFB9F34A),
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(
          Icons.sports_motorsports_rounded,
          color: Color(0xFF18220E),
        ),
      ),
      const SizedBox(width: 11),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'APEX RC',
            style: TextStyle(
              color: Color(0xFFF1F4EF),
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            'WEB RACING PROTOTYPE',
            style: TextStyle(
              color: Color(0xFF86918A),
              fontSize: 9,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
      const Spacer(),
      if (wide)
        const Text(
          'LOCAL · 2 PLAYERS',
          style: TextStyle(
            color: Color(0xFF9BA89E),
            fontSize: 10,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
    ],
  );

  Widget _gameField() => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(
        constraints.maxWidth,
        constraints.maxHeight *
            RaceTrackLayout.worldWidth /
            RaceTrackLayout.worldHeight,
      );
      return Center(
        child: SizedBox(
          width: width,
          height:
              width * RaceTrackLayout.worldHeight / RaceTrackLayout.worldWidth,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GameWidget<ApexRacingGame>(
              game: _game,
              focusNode: _focusNode,
              autofocus: true,
              backgroundBuilder: (_) =>
                  const ColoredBox(color: Color(0xFF193323)),
            ),
          ),
        ),
      );
    },
  );

  Widget _controlPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _inputModeCard(),
      const SizedBox(height: 12),
      _speedCard(),
      const SizedBox(height: 12),
      _actionCard(),
      const SizedBox(height: 12),
      Expanded(child: _keyCard()),
    ],
  );

  Widget _compactControls() => Column(
    children: [
      _inputModeCard(),
      const SizedBox(height: 10),
      _speedCard(),
      const SizedBox(height: 10),
      _actionButtons(),
    ],
  );

  Widget _inputModeCard() => _PanelCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ĐIỀU KHIỂN XE ĐỎ',
          style: TextStyle(
            color: Color(0xFF9BA89E),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Bàn phím'),
              selected: _input.mode == RacingInputMode.keyboard,
              onSelected: (_) => _selectInputMode(RacingInputMode.keyboard),
            ),
            ChoiceChip(
              label: const Text('Điện thoại'),
              selected: _input.mode == RacingInputMode.phone,
              onSelected: (_) => _selectInputMode(RacingInputMode.phone),
            ),
          ],
        ),
        Text(
          _controllerError.isNotEmpty
              ? _controllerError
              : _remote.hasFreshInput
              ? 'Điện thoại đang gửi tín hiệu.'
              : _remote.connected
              ? 'Đang chờ tín hiệu từ điện thoại.'
              : ControllerConfig.webSocketUrl.isEmpty
              ? 'Chưa cấu hình CONTROLLER_WS_URL.'
              : _connection?.isConnected == true
              ? 'Relay đã nối · chờ điện thoại.'
              : 'Đang kết nối relay…',
          style: const TextStyle(color: Color(0xFF96A399), fontSize: 10),
        ),
      ],
    ),
  );

  Widget _speedCard() => _PanelCard(
    child: AnimatedBuilder(
      animation: _snapshot,
      builder: (context, _) => Row(
        children: [
          Expanded(
            child: _SpeedReadout(
              label: 'PLAYER 1 · RED',
              value: _snapshot.value.redSpeed.round(),
              color: const Color(0xFFFF696E),
            ),
          ),
          Container(width: 1, height: 42, color: const Color(0xFF29342E)),
          Expanded(
            child: _SpeedReadout(
              label: 'PLAYER 2 · BLUE',
              value: _snapshot.value.blueSpeed.round(),
              color: const Color(0xFF68A4FF),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _actionCard() => _PanelCard(child: _actionButtons(vertical: true));

  Widget _actionButtons({bool vertical = false}) {
    final startButton = FilledButton.icon(
      onPressed: _toggleRace,
      icon: Icon(
        _simulation.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
      ),
      label: Text(_simulation.isRunning ? 'Tạm dừng' : 'Bắt đầu đua'),
      style: FilledButton.styleFrom(
        foregroundColor: const Color(0xFF17200E),
        backgroundColor: const Color(0xFFB9F34A),
        minimumSize: const Size(0, 46),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
    final resetButton = OutlinedButton.icon(
      onPressed: _resetRace,
      icon: const Icon(Icons.restart_alt_rounded, size: 19),
      label: const Text('Reset xe'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFE4EAE5),
        side: const BorderSide(color: Color(0xFF39473E)),
        minimumSize: const Size(0, 44),
      ),
    );
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          startButton,
          const SizedBox(height: 9),
          resetButton,
          const SizedBox(height: 12),
          const Text(
            'Nhấn ESC để dừng ngay.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF96A399), fontSize: 11),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: startButton),
        const SizedBox(width: 9),
        Expanded(child: resetButton),
      ],
    );
  }

  Widget _keyCard() => _PanelCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ĐIỀU KHIỂN',
          style: TextStyle(
            color: Color(0xFF9BA89E),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 13),
        const _KeyLegend(
          color: Color(0xFFFF696E),
          name: 'Player 1 · xe đỏ',
          controls: 'W A S D',
          horn: 'Q · còi chưa bật',
        ),
        const SizedBox(height: 17),
        const _KeyLegend(
          color: Color(0xFF68A4FF),
          name: 'Player 2 · xe xanh',
          controls: '← ↑ ↓ →',
          horn: 'M · còi chưa bật',
        ),
        const Spacer(),
        const Text(
          'GA   tăng tốc      PHANH   giảm tốc\nA / ←   trái      D / →   phải',
          style: TextStyle(
            color: Color(0xFF86918A),
            fontSize: 10,
            height: 1.8,
            fontFamily: 'monospace',
          ),
        ),
      ],
    ),
  );

  Widget _footer(bool wide) => Row(
    children: [
      const Icon(
        Icons.info_outline_rounded,
        size: 14,
        color: Color(0xFF7E8A81),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          wide
              ? 'Giữ game được focus để lái · Click vào đường đua nếu bàn phím chưa phản hồi.'
              : 'Giữ game được focus để lái · Click đường đua nếu cần.',
          style: const TextStyle(color: Color(0xFF7E8A81), fontSize: 10),
        ),
      ),
      const Text(
        'ARCADE PHYSICS',
        style: TextStyle(
          color: Color(0xFF56635A),
          fontSize: 9,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFF1B2620),
      border: Border.all(color: const Color(0xFF2B3830)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

class _SpeedReadout extends StatelessWidget {
  const _SpeedReadout({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF8E9A90),
            fontSize: 8,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontSize: 25,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 5),
              const Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text(
                  'u/s',
                  style: TextStyle(color: Color(0xFF9AA49C), fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _KeyLegend extends StatelessWidget {
  const _KeyLegend({
    required this.color,
    required this.name,
    required this.controls,
    required this.horn,
  });

  final Color color;
  final String name;
  final String controls;
  final String horn;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            name,
            style: const TextStyle(
              color: Color(0xFFE4EAE5),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        controls,
        style: const TextStyle(
          color: Color(0xFFB9F34A),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          fontFamily: 'monospace',
        ),
      ),
      Text(horn, style: const TextStyle(color: Color(0xFF849087), fontSize: 9)),
    ],
  );
}
