import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../controller/controller_config.dart';
import '../controller/pairing_payload.dart';
import '../racing/multiplayer_room_session.dart';
import '../racing/race_mode.dart';
import '../racing/race_mode_selector.dart';

class MultiplayerSetupPage extends StatefulWidget {
  const MultiplayerSetupPage({
    super.key,
    required this.onBack,
    required this.onStart,
    this.sessionFactory,
  });

  final VoidCallback onBack;
  final Future<void> Function(MultiplayerRoomSession session, RaceMode mode)
  onStart;
  final MultiplayerRoomSession Function(Uri relay)? sessionFactory;

  @override
  State<MultiplayerSetupPage> createState() => _MultiplayerSetupPageState();
}

class _MultiplayerSetupPageState extends State<MultiplayerSetupPage> {
  final _relayUrl = TextEditingController(text: ControllerConfig.webSocketUrl);
  MultiplayerRoomSession? _session;
  String? _error;
  String? _shownQrSlot;
  bool _starting = false;
  RaceMode _mode = RaceMode.lap;

  @override
  void dispose() {
    _session?.removeListener(_changed);
    final session = _session;
    if (session != null) {
      unawaited(session.close());
      session.dispose();
    }
    _relayUrl.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final shownSlot = _shownQrSlot;
    if (shownSlot != null && _session?.slot(shownSlot)?.connected == true) {
      _shownQrSlot = null;
    }
    setState(() {});
  }

  void _createRoom() {
    final relay = PairingPayload.parseRelayUrl(_relayUrl.text);
    if (relay == null) {
      setState(() {
        _error = ControllerConfig.allowUsbRelay
            ? 'Nhập địa chỉ ws://IP:3000/controller hoặc ws://127.0.0.1:3000/controller cho ADB reverse.'
            : 'Nhập địa chỉ WebSocket LAN dạng ws://192.168.1.20:3000/controller.';
      });
      return;
    }
    final previous = _session;
    previous?.removeListener(_changed);
    _session = null;
    if (previous != null) {
      unawaited(previous.close());
      previous.dispose();
    }
    final session =
        widget.sessionFactory?.call(relay) ??
        MultiplayerRoomSession(relayUrl: relay);
    session.addListener(_changed);
    setState(() {
      _session = session;
      _shownQrSlot = 'p1';
      _error = null;
    });
  }

