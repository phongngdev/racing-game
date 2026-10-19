import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../controller/controller_config.dart';
import '../controller/pairing_payload.dart';
import '../racing/practice_controller_session.dart';

class PracticeSetupPage extends StatefulWidget {
  const PracticeSetupPage({
    super.key,
    required this.onBack,
    required this.onStart,
  });

  final VoidCallback onBack;
  final Future<void> Function(PracticeControllerSession? session) onStart;

  @override
  State<PracticeSetupPage> createState() => _PracticeSetupPageState();
}

class _PracticeSetupPageState extends State<PracticeSetupPage> {
  final _relayUrlController = TextEditingController(
    text: ControllerConfig.webSocketUrl,
  );
  PracticeControllerSession? _session;
  bool _phoneSelected = false;
  String? _relayError;
  bool _starting = false;

  @override
  void dispose() {
    _session?.removeListener(_handleSessionChange);
    _session?.dispose();
    _relayUrlController.dispose();
    super.dispose();
  }

  void _handleSessionChange() {
    if (mounted) setState(() {});
  }

  void _selectKeyboard() {
    final session = _session;
    _session = null;
    session?.removeListener(_handleSessionChange);
    if (session != null) unawaited(session.end());
    setState(() {
      _phoneSelected = false;
      _relayError = null;
    });
  }

  void _selectPhone() {
    setState(() {
      _phoneSelected = true;
      _relayError = null;
    });
    if (_session == null) _createPairingSession();
  }

  Future<void> _createPairingSession() async {
    if (!_phoneSelected) return;
    final uri = PairingPayload.parseRelayUrl(_relayUrlController.text);
    if (uri == null) {
      setState(() {
        _relayError = 'Nhập địa chỉ WebSocket LAN có dạng ws://192.168.1.20:3000/controller. Không dùng localhost.';
      });
      return;
    }
    final previous = _session;
    previous?.removeListener(_handleSessionChange);
    _session = null;
    await previous?.end();
    if (!mounted) return;
    final session = PracticeControllerSession(relayUrl: uri);
    session.addListener(_handleSessionChange);
    setState(() {
      _session = session;
      _relayError = null;
    });
  }

  Future<void> _startPractice() async {
    if (_starting) return;
    final session = _phoneSelected ? _session : null;
    if (_phoneSelected && (session == null || !session.canStart)) return;
    setState(() => _starting = true);
    try {
      await widget.onStart(session);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F8FA),
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      leading: IconButton(
        tooltip: 'Quay lại',
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Chuẩn bị Practice'),
    ),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 16 : 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Sẵn sàng ra đường đua',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Chọn cách điều khiển. Cuộc đua chỉ bắt đầu sau khi bạn nhấn nút trong game.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 22),
                  _SetupCard(
                    icon: Icons.keyboard_rounded,
                    title: 'Bàn phím · WASD',
                    selected: !_phoneSelected,
                    onTap: _selectKeyboard,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ControlLine(keys: 'W', description: 'Ga xe đỏ'),
                        _ControlLine(keys: 'S', description: 'Lùi xe đỏ'),
                        _ControlLine(
                          keys: 'A / D',
                          description: 'Rẽ trái / phải xe đỏ',
                        ),
                        Divider(height: 22),
                        _ControlLine(
                          keys: '← ↑ ↓ →',
                          description: 'Điều khiển xe xanh để kiểm thử va chạm',
                        ),
                        SizedBox(height: 12),
                        Text(
                          'ESC · tạm dừng     R · đặt lại xe',
                          style: TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SetupCard(
                    icon: Icons.phone_iphone_rounded,
                    title: 'Điện thoại',
                    selected: _phoneSelected,
                    onTap: _selectPhone,
                    child: _phoneSetupContent(context),
                  ),
                  const SizedBox(height: 14),
                  if (!_phoneSelected)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: Color(0xFF3267E3),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Bàn phím hoạt động độc lập với NestJS relay.',
                                style: TextStyle(color: Color(0xFF667085)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed:
                        _starting ||
                            (_phoneSelected && !(_session?.canStart ?? false))
                        ? null
                        : _startPractice,
                    icon: const Icon(Icons.sports_esports_rounded),
                    label: Text(
                      _starting ? 'Đang mở game…' : 'Bắt đầu Practice',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3267E3),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _phoneSetupContent(BuildContext context) => !_phoneSelected
      ? const Text(
          'Chọn Điện thoại để tạo phiên ghép nối qua QR.',
          style: TextStyle(color: Color(0xFF667085), height: 1.5),
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Quét mã bằng ứng dụng Apex RC trên Android. PC và điện thoại cần ở cùng mạng LAN.',
              style: TextStyle(color: Color(0xFF667085), height: 1.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _relayUrlController,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'WebSocket URL của relay',
                hintText: 'ws://192.168.1.20:3000/controller',
                helperText:
                    'Dùng IP LAN của máy chạy NestJS, không dùng localhost.',
              ),
            ),
            if (_relayError != null) ...[
              const SizedBox(height: 8),
              Text(
                _relayError!,
                style: const TextStyle(color: Color(0xFFB42318), height: 1.4),
              ),
            ],
            const SizedBox(height: 12),
            if (_session == null ||
                _session!.state == PracticeControllerState.expired ||
                _session!.state == PracticeControllerState.ended ||
                _session!.state == PracticeControllerState.relayLost ||
                _session!.state == PracticeControllerState.error)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: _createPairingSession,
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: Text(_session == null ? 'Tạo mã QR' : 'Tạo mã QR mới'),
                ),
              ),
            if (_session case final session?) ...[
              const SizedBox(height: 14),
              AnimatedBuilder(
                animation: session,
                builder: (context, _) => _PairingStatusCard(session: session),
              ),
            ],
          ],
        );
}

