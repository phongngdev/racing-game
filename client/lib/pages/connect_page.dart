import 'package:flutter/material.dart';

import 'page_components.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.onConnected});
  final VoidCallback onConnected;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _pinController = TextEditingController();
  bool _connected = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _connect() {
    if (_pinController.text.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập đủ 6 chữ số PIN để tiếp tục nhé.')),
      );
      return;
    }
    setState(() => _connected = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã ghép nối thiết bị mô phỏng.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DemoPage(
      step: '01',
      title: 'Kết nối thiết bị',
      subtitle: 'Ghép nối bộ điều khiển để bắt đầu phiên đua.',
      trailing: const StatusTag(
        'BLUETOOTH · SẴN SÀNG',
        color: Color(0xFF31A879),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final pairingCard = _PairingCard(
            pinController: _pinController,
            onConnect: _connect,
            onScan: () => setState(() => _connected = true),
          );
          final deviceCard = _DeviceCard(
            connected: _connected,
            onTap: () => setState(() => _connected = !_connected),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact) ...[
                pairingCard,
                const SizedBox(height: 16),
                deviceCard,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: pairingCard),
                    const SizedBox(width: 18),
                    Expanded(flex: 5, child: deviceCard),
                  ],
                ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 18,
                        color: demoBlue,
                      ),
                      const SizedBox(width: 11),
                      const Expanded(
                        child: Text(
                          'Đây là màn mô phỏng. Nút quét QR và ghép nối dùng dữ liệu minh họa, không mở camera hay Bluetooth.',
                          style: TextStyle(
                            fontSize: 12,
                            color: muted,
                            height: 1.5,
                          ),
                        ),
                      ),
                      if (_connected) ...[
                        const SizedBox(width: 12),
                        PrimaryAction(
                          label: 'Tiếp tục',
                          onPressed: widget.onConnected,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PairingCard extends StatelessWidget {
  const _PairingCard({
    required this.pinController,
    required this.onConnect,
    required this.onScan,
  });
  final TextEditingController pinController;
  final VoidCallback onConnect;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Ghép nối nhanh'),
            const SizedBox(height: 4),
            const Text(
              'Quét mã trên thiết bị hoặc nhập PIN được cung cấp.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              height: 198,
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: line),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _DemoQrCode(),
                  const SizedBox(height: 8),
                  const Text(
                    'MÃ GHÉP NỐI MINH HỌA',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1,
                      color: Color(0xFF8A93A2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 17),
                label: const Text('Mô phỏng quét mã QR'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  side: const BorderSide(color: line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 17),
              child: Row(
                children: [
                  Expanded(child: Divider(color: line)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'HOẶC NHẬP PIN',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF98A0AD),
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: line)),
                ],
              ),
            ),
            TextField(
              controller: pinController,
              maxLength: 6,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                counterText: '',
                prefixIcon: Icon(Icons.password_rounded, size: 19),
                hintText: 'Nhập mã PIN 6 chữ số',
              ),
            ),
            const SizedBox(height: 11),
            PrimaryAction(
              label: 'Kết nối bằng PIN',
              icon: Icons.link_rounded,
              onPressed: onConnect,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.connected, required this.onTap});
  final bool connected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(
              'Thiết bị gần đây',
              trailing: const Text(
                '2 THIẾT BỊ',
                style: TextStyle(fontSize: 9, color: Color(0xFF98A0AD)),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Chọn bộ điều khiển để ghép nối.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 18),
            _DeviceRow(
              icon: Icons.sports_motorsports_rounded,
              name: 'Apex Hub Pro',
              serial: 'Mã thiết bị · #8821',
              signal: 'Tín hiệu tốt · 4 ms',
              tag: connected ? 'ĐÃ KẾT NỐI' : 'SẴN SÀNG',
              selected: connected,
              onTap: onTap,
            ),
            const SizedBox(height: 10),
            _DeviceRow(
              icon: Icons.memory_rounded,
              name: 'Telemetry OBD-Link',
              serial: 'Đồng bộ lần cuối · 2 giờ trước',
              signal: 'Có thể kết nối lại',
              tag: 'ĐÃ GHÉP ĐÔI',
              selected: false,
              onTap: onTap,
            ),
            const SizedBox(height: 21),
            const Divider(color: line),
            const SizedBox(height: 15),
            const SectionTitle('Trạng thái kết nối'),
            const SizedBox(height: 15),
            const _ConnectionFact(
              icon: Icons.bluetooth_rounded,
              label: 'Bluetooth',
              value: 'Sẵn sàng',
            ),
            const SizedBox(height: 12),
            const _ConnectionFact(
              icon: Icons.bolt_rounded,
              label: 'Độ trễ',
              value: '4 ms',
            ),
            const SizedBox(height: 12),
            const _ConnectionFact(
              icon: Icons.battery_5_bar_rounded,
              label: 'Pin thiết bị',
              value: '94%',
            ),
            const SizedBox(height: 19),
            const DemoFootnote(
              text: 'Thiết bị và thông số ở đây đều là dữ liệu giả.',
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.icon,
    required this.name,
    required this.serial,
    required this.signal,
    required this.tag,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String name;
  final String serial;
  final String signal;
  final String tag;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFF1F5FF) : pale,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: demoBlue),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      serial,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: muted),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      signal,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF31A879),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              StatusTag(
                tag,
                color: selected ? const Color(0xFF31A879) : demoBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionFact extends StatelessWidget {
  const _ConnectionFact({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: const Color(0xFF8A93A2)),
      const SizedBox(width: 9),
      Expanded(
        child: Text(label, style: const TextStyle(fontSize: 12, color: muted)),
      ),
      Text(
        value,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
    ],
  );
}

class _DemoQrCode extends StatelessWidget {
  const _DemoQrCode();

  final _pattern = const <int>[
    1,
    1,
    1,
    1,
    0,
    1,
    0,
    1,
    1,
    1,
    0,
    0,
    1,
    0,
    0,
    1,
    0,
    1,
    1,
    0,
    1,
    1,
    1,
    1,
    0,
    1,
    1,
    1,
    1,
    1,
    1,
    0,
    1,
    1,
    1,
    1,
    0,
    0,
    1,
    0,
    1,
    1,
    0,
    1,
    0,
    1,
    0,
    1,
    1,
    0,
    0,
    1,
    1,
    1,
    1,
    1,
    0,
    1,
    1,
    1,
    0,
    0,
    1,
    0,
    1,
    1,
    0,
    0,
    1,
    1,
    1,
    0,
    1,
    0,
    1,
    1,
    1,
    0,
    1,
    0,
    1,
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: 116,
    height: 116,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE8EBF0)),
    ),
    child: GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _pattern.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 9,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemBuilder: (context, index) => DecoratedBox(
        decoration: BoxDecoration(
          color: _pattern[index] == 1 ? const Color(0xFF243149) : Colors.white,
          borderRadius: BorderRadius.circular(1.5),
        ),
      ),
    ),
  );
}
