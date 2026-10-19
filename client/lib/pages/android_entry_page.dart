import 'package:flutter/material.dart';

class AndroidEntryPage extends StatelessWidget {
  const AndroidEntryPage({
    super.key,
    required this.onOpenApp,
    required this.onScanQr,
  });

  final VoidCallback onOpenApp;
  final VoidCallback onScanQr;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F8FA),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.sports_motorsports_rounded,
                  color: Color(0xFF3267E3),
                  size: 52,
                ),
                const SizedBox(height: 14),
                Text(
                  'Apex RC',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Mở ứng dụng hoặc kết nối điện thoại làm tay cầm Practice.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                _EntryCard(
                  icon: Icons.home_rounded,
                  title: 'Mở ứng dụng',
                  description:
                      'Đăng nhập để mở Trang chủ, Chơi, Cài đặt và Catalog.',
                  buttonLabel: 'Mở Apex RC',
                  onPressed: onOpenApp,
                ),
                const SizedBox(height: 14),
                _EntryCard(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Tay cầm Practice',
                  description: 'Quét mã trên PC để lái xe đỏ. Không cần đăng nhập tài khoản.',
                  buttonLabel: 'Quét QR',
                  onPressed: onScanQr,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF3267E3), size: 26),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(buttonLabel),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3267E3),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );
}