  Future<void> _start() async {
    final session = _session;
    if (session == null || !session.canStart || _starting) return;
    setState(() => _starting = true);
    try {
      await widget.onStart(session, _mode);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _selectSource(String slotId, String? source) async {
    if (source == null) return;
    final session = _session;
    if (session == null || session.isGameRunning) return;
    final configured = await session.configureSlot(slotId, source);
    if (!mounted) return;
    setState(() {
      _error = configured
          ? null
          : session.error ?? 'Không đổi được nguồn điều khiển.';
      if (source == 'keyboard' && _shownQrSlot == slotId) _shownQrSlot = null;
    });
  }

  void _back() {
    final session = _session;
    if (session != null) unawaited(session.close());
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          tooltip: 'Quay lại',
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Multiplayer · Phòng chơi'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          return SingleChildScrollView(
            padding: EdgeInsets.all(compact ? 16 : 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Tạo phòng và kết nối tay cầm',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Web chạy simulation. Mặc định P1 dùng điện thoại, P2 dùng bàn phím.',
                    ),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _relayUrl,
                              decoration: const InputDecoration(
                                labelText: 'WebSocket relay',
                                hintText: 'ws://192.168.1.20:3000/controller',
                              ),
                              keyboardType: TextInputType.url,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed:
                                  session == null ||
                                      session.state ==
                                          MultiplayerRoomState.closed
                                  ? _createRoom
                                  : null,
                              icon: const Icon(Icons.add_link_rounded),
                              label: Text(
                                session == null ? 'Tạo phòng' : 'Tạo phòng mới',
                              ),
                            ),
                            if (_error != null || session?.error != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _error ?? session!.error!,
                                style: const TextStyle(
                                  color: Color(0xFFB42318),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (session != null) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                session.isConnected
                                    ? Icons.cloud_done_rounded
                                    : Icons.cloud_sync_rounded,
                                color: session.isConnected
                                    ? const Color(0xFF16803C)
                                    : const Color(0xFF667085),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  session.roomId == null
                                      ? 'Đang kết nối relay…'
                                      : 'Phòng ${session.roomId!.substring(0, 8)} · ${session.state.name}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          for (final slotId in const ['p1', 'p2'])
                            SizedBox(
                              width: compact ? double.infinity : 440,
                              child: _slotCard(session, slotId),
                            ),
                        ],
                      ),
                      if (_shownQrSlot case final slotId?)
                        _qrCard(session, slotId),
                      const SizedBox(height: 16),
                      RaceModeSelector(
                        mode: _mode,
                        onChanged: _starting
                            ? null
                            : (value) => setState(() => _mode = value),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: session.canStart && !_starting
                            ? _start
                            : null,
                        icon: const Icon(Icons.flag_rounded),
                        label: Text(
                          _starting ? 'Đang mở game…' : 'Vào đường đua',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: session.canStart
                              ? const Color(0xFFEAF7EE)
                              : const Color(0xFFFFF7E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              session.canStart
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.info_outline_rounded,
                              color: session.canStart
                                  ? const Color(0xFF16803C)
                                  : const Color(0xFF9A6700),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                _startGuidance(session),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _slotCard(MultiplayerRoomSession session, String slotId) {
    final slot = session.slot(slotId);
    final isRed = slotId == 'p1';
    final color = isRed ? const Color(0xFFE34B50) : const Color(0xFF4388F5);
    final source = slot?.source ?? (isRed ? 'phone' : 'keyboard');
    final status = _slotStatus(session, slotId, slot, source);
    final invite = session.inviteFor(slotId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(backgroundColor: color, radius: 8),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '$slotId · ${isRed ? 'Xe đỏ' : 'Xe xanh'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Flexible(
                  child: Text(
                    status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: session.isSlotReadyToStart(slotId)
                          ? const Color(0xFF16803C)
                          : slot?.connected == true
                          ? const Color(0xFF9A6700)
                          : const Color(0xFF667085),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Nguồn: '),
                DropdownButton<String>(
                  value: source,
                  items: const [
                    DropdownMenuItem(value: 'phone', child: Text('Phone')),
                    DropdownMenuItem(
                      value: 'keyboard',
                      child: Text('Keyboard'),
                    ),
                  ],
                  onChanged:
                      session.isConnected && !session.isSlotConfiguring(slotId)
                      ? (value) => unawaited(_selectSource(slotId, value))
                      : null,
                ),
              ],
            ),
            if (source == 'phone') ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      if (invite == null) session.resetSlot(slotId);
                      setState(() => _shownQrSlot = slotId);
                    },
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: Text(invite == null ? 'Tạo / hiện QR' : 'Hiện QR'),
                  ),
                  if (invite != null ||
                      slot?.connected == true ||
                      slot?.reserved == true)
                    TextButton(
                      onPressed: () {
                        if (session.resetSlot(slotId)) {
                          setState(() => _shownQrSlot = slotId);
                        }
                      },
                      child: const Text('Tạo QR mới'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _qrCard(MultiplayerRoomSession session, String slotId) {
    final invite = session.inviteFor(slotId);
    if (invite == null) {
      return Card(
        margin: const EdgeInsets.only(top: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'QR $slotId chưa sẵn sàng. Hãy tạo QR mới cho slot này.',
            ),
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Quét bằng Android · ${slotId.toUpperCase()}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Center(child: QrImageView(data: invite.toQrValue(), size: 250)),
            const SizedBox(height: 8),
            Text('QR hết hạn lúc ${invite.expiresAt.toLocal()}'),
            Text('Relay: ${invite.relayUrl}', textAlign: TextAlign.center),
            TextButton(
              onPressed: () => setState(() => _shownQrSlot = null),
              child: const Text('Ẩn QR'),
            ),
          ],
        ),
      ),
    );
  }

  String _slotStatus(
    MultiplayerRoomSession session,
    String slotId,
    MultiplayerSlotStatus? slot,
    String source,
  ) {
    if (slot == null) return 'Đang lấy trạng thái…';
    if (source == 'keyboard') return 'Keyboard · sẵn sàng trên Web';
    if (!slot.connected) {
      return slot.reserved
          ? 'Disconnected · giữ slot 30 giây'
          : 'Disconnected · chờ điện thoại';
    }
    return switch (slot.stage) {
      'checking' => 'Phone connected · cần cân tâm',
      'calibrating' => 'Phone connected · đang cân tâm',
      'lost' => 'Phone connected · cảm biến chưa sẵn sàng',
      'ready' when session.isSlotReadyToStart(slotId) => 'Phone · sẵn sàng',
      'ready' => 'Đã cân tâm · nhả GA/LÙI',
      _ => 'Phone connected · đang kiểm tra',
    };
  }

  String _startGuidance(MultiplayerRoomSession session) {
    if (!session.isConnected) return 'Đang kết nối với relay…';
    if (session.slots.length < 2) {
      return 'Đang nhận trạng thái hai player slot…';
    }
    for (final slot in session.slots.values) {
      if (session.isSlotReadyToStart(slot.id)) continue;
      final player = slot.id.toUpperCase();
      if (slot.source == 'keyboard') continue;
      if (!slot.connected) {
        return slot.reserved
            ? '$player vừa mất kết nối. Kết nối lại trong 30 giây hoặc tạo QR mới sau khi hết hạn.'
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
    return 'Hai player đã sẵn sàng. Có thể bắt đầu trận.';
  }
}
