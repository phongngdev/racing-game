import 'package:flutter/material.dart';

import 'page_components.dart';

class RacePage extends StatefulWidget {
  const RacePage({
    super.key,
    required this.onCollision,
    required this.onFinish,
    required this.onPlayWebRacing,
  });
  final VoidCallback onCollision;
  final VoidCallback onFinish;
  final VoidCallback onPlayWebRacing;

  @override
  State<RacePage> createState() => _RacePageState();
}

class _RacePageState extends State<RacePage> {
  bool _paused = false;
  bool _braking = false;
  double _throttle = 0.72;

  @override
  Widget build(BuildContext context) {
    return DemoPage(
      step: '03',
      title: 'Bảng điều khiển đường đua',
      subtitle: 'Phiên đua Suzuka GP · 12 vòng · Xe GT3 Proto-R',
      trailing: StatusTag(
        _paused ? 'ĐANG TẠM DỪNG' : 'ĐANG TRONG PHIÊN',
        color: _paused ? const Color(0xFFCC8B24) : const Color(0xFF31A879),
      ),
      child: Column(
        children: [
          _RaceSummary(
            paused: _paused,
            onPause: () => setState(() => _paused = !_paused),
            onFinish: widget.onFinish,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: widget.onPlayWebRacing,
              icon: const Icon(Icons.sports_motorsports_rounded, size: 18),
              label: const Text('Chơi thử Web Racing'),
              style: FilledButton.styleFrom(backgroundColor: demoBlue),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 760;
              final track = _TrackCard(paused: _paused, throttle: _throttle);
              final controls = _RaceControls(
                throttle: _throttle,
                braking: _braking,
                paused: _paused,
                onThrottleChanged: (v) => setState(() => _throttle = v),
                onBrake: () => setState(() => _braking = !_braking),
                onCollision: widget.onCollision,
              );
              if (stack) {
                return Column(
                  children: [track, const SizedBox(height: 16), controls],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: track),
                  const SizedBox(width: 16),
                  Expanded(flex: 4, child: controls),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          const _TireCard(),
          const SizedBox(height: 14),
          const DemoFootnote(
            text: 'Đây là bảng HUD minh họa, không có mô phỏng lái xe.',
          ),
        ],
      ),
    );
  }
}

class _RaceSummary extends StatelessWidget {
  const _RaceSummary({
    required this.paused,
    required this.onPause,
    required this.onFinish,
  });
  final bool paused;
  final VoidCallback onPause;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 17),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 550;
          final stats = Wrap(
            spacing: narrow ? 20 : 30,
            runSpacing: 13,
            children: const [
              ValueTile(
                label: 'TỐC ĐỘ',
                value: '184',
                unit: 'km/h',
                color: demoBlue,
              ),
              ValueTile(label: 'VÒNG ĐUA', value: '08', unit: '/ 12'),
              ValueTile(label: 'THỜI GIAN', value: '01:24', unit: '.892'),
              ValueTile(label: 'VỊ TRÍ', value: 'P2', unit: '/ 8'),
            ],
          );
          final buttons = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onPause,
                icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 17,
                ),
                label: Text(paused ? 'Tiếp tục' : 'Tạm dừng'),
              ),
              IconButton.filledTonal(
                onPressed: onFinish,
                tooltip: 'Kết thúc phiên đua giả lập',
                icon: const Icon(Icons.flag_outlined),
              ),
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [stats, const SizedBox(height: 16), buttons],
            );
          }
          return Row(
            children: [
              Expanded(child: stats),
              buttons,
            ],
          );
        },
      ),
    ),
  );
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({required this.paused, required this.throttle});
  final bool paused;
  final double throttle;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            'Sơ đồ vòng đua',
            trailing: StatusTag('SUZUKA GP'),
          ),
          const SizedBox(height: 7),
          const Text(
            'Lộ trình và vị trí xe được minh họa tĩnh.',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 11),
          AspectRatio(
            aspectRatio: 1.55,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: _TrackPainter())),
                  const Positioned(
                    left: 18,
                    top: 15,
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 7, color: Color(0xFF31A879)),
                        SizedBox(width: 6),
                        Text(
                          'SUZUKA · NHẬT BẢN',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: .7,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 14,
                    top: 14,
                    child: _MapBadge(
                      icon: Icons.directions_car_filled_rounded,
                      text: 'BẠN · P2',
                    ),
                  ),
                  if (paused)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(color: Color(0x18000000), blurRadius: 12),
                          ],
                        ),
                        child: const Text(
                          'ĐÃ TẠM DỪNG',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.bolt_rounded, size: 15, color: demoBlue),
              const SizedBox(width: 6),
              const Text(
                'Mức ga',
                style: TextStyle(fontSize: 10, color: muted),
              ),
              const Spacer(),
              Text(
                '${(throttle * 100).round()}%',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: throttle,
              minHeight: 7,
              color: demoBlue,
              backgroundColor: const Color(0xFFE9EDF5),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MapBadge extends StatelessWidget {
  const _MapBadge({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(icon, size: 12, color: demoBlue),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      ],
    ),
  );
}

