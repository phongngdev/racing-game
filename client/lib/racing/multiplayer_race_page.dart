import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'apex_racing_game.dart';
import 'input/car_input.dart';
import 'input/multiplayer_input_source.dart';
import 'multiplayer_room_session.dart';
import 'simulation/race_simulation.dart';

class MultiplayerRacePage extends StatefulWidget {
  const MultiplayerRacePage({super.key, required this.session, this.onBack});

  final MultiplayerRoomSession session;
  final VoidCallback? onBack;

  @override
  State<MultiplayerRacePage> createState() => _MultiplayerRacePageState();
}

class _MultiplayerRacePageState extends State<MultiplayerRacePage>
    with WidgetsBindingObserver {
  final _keyboard = KeyboardInputSource();
  final _simulation = RaceSimulation();
  final _snapshot = ValueNotifier(const RaceSnapshot());
  final _focusNode = FocusNode(debugLabel: 'Apex RC multiplayer game');
  final _pageFocusNode = FocusNode(debugLabel: 'Apex RC multiplayer page');
  late final MultiplayerInputSource _input;
  late final ApexRacingGame _game;
  StreamSubscription<CollisionEvent>? _collisions;
  Timer? _refreshTimer;
  String? _qrSlot;
  bool _hasBeenFocused = false;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input = MultiplayerInputSource(
      keyboard: _keyboard,
      phoneInputFor: widget.session.remoteFor,
    );
    _applySources();
    _game = ApexRacingGame(
      simulation: _simulation,
      inputSource: _input,
      snapshot: _snapshot,
      onKeyboardEvent: _handleKeyEvent,
    );
    _focusNode.addListener(_focusChanged);
    widget.session.addListener(_sessionChanged);
    widget.session.setGameRunning(false);
    _collisions = _simulation.collisionEvents.listen(_handleCollision);
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  void _focusChanged() {
    if (_focusNode.hasFocus) {
      _hasBeenFocused = true;
    } else if (_hasBeenFocused && _simulation.isRunning) {
      _pause();
    }
  }

  void _applySources() {
    for (final id in const ['p1', 'p2']) {
      final slot = widget.session.slot(id);
      if (slot == null) continue;
      _input.setPhoneSelected(slot.player, slot.source == 'phone');
    }
  }

  void _sessionChanged() {
    _applySources();
    if (widget.session.state == MultiplayerRoomState.closed &&
        _simulation.isRunning) {
      _pause();
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pause();
    }
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.escape) {
        _pause();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyR) {
        _reset();
        return KeyEventResult.handled;
      }
      if (_drivingKeys.contains(key)) _keyboard.handleKey(key, true);
    } else if (event is KeyUpEvent && _drivingKeys.contains(key)) {
      _keyboard.handleKey(key, false);
    }
    return _drivingKeys.contains(key)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _handleCollision(CollisionEvent event) {
    if (!_simulation.isRunning) return;
    for (final player in event.players) {
      final slotId = player == PlayerId.red ? 'p1' : 'p2';
      final slot = widget.session.slot(slotId);
      final remote = widget.session.remoteFor(player);
      if (slot?.source == 'phone' &&
          slot?.connected == true &&
          remote.hasFreshInput) {
        widget.session.sendCollision(slotId);
      }
    }
  }

  void _toggle() {
    if (_simulation.isRunning) {
      _pause();
      return;
    }
    if (!widget.session.canStart) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Kết nối và cân tâm các slot Phone, sau đó nhả pedal.',
            ),
          ),
        );
      return;
    }
    _input.clear();
    widget.session.setGameRunning(true);
    _simulation.setRunning(true);
    _focusNode.requestFocus();
    setState(() {});
  }

  void _pause() {
    _simulation.setRunning(false);
    widget.session.setGameRunning(false);
    _input.clear();
    if (mounted) setState(() {});
  }

  void _reset() {
    _simulation.setRunning(false);
    widget.session.setGameRunning(false);
    _simulation.reset();
    _input.clear();
    _snapshot.value = const RaceSnapshot();
    if (mounted) setState(() {});
  }

  Future<void> _configure(String slotId, String? source) async {
    if (source == null || _simulation.isRunning) return;
    final changed = await widget.session.configureSlot(slotId, source);
    if (!mounted) return;
    _applySources();
    if (!changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.session.error ?? 'Không đổi được nguồn.'),
        ),
      );
    }
    setState(() {});
  }

  void _showQr(String slotId) {
    final invite = widget.session.inviteFor(slotId);
    if (invite == null) {
      if (!widget.session.resetSlot(slotId)) return;
    }
    setState(() => _qrSlot = slotId);
  }

  void _returnToLobby() {
    _pause();
    widget.onBack?.call();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _simulation.setRunning(false);
    widget.session.setGameRunning(false);
    _input.clear();
    _refreshTimer?.cancel();
    _collisions?.cancel();
    widget.session.removeListener(_sessionChanged);
    _focusNode.removeListener(_focusChanged);
    _input.clear();
    _focusNode.dispose();
    _pageFocusNode.dispose();
    _simulation.dispose();
    _snapshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _pageFocusNode,
      child: Scaffold(
        backgroundColor: const Color(0xFF111916),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Về lobby',
                      onPressed: _returnToLobby,
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'MULTIPLAYER',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      widget.session.roomId == null
                          ? 'PHÒNG ĐANG ĐÓNG'
                          : 'ROOM ${widget.session.roomId!.substring(0, 8)}',
                      style: const TextStyle(
                        color: Color(0xFF9BA89E),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
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
                      const SizedBox(width: 14),
                      SizedBox(width: 300, child: _rightPanel()),
                    ],
                  ),
                ),
                if (_qrSlot case final slotId?) _qrPanel(slotId),
                const SizedBox(height: 8),
                const Text(
                  'WASD · P1 xe đỏ      ↑ ↓ ← → · P2 xe xanh      ESC · pause      R · reset',
                  style: TextStyle(color: Color(0xFF86918A), fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rightPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final id in const ['p1', 'p2']) ...[
        _slotPanel(id),
        const SizedBox(height: 10),
      ],
      _speedCard(),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: _toggle,
        icon: Icon(_simulation.isRunning ? Icons.pause : Icons.play_arrow),
        label: Text(_simulation.isRunning ? 'Tạm dừng' : 'Bắt đầu đua'),
      ),
      const SizedBox(height: 7),
      OutlinedButton.icon(
        onPressed: _reset,
        icon: const Icon(Icons.restart_alt_rounded),
        label: const Text('Reset xe'),
      ),
      if (widget.session.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            widget.session.error!,
            style: const TextStyle(color: Color(0xFFFF9C92), fontSize: 11),
          ),
        ),
    ],
  );

  Widget _slotPanel(String slotId) {
    final slot = widget.session.slot(slotId);
    final red = slotId == 'p1';
    final source = slot?.source ?? (red ? 'phone' : 'keyboard');
    final connected = slot?.connected == true;
    final remote = widget.session.remoteFor(red ? PlayerId.red : PlayerId.blue);
    final label = connected
        ? remote.hasFreshInput
              ? 'Connected · ${slot?.stage ?? 'checking'}'
              : 'Connected · chờ input'
        : slot?.reserved == true
        ? 'Disconnected · đang giữ slot'
        : source == 'keyboard'
        ? 'Keyboard · Web'
        : 'Disconnected';
    final color = red ? const Color(0xFFFF696E) : const Color(0xFF68A4FF);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2620),
        border: Border.all(color: const Color(0xFF2B3830)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 5, backgroundColor: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${slotId.toUpperCase()} · ${red ? 'Xe đỏ' : 'Xe xanh'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF9BA89E), fontSize: 11),
          ),
          const SizedBox(height: 6),
          DropdownButton<String>(
            value: source,
            isExpanded: true,
            dropdownColor: const Color(0xFF1B2620),
            style: const TextStyle(color: Colors.white),
            items: const [
              DropdownMenuItem(value: 'phone', child: Text('Phone')),
              DropdownMenuItem(value: 'keyboard', child: Text('Keyboard')),
            ],
            onChanged:
                _simulation.isRunning ||
                    widget.session.isSlotConfiguring(slotId)
                ? null
                : (value) => _configure(slotId, value),
          ),
          if (source == 'phone' && !connected)
            TextButton.icon(
              onPressed: _simulation.isRunning ? null : () => _showQr(slotId),
              icon: const Icon(Icons.qr_code_2_rounded, size: 17),
              label: const Text('Hiện QR / nối lại'),
            ),
        ],
      ),
    );
  }

  Widget _speedCard() => AnimatedBuilder(
    animation: _snapshot,
    builder: (context, _) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2620),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'P1 ${_snapshot.value.redSpeed.round()} u/s',
              style: const TextStyle(color: Color(0xFFFF696E)),
            ),
          ),
          Expanded(
            child: Text(
              'P2 ${_snapshot.value.blueSpeed.round()} u/s',
              style: const TextStyle(color: Color(0xFF68A4FF)),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _qrPanel(String slotId) {
    final invite = widget.session.inviteFor(slotId);
    if (invite == null) {
      return TextButton(
        onPressed: () => setState(() => _qrSlot = null),
        child: Text('QR $slotId đang được tạo · Ẩn'),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          QrImageView(data: invite.toQrValue(), size: 112),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quét QR ${slotId.toUpperCase()} bằng Android'),
              const Text('Hạn 5 phút'),
              TextButton(
                onPressed: () => setState(() => _qrSlot = null),
                child: const Text('Ẩn QR'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