class _PairingStatusCard extends StatelessWidget {
  const _PairingStatusCard({required this.session});

  final PracticeControllerSession session;

  @override
  Widget build(BuildContext context) {
    final pairing = session.pairing;
    final state = session.state;
    final (label, color, icon) = switch (state) {
      PracticeControllerState.connectingRelay => (
        'Đang kết nối relay…',
        const Color(0xFF667085),
        Icons.sync_rounded,
      ),
      PracticeControllerState.waitingForPhone => (
        'Chờ điện thoại quét mã',
        const Color(0xFF3267E3),
        Icons.qr_code_scanner_rounded,
      ),
      PracticeControllerState.checking => (
        'Đã kết nối · nhấn Cân tâm trên điện thoại trước khi chơi',
        const Color(0xFFB54708),
        Icons.sensors_rounded,
      ),
      PracticeControllerState.calibrating => (
        'Đã kết nối · điện thoại đang cân tâm',
        const Color(0xFFB54708),
        Icons.center_focus_strong_rounded,
      ),
      PracticeControllerState.neutralRequired => (
        'Thả GA/LÙI để tay cầm sẵn sàng',
        const Color(0xFFB54708),
        Icons.pan_tool_alt_rounded,
      ),
      PracticeControllerState.ready => (
        'Tay cầm sẵn sàng',
        const Color(0xFF067647),
        Icons.check_circle_rounded,
      ),
      PracticeControllerState.lost => (
        session.isPhoneConnected
            ? 'Điện thoại vẫn kết nối · cảm biến chưa sẵn sàng. Kiểm tra cảm biến và cân tâm lại.'
            : 'Điện thoại đã ngắt kết nối · kiểm tra Wi-Fi hoặc mở lại ứng dụng.',
        session.isPhoneConnected
            ? const Color(0xFFB54708)
            : const Color(0xFFB42318),
        session.isPhoneConnected
            ? Icons.sensors_off_rounded
            : Icons.wifi_off_rounded,
      ),
      PracticeControllerState.relayLost => (
        'Relay trên PC bị ngắt · hãy tạo mã mới',
        const Color(0xFFB42318),
        Icons.cloud_off_rounded,
      ),
      PracticeControllerState.expired => (
        'Mã ghép nối đã hết hạn',
        const Color(0xFFB42318),
        Icons.timer_off_rounded,
      ),
      PracticeControllerState.ended => (
        'Phiên ghép nối đã kết thúc',
        const Color(0xFF667085),
        Icons.link_off_rounded,
      ),
      PracticeControllerState.error => (
        'Không tạo được phiên ghép nối',
        const Color(0xFFB42318),
        Icons.error_outline_rounded,
      ),
    };
    final showQr =
        pairing != null &&
        !pairing.isExpired &&
        !session.isPhoneConnected &&
        state == PracticeControllerState.waitingForPhone;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            if (showQr)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8EBF0)),
                ),
                child: QrImageView(
                  data: pairing.toQrValue(),
                  version: QrVersions.auto,
                  size: 220,
                  gapless: true,
                  semanticsLabel: 'Mã ghép nối Practice Apex RC',
                ),
              ),
            if (showQr) const SizedBox(height: 14),
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                ),
                if (session.isPhoneConnected)
                  TextButton.icon(
                    onPressed: session.end,
                    icon: const Icon(Icons.link_off_rounded, size: 17),
                    label: const Text('Ngắt'),
                  ),
              ],
            ),
            if (session.error != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  session.error!,
                  style: const TextStyle(color: Color(0xFFB42318)),
                ),
              ),
            ],
            if (pairing != null && showQr) ...[
              const SizedBox(height: 6),
              Text(
                'Mã dùng một lần · hết hạn lúc ${TimeOfDay.fromDateTime(pairing.expiresAt).format(context)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.icon,
    required this.title,
    required this.child,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: selected ? const Color(0xFF3267E3) : const Color(0xFFE8EBF0),
        width: selected ? 1.5 : 1,
      ),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: selected
                      ? const Color(0xFF3267E3)
                      : const Color(0xFF667085),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: Color(0xFF3267E3)),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    ),
  );
}

class _ControlLine extends StatelessWidget {
  const _ControlLine({required this.keys, required this.description});

  final String keys;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            keys,
            style: const TextStyle(
              color: Color(0xFF3267E3),
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Expanded(
          child: Text(
            description,
            style: const TextStyle(color: Color(0xFF667085)),
          ),
        ),
      ],
    ),
  );
}
