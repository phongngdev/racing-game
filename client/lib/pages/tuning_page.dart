import 'package:flutter/material.dart';

import 'page_components.dart';

class TuningPage extends StatefulWidget {
  const TuningPage({super.key, required this.onStartRace});
  final VoidCallback onStartRace;

  @override
  State<TuningPage> createState() => _TuningPageState();
}

class _TuningPageState extends State<TuningPage> {
  static const _cars = <_CarSpec>[
    _CarSpec('GT3 PROTO-R', 'Apex Racing', 'AWD', '720', '1.180', 'Cân bằng'),
    _CarSpec('NOVA GT-R', 'Nordic Works', 'RWD', '640', '1.240', 'Tốc độ'),
    _CarSpec('VORTEX S', 'Apex Racing', 'AWD', '810', '1.090', 'Bám đường'),
    _CarSpec('VECTOR 07', 'Vector Lab', 'RWD', '580', '1.160', 'Linh hoạt'),
    _CarSpec('ORBIT RS', 'Orbit Garage', 'AWD', '760', '1.210', 'Ổn định'),
  ];

  int _carIndex = 0;
  int _steering = 540;
  double _gyro = 78;
  double _haptic = 65;
  bool _autoCenter = true;

  void _selectCar(int offset) {
    setState(
      () => _carIndex = (_carIndex + offset + _cars.length) % _cars.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final car = _cars[_carIndex];
    return DemoPage(
      step: '02',
      title: 'Tinh chỉnh bộ điều khiển',
      subtitle: 'Chọn xe và điều chỉnh cảm giác lái theo ý bạn.',
      trailing: const StatusTag('CẤU HÌNH ĐÃ LƯU'),
      child: Column(
        children: [
          _CarCard(
            car: car,
            index: _carIndex,
            total: _cars.length,
            onPrevious: () => _selectCar(-1),
            onNext: () => _selectCar(1),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 760;
              final controls = _ControllerCard(
                gyro: _gyro,
                haptic: _haptic,
                steering: _steering,
                autoCenter: _autoCenter,
                onGyroChanged: (v) => setState(() => _gyro = v),
                onHapticChanged: (v) => setState(() => _haptic = v),
                onSteeringChanged: (v) => setState(() => _steering = v),
                onAutoCenterChanged: (v) => setState(() => _autoCenter = v),
              );
              final telemetry = const _TelemetryCard();
              if (stack) {
                return Column(
                  children: [controls, const SizedBox(height: 16), telemetry],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: controls),
                  const SizedBox(width: 16),
                  Expanded(flex: 4, child: telemetry),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: DemoFootnote(
                  text: 'Thiết lập được lưu trong phiên trình duyệt này.',
                ),
              ),
              PrimaryAction(
                label: 'Sẵn sàng đua',
                icon: Icons.flag_rounded,
                onPressed: widget.onStartRace,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CarSpec {
  const _CarSpec(
    this.name,
    this.team,
    this.drive,
    this.power,
    this.weight,
    this.style,
  );
  final String name;
  final String team;
  final String drive;
  final String power;
  final String weight;
  final String style;
}

class _CarCard extends StatelessWidget {
  const _CarCard({
    required this.car,
    required this.index,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });
  final _CarSpec car;
  final int index;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(19),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 540;
          final carVisual = Container(
            height: compact ? 120 : 144,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _GarageLinesPainter()),
                ),
                Center(
                  child: Icon(
                    Icons.directions_car_filled_rounded,
                    size: compact ? 82 : 102,
                    color: demoBlue.withAlpha(210),
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 13,
                  child: StatusTag(car.style.toUpperCase()),
                ),
              ],
            ),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: SectionTitle('Xe đang chọn')),
                  IconButton(
                    onPressed: onPrevious,
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: 'Xe trước',
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    '${index + 1} / $total',
                    style: const TextStyle(fontSize: 10, color: muted),
                  ),
                  IconButton(
                    onPressed: onNext,
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: 'Xe tiếp theo',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                car.name,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontSize: 21),
              ),
              const SizedBox(height: 3),
              Text(
                '${car.team} · Xe đua hạng GT',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 0,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: compact ? 100 : 116,
                    child: ValueTile(label: 'DẪN ĐỘNG', value: car.drive),
                  ),
                  SizedBox(
                    width: compact ? 100 : 116,
                    child: ValueTile(
                      label: 'CÔNG SUẤT',
                      value: car.power,
                      unit: 'HP',
                      color: demoBlue,
                    ),
                  ),
                  SizedBox(
                    width: compact ? 100 : 116,
                    child: ValueTile(
                      label: 'KHỐI LƯỢNG',
                      value: car.weight,
                      unit: 'kg',
                    ),
                  ),
                ],
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [carVisual, const SizedBox(height: 14), details],
            );
          }
          return Row(
            children: [
              Expanded(flex: 5, child: carVisual),
              const SizedBox(width: 21),
              Expanded(flex: 6, child: details),
            ],
          );
        },
      ),
    ),
  );
}

