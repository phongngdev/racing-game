import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'apex_racing_game.dart';
import 'input/car_input.dart';
import 'input/multiplayer_input_source.dart';
import 'lap/lap_player_tracker.dart';
import 'lap/lap_race_session.dart';
import 'lap/lap_race_track.dart';
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
  final _snapshot = ValueNotifier(const RaceSnapshot());
  final _focusNode = FocusNode(debugLabel: 'Apex RC multiplayer game');
  final _pageFocusNode = FocusNode(debugLabel: 'Apex RC multiplayer page');
  late final RaceSimulation _simulation;
  late final MultiplayerInputSource _input;
  late final LapRaceSession _race;
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

  static const _track = LapRaceTrack.standard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _simulation = RaceSimulation(
      redStartPosition: Vector2(_track.redGrid.x, _track.redGrid.y),
      blueStartPosition: Vector2(_track.blueGrid.x, _track.blueGrid.y),
    );
    _input = MultiplayerInputSource(
      keyboard: _keyboard,
      phoneInputFor: widget.session.remoteFor,
    );
    _applySources();
    _race = LapRaceSession(
      simulation: _simulation,
      inputSource: _input,
      canStart: () => widget.session.canStart,
      controllersAvailable: _controllersAvailable,
      clearInputs: _input.clear,
      setGameRunning: widget.session.setGameRunning,
    );
    _game = ApexRacingGame(
      simulation: _simulation,
      inputSource: _input,
      snapshot: _snapshot,
      onKeyboardEvent: _handleKeyEvent,
      lapTrack: _track,
      onFrameUpdate: _race.advanceFrame,
    );
    _focusNode.addListener(_focusChanged);
    widget.session.addListener(_sessionChanged);
    _race.addListener(_raceChanged);
    _collisions = _simulation.collisionEvents.listen(_handleCollision);
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  bool _controllersAvailable() {
    if (!widget.session.isConnected) return false;
    for (final slot in widget.session.slots.values) {
      if (slot.source != 'phone') continue;
      final remote = widget.session.remoteFor(slot.player);
      if (!slot.connected ||
          slot.stage != 'ready' ||
          !remote.connected ||
          !remote.hasFreshInput) {
        return false;
      }
    }
    return widget.session.slots.length == 2;
  }

  void _focusChanged() {
    if (_focusNode.hasFocus) {
      _hasBeenFocused = true;
    } else if (_hasBeenFocused && _race.canPause) {
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
    final shownSlot = _qrSlot;
    if (shownSlot != null) {
      final slot = widget.session.slot(shownSlot);
      if (slot?.connected == true || slot?.source != 'phone') {
        _qrSlot = null;
      }
    }
    if (widget.session.state == MultiplayerRoomState.closed) {
      _race.endForRoomClose();
    }
    if (mounted) setState(() {});
  }

  void _raceChanged() {
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
        if (_race.phase == LapRacePhase.paused) {
          _resume();
        } else {
          _pause();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyR) {
        _race.restartFromPause();
        return KeyEventResult.handled;
      }
      if (_race.phase == LapRacePhase.racing && _drivingKeys.contains(key)) {
        _keyboard.handleKey(key, true);
      }
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
    switch (_race.phase) {
      case LapRacePhase.ready:
        if (_race.canStartRace) {
          if (_race.startCountdown()) _focusNode.requestFocus();
        } else {
          _race.pause();
        }
      case LapRacePhase.countdown:
      case LapRacePhase.racing:
        _race.pause();
      case LapRacePhase.paused:
        _resume();
      case LapRacePhase.finished:
        return;
    }
  }

  void _pause() {
    _race.pause();
  }

  void _resume() {
    if (_race.resume()) _focusNode.requestFocus();
  }

  Future<void> _configure(String slotId, String? source) async {
    if (source == null || _race.phase != LapRacePhase.paused) return;
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
    if (_race.phase != LapRacePhase.paused) return;
    final invite = widget.session.inviteFor(slotId);
    if (invite == null) {
      if (!widget.session.resetSlot(slotId)) return;
    }
    setState(() => _qrSlot = slotId);
  }

  void _returnToLobby() {
    if (_race.phase == LapRacePhase.countdown ||
        _race.phase == LapRacePhase.racing) {
      _race.pause();
      return;
    }
    if (_race.phase == LapRacePhase.paused &&
        (_race.pausedFrom == LapRacePhase.racing ||
            _race.pausedFrom == LapRacePhase.countdown)) {
      _race.endEarly();
      return;
    }
    widget.onBack?.call();
  }

  void _leaveToLobby() {
    widget.session.setGameRunning(false);
    widget.onBack?.call();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _simulation.setRunning(false);
    widget.session.setGameRunning(false);
    _input.clear();
    _race.removeListener(_raceChanged);
    _race.dispose();
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
    if (_race.phase == LapRacePhase.finished) return _buildResults();
    final roomId = widget.session.roomId;
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
                      'LAP RACE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      roomId == null
                          ? 'PHÒNG ĐANG ĐÓNG'
                          : 'ROOM ${roomId.substring(0, 8)}',
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
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              GameWidget<ApexRacingGame>(
                                game: _game,
                                focusNode: _focusNode,
                                autofocus: true,
                                backgroundBuilder: (_) =>
                                    const ColoredBox(color: Color(0xFF193323)),
                              ),
                              if (_race.phase == LapRacePhase.countdown ||
                                  (_race.phase == LapRacePhase.racing &&
                                      _race.showGo) ||
                                  _race.phase == LapRacePhase.paused)
                                _raceOverlay(),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(width: 300, child: _rightPanel()),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'WASD · P1 xe đỏ      ↑ ↓ ← → · P2 xe xanh      ESC · pause/resume      R · restart khi pause',
                  style: TextStyle(color: Color(0xFF86918A), fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _raceOverlay() {
    if (_race.phase == LapRacePhase.countdown || _race.showGo) {
      final text = _race.showGo ? 'GO!' : '${_race.countdownNumber}';
      return ColoredBox(
        color: const Color(0xAA101713),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 88,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Colors.black45, blurRadius: 16)],
            ),
          ),
        ),
      );
    }

    final canEnd =
        _race.pausedFrom == LapRacePhase.racing ||
        _race.pausedFrom == LapRacePhase.countdown;
    return ColoredBox(
      color: const Color(0xB0101713),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2620),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF516157)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'TẠM DỪNG',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Thời gian đua: ${_formatDuration(_race.raceTime)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFB6C1B9)),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _resume,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Tiếp tục'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    _race.restartFromPause();
                    _snapshot.value = const RaceSnapshot();
                  },
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Restart từ vạch xuất phát'),
                ),
                if (canEnd) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _race.endEarly,
                    icon: const Icon(Icons.flag_rounded),
                    label: const Text('Kết thúc sớm và xem Results'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFFA69E),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _leaveToLobby,
                    icon: const Icon(Icons.meeting_room_outlined),
                    label: const Text('Về Lobby'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rightPanel() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in const ['p1', 'p2']) ...[
          _slotPanel(id),
          const SizedBox(height: 10),
        ],
        _raceClockPanel(),
        const SizedBox(height: 8),
        _progressPanel(PlayerId.red),
        const SizedBox(height: 8),
        _progressPanel(PlayerId.blue),
        const SizedBox(height: 10),
        if (_race.phase == LapRacePhase.ready ||
            _race.phase == LapRacePhase.paused) ...[
          _readinessPanel(),
          const SizedBox(height: 10),
        ],
        if (_race.finishTimeRemaining case final remaining?) ...[
          _finishDeadlinePanel(remaining),
          const SizedBox(height: 10),
        ],
        _speedCard(),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _race.phase == LapRacePhase.finished ? null : _toggle,
          icon: Icon(
            _race.phase == LapRacePhase.paused
                ? Icons.play_arrow
                : _race.phase == LapRacePhase.ready
                ? _race.canStartRace
                      ? Icons.flag_rounded
                      : Icons.tune_rounded
                : Icons.pause,
          ),
          label: Text(switch (_race.phase) {
            LapRacePhase.ready =>
              _race.canStartRace
                  ? 'Countdown & mulai'
                  : 'Pause để đổi nguồn / hiện QR',
            LapRacePhase.paused => 'Lanjutkan',
            LapRacePhase.countdown || LapRacePhase.racing => 'Tạm dừng',
            LapRacePhase.finished => 'Results',
          }),
        ),
        if (_qrSlot case final slotId?) ...[
          const SizedBox(height: 10),
          _qrPanel(slotId),
        ],
        if (_race.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _race.message!,
              style: const TextStyle(color: Color(0xFFF2C66D), fontSize: 11),
            ),
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
    ),
  );

  Widget _progressPanel(PlayerId player) {
    final progress = _race.progressFor(player);
    final red = player == PlayerId.red;
    final color = red ? const Color(0xFFFF696E) : const Color(0xFF68A4FF);
    final gate = progress.nextGateId;
    final checkpoint = gate == null
        ? progress.status == LapPlayerStatus.finished
              ? 'Đã về đích'
              : 'DNF'
        : gate == 'finish'
        ? 'Tiếp theo: vạch đích'
        : 'Tiếp theo: CP ${gate.substring(2, 3)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2620),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${red ? 'P1' : 'P2'} · Vòng ${progress.lapNumber}/${progress.lapCount}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                progress.status == LapPlayerStatus.finished
                    ? 'FINISH'
                    : progress.status == LapPlayerStatus.dnf
                    ? 'DNF'
                    : _formatDuration(progress.currentLapElapsed),
                style: const TextStyle(
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            checkpoint,
            style: const TextStyle(color: Color(0xFF9BA89E), fontSize: 11),
          ),
          if (progress.lapTimes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              progress.lapTimes
                  .asMap()
                  .entries
                  .map(
                    (entry) =>
                        'V${entry.key + 1} ${_formatDuration(entry.value)}',
                  )
                  .join('   '),
              style: const TextStyle(color: Color(0xFFB6C1B9), fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _raceClockPanel() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF26362C),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      children: [
        const Icon(Icons.timer_rounded, color: Color(0xFFC4D5C9), size: 18),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Thời gian đua',
            style: TextStyle(color: Color(0xFFC4D5C9), fontSize: 12),
          ),
        ),
        Text(
          _formatDuration(_race.raceTime),
          style: const TextStyle(
            color: Colors.white,
            fontFeatures: [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  Widget _finishDeadlinePanel(double remaining) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: const Color(0xFF382E1B),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      children: [
        const Icon(Icons.timer_outlined, color: Color(0xFFF2C66D), size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Người còn lại có ${_formatDuration(remaining)} để về đích.',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ],
    ),
  );

  Widget _buildResults() {
    final winner = _race.winner;
    final title = _race.isDraw
        ? 'HASIL SERI'
        : winner == PlayerId.red
        ? 'P1 MENANG'
        : winner == PlayerId.blue
        ? 'P2 MENANG'
        : 'TANPA PEMENANG';
    final reason = switch (_race.endReason) {
      LapRaceEndReason.completed => 'Kedua player menyelesaikan balapan.',
      LapRaceEndReason.deadline =>
        'Batas 60 detik setelah finish pertama habis.',
      LapRaceEndReason.hostEnded => 'Host mengakhiri balapan lebih awal.',
      LapRaceEndReason.roomClosed => 'Phòng hoặc relay đã kết thúc.',
      null => 'Cuộc đua đã kết thúc.',
    };
    return Scaffold(
      backgroundColor: const Color(0xFF111916),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: winner == PlayerId.red
                          ? const Color(0xFFFF696E)
                          : winner == PlayerId.blue
                          ? const Color(0xFF68A4FF)
                          : Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFB6C1B9)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ROOM ${widget.session.roomId?.substring(0, 8) ?? 'đã đóng'} · Thời gian mô phỏng ${_formatDuration(_race.raceTime)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF849087),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 24),
                  for (final player in PlayerId.values) ...[
                    _resultCard(player),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: widget.session.isConnected
                        ? () {
                            if (_race.rematch()) {
                              _snapshot.value = const RaceSnapshot();
                              _focusNode.requestFocus();
                            }
                          }
                        : null,
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Rematch · giữ nguyên room & controller'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _leaveToLobby,
                    icon: const Icon(Icons.meeting_room_outlined),
                    label: const Text('Về Lobby'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultCard(PlayerId player) {
    final progress = _race.progressFor(player);
    final red = player == PlayerId.red;
    final color = red ? const Color(0xFFFF696E) : const Color(0xFF68A4FF);
    final status = switch (progress.status) {
      LapPlayerStatus.finished =>
        'FINISH · ${_formatDuration(progress.finishTime!)}',
      LapPlayerStatus.dnf => 'DNF',
      LapPlayerStatus.racing => 'ĐANG ĐUA',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2620),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(backgroundColor: color, radius: 7),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${red ? 'P1 · Xe đỏ' : 'P2 · Xe xanh'}\n${progress.completedLaps}/${progress.lapCount} vòng',
                  style: const TextStyle(color: Colors.white, height: 1.5),
                ),
              ),
              Text(
                status,
                textAlign: TextAlign.end,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          if (progress.lapTimes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              progress.lapTimes
                  .asMap()
                  .entries
                  .map(
                    (entry) =>
                        'Vòng ${entry.key + 1}: ${_formatDuration(entry.value)}',
                  )
                  .join('  ·  '),
              style: const TextStyle(color: Color(0xFFB6C1B9), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(double seconds) {
    final milliseconds = (seconds * 1000).round().clamp(0, 359999999);
    final minutes = milliseconds ~/ 60000;
    final remainder = milliseconds % 60000;
    final wholeSeconds = remainder ~/ 1000;
    final millis = remainder % 1000;
    return '${minutes.toString().padLeft(2, '0')}:${wholeSeconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}';
  }

  Widget _readinessPanel() {
    MultiplayerSlotStatus? pending;
    for (final slot in widget.session.slots.values) {
      if (!widget.session.isSlotReadyToStart(slot.id)) {
        pending = slot;
        break;
      }
    }
    final ready = widget.session.canStart;
    final message = ready
        ? 'Hai player đã sẵn sàng. Có thể bắt đầu trận.'
        : pending != null
        ? _slotGuidance(pending)
        : 'Đang chờ relay gửi trạng thái hai player slot…';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ready ? const Color(0xFF173321) : const Color(0xFF382E1B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready ? Icons.check_circle_outline : Icons.info_outline,
            color: ready ? const Color(0xFF5BD184) : const Color(0xFFF2C66D),
            size: 18,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  String _slotGuidance(MultiplayerSlotStatus slot) {
    final player = slot.id.toUpperCase();
    if (!slot.connected) {
      return slot.reserved
          ? '$player tạm ngắt kết nối · có thể kết nối lại trong 30 giây.'
          : 'Quét QR $player bằng Android để kết nối điện thoại.';
    }
    return switch (slot.stage) {
      'checking' =>
        'Điện thoại $player đã kết nối. Giữ máy thẳng, nhấn Cân tâm trên điện thoại, rồi nhả GA/LÙI để bắt đầu.',
      'calibrating' =>
        'Điện thoại $player đang cân tâm. Giữ máy yên và chờ hoàn tất.',
      'lost' =>
        '$player chưa có trạng thái cảm biến sẵn sàng. Kiểm tra điện thoại và cân tâm lại nếu cần.',
      _ =>
        '$player đã cân tâm. Nhả GA/LÙI để gửi input trung tính trước khi xuất phát.',
    };
  }

  Widget _slotPanel(String slotId) {
    final slot = widget.session.slot(slotId);
    final red = slotId == 'p1';
    final source = slot?.source ?? (red ? 'phone' : 'keyboard');
    final connected = slot?.connected == true;
    final remote = widget.session.remoteFor(red ? PlayerId.red : PlayerId.blue);
    final label = source == 'keyboard'
        ? 'Keyboard · Web'
        : !connected
        ? slot?.reserved == true
              ? 'Disconnected · giữ slot 30 giây'
              : 'Disconnected'
        : switch (slot?.stage) {
            'checking' => 'Phone đã kết nối · cần cân tâm',
            'calibrating' => 'Phone đã kết nối · đang cân tâm',
            'lost' => 'Phone kết nối · cảm biến chưa sẵn sàng',
            'ready' when widget.session.isSlotReadyToStart(slotId) =>
              'Phone · sẵn sàng',
            'ready' when remote.hasFreshInput => 'Đã cân tâm · nhả GA/LÙI',
            'ready' => 'Đã cân tâm · chờ input trung tính',
            _ => 'Phone · đang kiểm tra',
          };
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
                _race.phase != LapRacePhase.paused ||
                    widget.session.isSlotConfiguring(slotId)
                ? null
                : (value) => _configure(slotId, value),
          ),
          if (source == 'phone' && !connected)
            TextButton.icon(
              onPressed: _race.phase != LapRacePhase.paused
                  ? null
                  : () => _showQr(slotId),
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
        child: Text('QR $slotId chưa sẵn sàng · Ẩn'),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Quét QR ${slotId.toUpperCase()} bằng Android',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Center(child: QrImageView(data: invite.toQrValue(), size: 190)),
          const Text('Mã có hiệu lực 5 phút', textAlign: TextAlign.center),
          TextButton(
            onPressed: () => setState(() => _qrSlot = null),
            child: const Text('Ẩn QR'),
          ),
        ],
      ),
    );
  }
}
