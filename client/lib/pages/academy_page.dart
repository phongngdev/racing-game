import 'package:flutter/material.dart';

class AcademyPage extends StatelessWidget {
  const AcademyPage({super.key, required this.onBack, required this.onLesson});

  final VoidCallback onBack;
  final VoidCallback onLesson;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F8FA),
    appBar: AppBar(
      backgroundColor: Colors.white,
      leading: IconButton(
        tooltip: 'Quay lại',
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Sát hạch lái xe'),
    ),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return ListView(
          padding: EdgeInsets.all(compact ? 16 : 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Driving Academy',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text('Chọn một bài luyện để bắt đầu.'),
                    const SizedBox(height: 24),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onLesson,
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Row(
                            children: [
                              Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF1FF),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.alt_route_rounded,
                                  color: Color(0xFF3267E3),
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Đường vòng quanh co',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 18,
                                      ),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      'Bài chữ S · 2 phút · Tối đa 100 điểm',
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.play_circle_fill_rounded,
                                color: Color(0xFF3267E3),
                                size: 34,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_clock_rounded,
                              color: Color(0xFF818A98),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Các bài sát hạch khác · Sắp ra mắt',
                                style: TextStyle(color: Color(0xFF667085)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Driving Academy là bài luyện trong game, không cấp hoặc xác nhận kết quả sát hạch lái xe.',
                      style: TextStyle(color: Color(0xFF667085)),
                    ),
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
