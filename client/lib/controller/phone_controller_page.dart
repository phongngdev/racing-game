import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'controller_config.dart';
import 'phone_controller.dart';

class PhoneControllerPage extends StatefulWidget {
  const PhoneControllerPage({super.key});

  @override
  State<PhoneControllerPage> createState() => _PhoneControllerPageState();
}

class _PhoneControllerPageState extends State<PhoneControllerPage> {
  final _controller = PhoneController();
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ControllerConfig.webSocketUrl);
    _controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF111916),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 450;
          return SingleChildScrollView(
            child: SizedBox(
              height: math.max(320, constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.all(compact ? 8 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.sports_motorsports_rounded,
                          color: Color(0xFFB9F34A),
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'APEX RC CONTROLLER',
                            style: TextStyle(
                              color: Color(0xFFF1F4EF),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        _StatusDot(connected: _controller.isConnected),
                        const SizedBox(width: 8),
                        Text(
                          _controller.isConnected
                              ? 'ĐÃ KẾT NỐI'
                              : 'CHƯA KẾT NỐI',
                          style: const TextStyle(
                            color: Color(0xFFABB6AC),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 6 : 13),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.url,
                            style: const TextStyle(color: Color(0xFFE4EAE5)),
                            decoration: InputDecoration(
                              isDense: compact,
                              contentPadding: compact
                                  ? const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    )
                                  : null,
                              labelText: 'WebSocket URL của PC',
                              hintText: 'ws://192.168.1.20:3000/controller',
                              labelStyle: const TextStyle(
                                color: Color(0xFF9BA89E),
                              ),
                              hintStyle: const TextStyle(
                                color: Color(0xFF647168),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF1B2620),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _controller.isAttempting
                              ? _controller.disconnect
                              : () {
                                  FocusScope.of(context).unfocus();
                                  _controller.connect(_urlController.text);
                                },
                          style: FilledButton.styleFrom(
                            foregroundColor: const Color(0xFF17200E),
                            backgroundColor: const Color(0xFFB9F34A),
                            minimumSize: Size(112, compact ? 42 : 52),
                          ),
                          child: Text(
                            _controller.isAttempting
                                ? 'Ngắt kết nối'
                                : 'Kết nối',
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 6 : 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _controller.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFABB6AC),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _controller.isConnected
                              ? _controller.calibrate
                              : null,
                          icon: const Icon(Icons.center_focus_strong_rounded),
                          label: Text(
                            _controller.isCalibrated
                                ? 'Cân tâm lại'
                                : 'Cân tâm',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE4EAE5),
                            disabledForegroundColor: const Color(0xFF849087),
                            side: const BorderSide(color: Color(0xFF39473E)),
                            minimumSize: Size(130, compact ? 36 : 48),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 6 : 12),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: _SteeringPanel(
                              value: _controller.steering,
                              active: _controller.isReady,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 4,
                            child: Column(
                              children: [
                                Expanded(
                                  child: _HoldButton(
                                    label: 'GA',
                                    icon: Icons.arrow_upward_rounded,
                                    color: const Color(0xFFB9F34A),
                                    active: _controller.isReady,
                                    pressed: _controller.throttlePressed,
                                    onPressed: _controller.setThrottle,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: _HoldButton(
                                    label: 'PHANH',
                                    icon: Icons.vertical_align_bottom_rounded,
                                    color: const Color(0xFFFF696E),
                                    active: _controller.isReady,
                                    pressed: _controller.brakePressed,
                                    onPressed: _controller.setBrake,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Giữ điện thoại ngang · giữ nút để ga/phanh · thả tay để nhả',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF68756B), fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _SteeringPanel extends StatelessWidget {
  const _SteeringPanel({required this.value, required this.active});

  final double value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final marker = ((value.clamp(-1.0, 1.0) + 1) / 2).toDouble();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B2620),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2B3830)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            active ? 'NGHIÊNG ĐỂ LÁI' : 'CÂN TÂM ĐỂ BẮT ĐẦU',
            style: const TextStyle(
              color: Color(0xFF9BA89E),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                alignment: Alignment.center,
                children: [
                  Container(height: 3, color: const Color(0xFF39473E)),
                  Align(
                    alignment: const Alignment(0, 0),
                    child: Container(
                      width: 2,
                      height: math.min(30, constraints.maxHeight),
                      color: const Color(0xFF68756B),
                    ),
                  ),
                  Positioned(
                    left: (constraints.maxWidth - 18) * marker,
                    child: Container(
                      width: 18,
                      height: math.min(38, constraints.maxHeight),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFB9F34A)
                            : const Color(0xFF68756B),
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'TRÁI',
                style: TextStyle(color: Color(0xFF849087), fontSize: 9),
              ),
              Text(
                'THẲNG',
                style: TextStyle(color: Color(0xFF849087), fontSize: 9),
              ),
              Text(
                'PHẢI',
                style: TextStyle(color: Color(0xFF849087), fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.active,
    required this.pressed,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final bool pressed;
  final ValueChanged<bool> onPressed;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  final Set<int> _pointers = {};

  void _updatePointer(int pointer, bool down) {
    if (!widget.active) return;
    if (down) {
      _pointers.add(pointer);
    } else {
      _pointers.remove(pointer);
    }
    widget.onPressed(_pointers.isNotEmpty);
  }

  @override
  void didUpdateWidget(covariant _HoldButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && _pointers.isNotEmpty) {
      _pointers.clear();
      widget.onPressed(false);
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) => _updatePointer(event.pointer, true),
    onPointerUp: (event) => _updatePointer(event.pointer, false),
    onPointerCancel: (event) => _updatePointer(event.pointer, false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      decoration: BoxDecoration(
        color: widget.pressed
            ? widget.color.withValues(alpha: 0.23)
            : const Color(0xFF1B2620),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.active ? widget.color : const Color(0xFF39473E),
          width: widget.pressed ? 3 : 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final color = widget.active ? widget.color : const Color(0xFF68756B);
          if (constraints.maxHeight < 100) {
            return Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, color: color, size: 26),
                      const SizedBox(width: 10),
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  color: widget.active ? widget.color : const Color(0xFF68756B),
                  size: 28,
                ),
                const SizedBox(height: 5),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.active
                        ? widget.color
                        : const Color(0xFF68756B),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'GIỮ ĐỂ KÍCH HOẠT',
                  style: TextStyle(color: Color(0xFF849087), fontSize: 8),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: connected ? const Color(0xFFB9F34A) : const Color(0xFF68756B),
    ),
  );
}
