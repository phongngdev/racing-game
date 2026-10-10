import 'package:flutter/material.dart';

import 'page_components.dart';

class ResultPage extends StatefulWidget {
  const ResultPage({super.key, required this.onRematch});
  final VoidCallback onRematch;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  bool _voted = false;

  @override
  Widget build(BuildContext context) {
    return DemoPage(
      step: '05',
      title: 'Kết quả phiên đua',
      subtitle: 'Suzuka GP · Phiên đua đã kết thúc · 8 tay đua',
      trailing: const StatusTag('ĐÃ HOÀN THÀNH', color: Color(0xFF31A879)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 780;
          final summary = Column(
            children: [
              const _WinnerCard(),
              const SizedBox(height: 15),
              _StatsCard(
                voted: _voted,
                onVote: () => setState(() => _voted = true),
              ),
            ],
          );
          final standings = const _StandingsCard();
          return Column(
            children: [
              if (stack)
                Column(
                  children: [summary, const SizedBox(height: 16), standings],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: summary),
                    const SizedBox(width: 16),
                    const Expanded(flex: 6, child: _StandingsCard()),
                  ],
                ),
              const SizedBox(height: 17),
              Row(
                children: [
                  const Expanded(
                    child: DemoFootnote(
                      text: 'Bảng xếp hạng và chỉ số sau trận là dữ liệu minh họa.',
                    ),
                  ),
                  PrimaryAction(
                    label: 'Chơi lại',
                    icon: Icons.replay_rounded,
                    onPressed: widget.onRematch,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WinnerCard extends StatelessWidget {
  const _WinnerCard();

  @override
  Widget build(BuildContext context) => Card(
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFFFBFCFF), Color(0xFFF0F4FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1D6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFFD99B2B),
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NGƯỜI DẪN ĐẦU',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                        color: muted,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'APX_VALKYRIE',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
              const StatusTag('P1 · BẠN', color: Color(0xFFD99B2B)),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(color: Color(0xFFE1E7F4)),
          const SizedBox(height: 13),
          const Row(
            children: [
              Expanded(
                child: ValueTile(
                  label: 'TỔNG THỜI GIAN',
                  value: '21:48',
                  unit: '.320',
                ),
              ),
              Expanded(
                child: ValueTile(label: 'ĐIỂM THƯỞNG', value: '+26', unit: 'đ'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.directions_car_filled_rounded,
                size: 15,
                color: demoBlue,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'GT3 Proto-R · Apex Racing',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ),
              const Text(
                'Về nhất vòng 8',
                style: TextStyle(fontSize: 9, color: Color(0xFF31A879)),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.voted, required this.onVote});
  final bool voted;
  final VoidCallback onVote;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Thống kê sau trận'),
          const SizedBox(height: 17),
          const Row(
            children: [
              Expanded(
                child: ValueTile(
                  label: 'VÒNG NHANH NHẤT',
                  value: '1:23.410',
                  color: demoBlue,
                ),
              ),
              Expanded(
                child: ValueTile(
                  label: 'TỐC ĐỘ TỐI ĐA',
                  value: '288',
                  unit: 'km/h',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: ValueTile(
                  label: 'ĐỘ ỔN ĐỊNH',
                  value: '99.4',
                  unit: '%',
                  color: Color(0xFF31A879),
                ),
              ),
              Expanded(
                child: ValueTile(label: 'SỐ VÒNG', value: '12', unit: 'vòng'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: line),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Bình chọn tái đấu',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
              Text(
                voted ? '7 / 8' : '6 / 8',
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: voted ? 7 / 8 : 6 / 8,
              minHeight: 6,
              color: demoBlue,
              backgroundColor: const Color(0xFFEBEEF4),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: voted ? null : onVote,
              icon: Icon(
                voted ? Icons.check_rounded : Icons.how_to_vote_outlined,
                size: 17,
              ),
              label: Text(voted ? 'Đã bình chọn tái đấu' : 'Bình chọn tái đấu'),
              style: OutlinedButton.styleFrom(
                foregroundColor: demoBlue,
                side: const BorderSide(color: Color(0xFFD9E3FA)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Racer {
  const _Racer(this.name, this.team, this.bestLap, this.gap, this.position);
  final String name;
  final String team;
  final String bestLap;
  final String gap;
  final int position;
}

class _StandingsCard extends StatelessWidget {
  const _StandingsCard();

  static const _racers = <_Racer>[
    _Racer('APX_VALKYRIE', 'Apex Works Racing', '1:23.410', 'Dẫn đầu', 1),
    _Racer('K. SATO', 'Phantom SimSport', '1:23.550', '+2.140s', 2),
    _Racer('M. VANDER', 'Apex Nordic Group', '1:24.100', '+5.680s', 3),
    _Racer('NEXUS_R', 'Cyber Motorsport', '1:24.410', '+8.200s', 4),
    _Racer('D. ROCHA', 'Redline Sim', '1:24.890', '+11.450s', 5),
    _Racer('J. MILLER', 'Apex Privateer', '1:25.101', '+13.210s', 6),
    _Racer('T. CHEN', 'F1 Sector 3', '1:25.640', '+18.500s', 7),
    _Racer('L. MARTIN', 'Blue Apex Team', '1:26.020', '+21.330s', 8),
  ];

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'Bảng xếp hạng',
            trailing: const Text(
              '8 TAY ĐUA',
              style: TextStyle(fontSize: 9, color: muted),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Suzuka GP · Kết quả sau 12 vòng',
            style: TextStyle(fontSize: 10, color: muted),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 27,
                  child: Text(
                    'HẠNG',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'TAY ĐUA',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    'VÒNG NHANH',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 59,
                  child: Text(
                    'KHOẢNG CÁCH',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          const Divider(color: line, height: 1),
          const SizedBox(height: 3),
          for (final racer in _racers) _RacerRow(racer: racer),
        ],
      ),
    ),
  );
}

class _RacerRow extends StatelessWidget {
  const _RacerRow({required this.racer});
  final _Racer racer;

  @override
  Widget build(BuildContext context) {
    final winner = racer.position == 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: winner ? const Color(0xFFF2F6FF) : Colors.transparent,
        border: const Border(bottom: BorderSide(color: Color(0xFFF0F2F5))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 27,
            child: Text(
              '${racer.position}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: winner ? demoBlue : muted,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  racer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: winner ? demoBlue : ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  racer.team,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8, color: muted),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              racer.bestLap,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 8, color: ink),
            ),
          ),
          SizedBox(
            width: 59,
            child: Text(
              racer.gap,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 8,
                fontWeight: winner ? FontWeight.w700 : FontWeight.w500,
                color: winner ? const Color(0xFF31A879) : muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