class _ControllerCard extends StatelessWidget {
  const _ControllerCard({
    required this.gyro,
    required this.haptic,
    required this.steering,
    required this.autoCenter,
    required this.onGyroChanged,
    required this.onHapticChanged,
    required this.onSteeringChanged,
    required this.onAutoCenterChanged,
  });
  final double gyro;
  final double haptic;
  final int steering;
  final bool autoCenter;
  final ValueChanged<double> onGyroChanged;
  final ValueChanged<double> onHapticChanged;
  final ValueChanged<int> onSteeringChanged;
  final ValueChanged<bool> onAutoCenterChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Điều khiển & cảm biến'),
          const SizedBox(height: 18),
          _AdjustmentSlider(
            title: 'Độ nhạy con quay hồi chuyển',
            value: gyro,
            onChanged: onGyroChanged,
            icon: Icons.screen_rotation_alt_rounded,
          ),
          const SizedBox(height: 14),
          _AdjustmentSlider(
            title: 'Cường độ rung phản hồi',
            value: haptic,
            onChanged: onHapticChanged,
            icon: Icons.vibration_rounded,
          ),
          const SizedBox(height: 20),
          const Text(
            'GIỚI HẠN GÓC LÁI',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: muted,
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 900, label: Text('900°')),
              ButtonSegment(value: 540, label: Text('540°')),
              ButtonSegment(value: 360, label: Text('360°')),
            ],
            selected: {steering},
            showSelectedIcon: false,
            onSelectionChanged: (value) => onSteeringChanged(value.first),
            style: ButtonStyle(
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : muted,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.selected) ? demoBlue : pale,
              ),
              side: const WidgetStatePropertyAll(BorderSide(color: line)),
            ),
          ),
          const SizedBox(height: 13),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: autoCenter,
            onChanged: onAutoCenterChanged,
            activeThumbColor: demoBlue,
            title: const Text(
              'Tự cân bằng vô lăng',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            subtitle: const Text(
              'Đưa vô lăng về vị trí giữa sau mỗi khúc cua',
              style: TextStyle(fontSize: 10, color: muted),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AdjustmentSlider extends StatelessWidget {
  const _AdjustmentSlider({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.icon,
  });
  final String title;
  final double value;
  final ValueChanged<double> onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF8A93A2)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 11, color: ink),
            ),
          ),
          Text(
            '${value.round()}%',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: demoBlue,
            ),
          ),
        ],
      ),
      Slider(value: value, min: 0, max: 100, onChanged: onChanged),
    ],
  );
}

class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Tín hiệu thiết bị'),
          const SizedBox(height: 17),
          const Row(
            children: [
              Expanded(
                child: ValueTile(
                  label: 'TÍN HIỆU',
                  value: '-38',
                  unit: 'dBm',
                  color: Color(0xFF31A879),
                ),
              ),
              Expanded(
                child: ValueTile(
                  label: 'TẦN SỐ',
                  value: '1000',
                  unit: 'Hz',
                  color: demoBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: line),
          const SizedBox(height: 14),
          const Row(
            children: [
              Icon(
                Icons.battery_5_bar_rounded,
                size: 17,
                color: Color(0xFF31A879),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pin tay cầm',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
              Text(
                '94%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: const LinearProgressIndicator(
              value: 0.94,
              minHeight: 6,
              color: Color(0xFF31A879),
              backgroundColor: Color(0xFFEAF3EF),
            ),
          ),
          const SizedBox(height: 17),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: pale,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 17,
                  color: Color(0xFF31A879),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Kết nối ổn định',
                    style: TextStyle(fontSize: 11, color: ink),
                  ),
                ),
                Text('4 ms', style: TextStyle(fontSize: 10, color: muted)),
              ],
            ),
          ),
          const SizedBox(height: 13),
          const DemoFootnote(
            text: 'Dữ liệu cảm biến được dựng sẵn cho bản demo.',
          ),
        ],
      ),
    ),
  );
}

class _GarageLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE8EBF0)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height * .76),
      Offset(size.width, size.height * .76),
      paint,
    );
    for (var i = 1; i < 5; i++) {
      final x = size.width * i / 5;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint..color = const Color(0xFFF0F2F5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