class _RaceControls extends StatelessWidget {
  const _RaceControls({
    required this.throttle,
    required this.braking,
    required this.paused,
    required this.onThrottleChanged,
    required this.onBrake,
    required this.onCollision,
  });
  final double throttle;
  final bool braking;
  final bool paused;
  final ValueChanged<double> onThrottleChanged;
  final VoidCallback onBrake;
  final VoidCallback onCollision;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Điều khiển mô phỏng'),
          const SizedBox(height: 6),
          const Text(
            'Thử tương tác với HUD của xe.',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 22),
          Center(
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5FF),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFDCE6FF), width: 7),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    paused
                        ? '—'
                        : braking
                        ? '-4'
                        : '0',
                    style: const TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const Text('°', style: TextStyle(fontSize: 11, color: muted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'GÓC LÁI',
              style: TextStyle(fontSize: 9, letterSpacing: .8, color: muted),
            ),
          ),
          const SizedBox(height: 22),
          const Row(
            children: [
              Icon(Icons.flash_on_rounded, size: 15, color: demoBlue),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Bàn đạp ga',
                  style: TextStyle(fontSize: 11, color: ink),
                ),
              ),
              Text(
                'Kéo để thay đổi',
                style: TextStyle(fontSize: 9, color: muted),
              ),
            ],
          ),
          Slider(
            value: throttle,
            min: 0,
            max: 1,
            onChanged: paused ? null : onThrottleChanged,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: onBrake,
              icon: Icon(
                braking
                    ? Icons.stop_circle_outlined
                    : Icons.do_not_disturb_on_outlined,
                size: 18,
              ),
              label: Text(braking ? 'Nhả phanh' : 'Phanh'),
              style: FilledButton.styleFrom(
                backgroundColor: braking
                    ? const Color(0xFFFCEEEE)
                    : const Color(0xFFFFF4F1),
                foregroundColor: const Color(0xFFD4564B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 17),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCollision,
              icon: const Icon(Icons.warning_amber_rounded, size: 17),
              label: const Text('Mô phỏng va chạm'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD4564B),
                side: const BorderSide(color: Color(0xFFF2D6D3)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TireCard extends StatelessWidget {
  const _TireCard();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            'Tình trạng lốp',
            trailing: Text(
              'ĐƠN VỊ · BAR',
              style: TextStyle(fontSize: 9, color: muted),
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _TireChip(position: 'TRÁI TRƯỚC', pressure: '2.1'),
              _TireChip(position: 'PHẢI TRƯỚC', pressure: '2.0'),
              _TireChip(position: 'TRÁI SAU', pressure: '2.2'),
              _TireChip(position: 'PHẢI SAU', pressure: '2.1'),
            ],
          ),
        ],
      ),
    ),
  );
}

class _TireChip extends StatelessWidget {
  const _TireChip({required this.position, required this.pressure});
  final String position;
  final String pressure;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: pale,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.tire_repair_rounded,
          size: 16,
          color: Color(0xFF8A93A2),
        ),
        const SizedBox(width: 7),
        Text(position, style: const TextStyle(fontSize: 9, color: muted)),
        const SizedBox(width: 8),
        Text(
          pressure,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      ],
    ),
  );
}

class _TrackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerLine = Path()
      ..moveTo(size.width * .18, size.height * .60)
      ..cubicTo(
        size.width * .08,
        size.height * .55,
        size.width * .16,
        size.height * .31,
        size.width * .31,
        size.height * .33,
      )
      ..cubicTo(
        size.width * .42,
        size.height * .34,
        size.width * .35,
        size.height * .12,
        size.width * .54,
        size.height * .19,
      )
      ..cubicTo(
        size.width * .71,
        size.height * .25,
        size.width * .59,
        size.height * .47,
        size.width * .74,
        size.height * .49,
      )
      ..cubicTo(
        size.width * .90,
        size.height * .51,
        size.width * .84,
        size.height * .76,
        size.width * .69,
        size.height * .73,
      )
      ..cubicTo(
        size.width * .51,
        size.height * .70,
        size.width * .60,
        size.height * .56,
        size.width * .44,
        size.height * .58,
      )
      ..cubicTo(
        size.width * .33,
        size.height * .60,
        size.width * .34,
        size.height * .78,
        size.width * .21,
        size.height * .74,
      )
      ..cubicTo(
        size.width * .12,
        size.height * .71,
        size.width * .11,
        size.height * .62,
        size.width * .18,
        size.height * .60,
      );
    final casing = Paint()
      ..color = const Color(0xFFD5DCE8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final road = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final center = Paint()
      ..color = const Color(0xFFE7EBF2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(centerLine, casing);
    canvas.drawPath(centerLine, road);
    canvas.drawPath(centerLine, center);
    final marker = Paint()..color = demoBlue;
    canvas.drawCircle(Offset(size.width * .71, size.height * .73), 8, marker);
    canvas.drawCircle(
      Offset(size.width * .71, size.height * .73),
      3,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
