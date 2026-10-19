import 'package:flutter/material.dart';

class PracticeSetupPage extends StatelessWidget {
  const PracticeSetupPage({
    super.key,
    required this.onBack,
    required this.onStart,
  });

  final VoidCallback onBack;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F8FA),
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      leading: IconButton(
        tooltip: 'Quay lại',
        onPressed: onBack,
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
                    'Practice hiện hỗ trợ điều khiển bằng bàn phím. Cuộc đua chỉ bắt đầu sau khi bạn nhấn nút trong game.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 22),
                  _SetupCard(
                    icon: Icons.keyboard_rounded,
                    title: 'Bàn phím · WASD',
                    accent: true,
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
                  const _SetupCard(
                    icon: Icons.phone_iphone_rounded,
                    title: 'Điện thoại',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            'Kết nối bằng QR sẽ được hỗ trợ sau. Practice hiện chưa cần NestJS relay.',
                            style: TextStyle(
                              color: Color(0xFF667085),
                              height: 1.5,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Sắp hỗ trợ',
                          style: TextStyle(
                            color: Color(0xFF98A0AE),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFF3267E3),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Hãy dùng bàn phím vật lý để lái. Trên điện thoại, điều khiển cảm ứng chưa được hỗ trợ.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.sports_esports_rounded),
                    label: const Text('Bắt đầu Practice'),
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
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.icon,
    required this.title,
    required this.child,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final bool accent;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: accent
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
              if (accent) ...[
                const SizedBox(width: 10),
                const _AvailableBadge(),
              ],
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

class _AvailableBadge extends StatelessWidget {
  const _AvailableBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFEEF3FF),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'Đang dùng',
      style: TextStyle(
        color: Color(0xFF3267E3),
        fontSize: 11,
        fontWeight: FontWeight.w700,
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
