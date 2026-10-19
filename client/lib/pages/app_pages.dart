import 'package:flutter/material.dart';

import '../auth/session_user.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onPlay});

  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) => _AppPage(
    child: Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.sports_motorsports_rounded,
                size: 36,
                color: Color(0xFF3267E3),
              ),
              const SizedBox(height: 20),
              Text(
                'Chào mừng đến với Apex RC',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Ứng dụng dành cho trải nghiệm điều khiển xe đua RC.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.sports_esports_rounded),
                label: const Text('Khám phá mục Chơi'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PlayPage extends StatelessWidget {
  const PlayPage({super.key, required this.onPractice});

  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) => _AppPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chọn chế độ chơi',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Chọn cách bạn muốn trải nghiệm Apex RC.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        _ModeCard(
          icon: Icons.sports_esports_rounded,
          title: 'Practice',
          description: 'Luyện tập lái xe và làm quen đường đua.',
          actionLabel: 'Chuẩn bị',
          onTap: onPractice,
        ),
        const SizedBox(height: 14),
        const _ModeCard(
          icon: Icons.people_alt_rounded,
          title: 'Multiplayer',
          description: 'Chế độ chơi cùng người khác đang được phát triển.',
          actionLabel: 'Sắp ra mắt',
          enabled: false,
        ),
      ],
    ),
  );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? const Color(0xFF172033)
        : const Color(0xFF98A0AE);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: foreground),
            ),
            const SizedBox(height: 5),
            Text(description, style: Theme.of(context).textTheme.bodyMedium),
          ],
        );
        final modeIcon = Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFFEEF3FF) : const Color(0xFFF2F3F5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: enabled ? const Color(0xFF3267E3) : const Color(0xFF98A0AE),
          ),
        );
        final action = enabled
            ? TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(actionLabel),
              )
            : Text(
                actionLabel,
                style: const TextStyle(
                  color: Color(0xFF98A0AE),
                  fontWeight: FontWeight.w600,
                ),
              );

        return Card(
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            modeIcon,
                            const SizedBox(width: 14),
                            Expanded(child: details),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerRight, child: action),
                      ],
                    )
                  : Row(
                      children: [
                        modeIcon,
                        const SizedBox(width: 16),
                        Expanded(child: details),
                        const SizedBox(width: 12),
                        action,
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.user,
    this.onOpenPhoneController,
  });

  final SessionUser user;
  final VoidCallback? onOpenPhoneController;

  @override
  Widget build(BuildContext context) => _AppPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tài khoản', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AccountDetail(label: 'Tên người dùng', value: user.username),
                const SizedBox(height: 16),
                _AccountDetail(label: 'Email', value: user.email),
                const SizedBox(height: 16),
                _AccountDetail(
                  label: 'Vai trò',
                  value: user.role == AppRole.admin ? 'Admin' : 'User',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (onOpenPhoneController != null) ...[
          Text('Tay cầm', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final details = const Row(
                  children: [
                    Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Color(0xFF3267E3),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('Quét QR để điều khiển Practice trên PC.'),
                    ),
                  ],
                );
                final action = FilledButton.tonal(
                  onPressed: onOpenPhoneController,
                  child: const Text('Mở tay cầm'),
                );
                return Padding(
                  padding: const EdgeInsets.all(18),
                  child: constraints.maxWidth < 440
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            details,
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: action,
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: details),
                            const SizedBox(width: 8),
                            action,
                          ],
                        ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
        Text('Về Apex RC', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Apex RC là ứng dụng dành cho trải nghiệm điều khiển xe đua RC.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    ),
  );
}

class _AccountDetail extends StatelessWidget {
  const _AccountDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: const Color(0xFF667085)),
      ),
      const SizedBox(height: 4),
      SelectableText(
        value,
        style: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(color: const Color(0xFF172033)),
      ),
    ],
  );
}

class _AppPage extends StatelessWidget {
  const _AppPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      return SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 16 : 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: child,
          ),
        ),
      );
    },
  );
}
