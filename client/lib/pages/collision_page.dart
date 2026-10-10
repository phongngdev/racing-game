import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'page_components.dart';

class CollisionPage extends StatefulWidget {
  const CollisionPage({super.key, required this.onRecovered});
  final VoidCallback onRecovered;

  @override
  State<CollisionPage> createState() => _CollisionPageState();
}

class _CollisionPageState extends State<CollisionPage> {
  int _selectedStep = 0;
  bool _incidentExpanded = false;

  @override
  Widget build(BuildContext context) {
    return DemoPage(
      step: '04',
      title: 'Cảnh báo va chạm',
      subtitle: 'Minh họa trạng thái cảnh báo và các bước khôi phục an toàn.',
      trailing: const StatusTag('CẢNH BÁO MÔ PHỎNG', color: Color(0xFFD4564B)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 760;
          final warning = _WarningCard(
            selectedStep: _selectedStep,
            onSelected: (value) => setState(() => _selectedStep = value),
            onRecovered: widget.onRecovered,
          );
          final info = _IncidentDetails(
            expanded: _incidentExpanded,
            onExpanded: (value) => setState(() => _incidentExpanded = value),
          );
          if (stack) {
            return Column(
              children: [warning, const SizedBox(height: 16), info],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: warning),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: info),
            ],
          );
        },
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({
    required this.selectedStep,
    required this.onSelected,
    required this.onRecovered,
  });
  final int selectedStep;
  final ValueChanged<int> onSelected;
  final VoidCallback onRecovered;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F3),
              border: Border.all(color: const Color(0xFFF7DFDB)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCE8E5),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: Color(0xFFD4564B),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Phát hiện va chạm',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF9F3E37),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Lực tác động ở góc trước bên trái · 12:48:36',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFFAB6A63),
                        ),
                      ),
                    ],
                  ),
                ),
                const StatusTag('MÔ PHỎNG', color: Color(0xFFD4564B)),
              ],
            ),
          ),
          const SizedBox(height: 19),
          const SectionTitle('Quy trình khôi phục'),
          const SizedBox(height: 5),
          const Text(
            'Chọn một bước để xem hướng dẫn phục hồi.',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 8),
          _RecoveryOption(
            selected: selectedStep == 0,
            number: '01',
            title: 'Giữ phanh',
            subtitle: 'Giữ xe đứng yên trong khi kiểm tra.',
            onTap: () => onSelected(0),
          ),
          _RecoveryOption(
            selected: selectedStep == 1,
            number: '02',
            title: 'Kiểm tra trạng thái',
            subtitle: 'Xem tín hiệu và các thông số cảm biến.',
            onTap: () => onSelected(1),
          ),
          _RecoveryOption(
            selected: selectedStep == 2,
            number: '03',
            title: 'Cân bằng lại vô lăng',
            subtitle: 'Đưa góc lái về vị trí trung tâm.',
            onTap: () => onSelected(2),
          ),
          const SizedBox(height: 10),
          PrimaryAction(
            label: 'Đưa xe về trạng thái an toàn',
            icon: Icons.center_focus_strong_rounded,
            onPressed: onRecovered,
            expand: true,
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'HAPTIC PHẢN HỒI · MÔ PHỎNG',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: .7,
                color: Color(0xFF98A0AD),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RecoveryOption extends StatelessWidget {
  const _RecoveryOption({
    required this.selected,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final bool selected;
  final String number;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 9),
    child: Material(
      color: selected ? const Color(0xFFF2F5FD) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              SizedBox(
                width: 27,
                height: 27,
                child: Center(
                  child: Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? demoBlue : const Color(0xFFB8C0CD),
                        width: selected ? 5 : 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
              ),
              Text(
                number,
                style: const TextStyle(fontSize: 9, color: Color(0xFF98A0AD)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _IncidentDetails extends StatelessWidget {
  const _IncidentDetails({required this.expanded, required this.onExpanded});
  final bool expanded;
  final ValueChanged<bool> onExpanded;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(19),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(
                'Mức độ tác động',
                trailing: StatusTag('NHẸ', color: Color(0xFFCC8B24)),
              ),
              const SizedBox(height: 19),
              const Row(
                children: [
                  Expanded(
                    child: ValueTile(
                      label: 'LỰC TÁC ĐỘNG',
                      value: '2.4',
                      unit: 'G',
                      color: Color(0xFFD4564B),
                    ),
                  ),
                  Expanded(
                    child: ValueTile(
                      label: 'VỊ TRÍ',
                      value: 'FL',
                      unit: 'trước trái',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 21),
              const Divider(color: line),
              const SizedBox(height: 15),
              const SectionTitle(
                'Xung rung phản hồi',
                trailing: Text(
                  '180 Hz',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 100,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF8F8),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: CustomPaint(
                  painter: _PulsePainter(),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 9),
              const DemoFootnote(
                text: 'Biểu đồ và tín hiệu rung được dựng sẵn.',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      Card(
        child: ExpansionTile(
          initiallyExpanded: expanded,
          onExpansionChanged: onExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: const Icon(
            Icons.receipt_long_outlined,
            size: 19,
            color: demoBlue,
          ),
          title: const Text(
            'Chi tiết sự cố',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          subtitle: const Text(
            'Thông tin cảm biến tại thời điểm va chạm',
            style: TextStyle(fontSize: 10, color: muted),
          ),
          children: const [
            _DetailRow(label: 'Gia tốc ngang', value: '2.4 G'),
            SizedBox(height: 10),
            _DetailRow(label: 'Nhiệt độ lốp trước trái', value: '88°C'),
            SizedBox(height: 10),
            _DetailRow(label: 'Tín hiệu tay cầm', value: 'Ổn định'),
            SizedBox(height: 10),
            _DetailRow(label: 'Thời điểm', value: '12:48:36'),
          ],
        ),
      ),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(fontSize: 10, color: muted)),
      ),
      Text(
        value,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
    ],
  );
}

class _PulsePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFEEE8E7)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path();
    for (var x = 0.0; x <= size.width; x += 2) {
      final normalized = x / size.width;
      final pulse = normalized > .38 && normalized < .53
          ? (1 - ((normalized - .455).abs() / .075)).clamp(0.0, 1.0)
          : 0.0;
      final wave = math.sin(normalized * 15 * 3.14159) * 0.13;
      final y = size.height * (.51 - wave - pulse * .34);
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFD4564B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
