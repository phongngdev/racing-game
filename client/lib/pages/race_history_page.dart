import 'package:flutter/material.dart';

import '../history/race_history.dart';
import '../history/race_history_repository.dart';

class RaceHistoryPage extends StatefulWidget {
  const RaceHistoryPage({super.key, required this.repository});

  final RaceHistoryRepository repository;

  @override
  State<RaceHistoryPage> createState() => _RaceHistoryPageState();
}

class _RaceHistoryPageState extends State<RaceHistoryPage> {
  final _items = <RaceHistory>[];
  String? _cursor;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    if (append && (_loadingMore || _cursor == null)) return;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final page = await widget.repository.list(
        cursor: append ? _cursor : null,
      );
      if (!mounted) return;
      setState(() {
        if (append) {
          _items.addAll(page.items);
        } else {
          _items
            ..clear()
            ..addAll(page.items);
        }
        _cursor = page.nextCursor;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'Chưa tải được lịch sử đấu. Hãy kiểm tra mạng rồi thử lại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lịch sử đấu')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: _body(),
      ),
    ),
  );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error case final error?) {
      return _MessageState(
        icon: Icons.cloud_off_rounded,
        title: error,
        action: FilledButton.icon(
          onPressed: () => _load(),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Thử lại'),
        ),
      );
    }
    if (_items.isEmpty) {
      return const _MessageState(
        icon: Icons.flag_outlined,
        title: 'Chưa có trận nào trong lịch sử.',
        message: 'Kết quả trận multiplayer đã lưu sẽ xuất hiện ở đây.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _items.length + (_cursor == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Center(
              child: TextButton.icon(
                onPressed: _loadingMore ? null : () => _load(append: true),
                icon: _loadingMore
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(_loadingMore ? 'Đang tải…' : 'Tải thêm'),
              ),
            );
          }
          final history = _items[index];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFEEF3FF),
                child: Icon(
                  history.isDraw
                      ? Icons.balance_rounded
                      : history.winnerSlot == null
                      ? Icons.flag_outlined
                      : Icons.emoji_events_rounded,
                  color: const Color(0xFF3267E3),
                ),
              ),
              title: Text(
                history.isDraw
                    ? 'Hòa · ${_modeLabel(history.mode)}'
                    : history.winnerSlot == null
                    ? 'Kết thúc · ${_modeLabel(history.mode)}'
                    : '${history.winnerSlot!.toUpperCase()} thắng · ${_modeLabel(history.mode)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  '${history.trackId} · ${_dateTime(history.endedAt)} · ${_duration(history.durationMs)}',
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/history/detail'),
                  builder: (_) => RaceHistoryDetailPage(
                    repository: widget.repository,
                    historyId: history.id,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class RaceHistoryDetailPage extends StatefulWidget {
  const RaceHistoryDetailPage({
    super.key,
    required this.repository,
    required this.historyId,
  });

  final RaceHistoryRepository repository;
  final String historyId;

  @override
  State<RaceHistoryDetailPage> createState() => _RaceHistoryDetailPageState();
}

class _RaceHistoryDetailPageState extends State<RaceHistoryDetailPage> {
  late Future<RaceHistory> _history;

  @override
  void initState() {
    super.initState();
    _history = widget.repository.findOne(widget.historyId);
  }

  void _retry() => setState(() {
    _history = widget.repository.findOne(widget.historyId);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chi tiết trận đấu')),
    body: FutureBuilder<RaceHistory>(
      future: _history,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _MessageState(
            icon: Icons.cloud_off_rounded,
            title: 'Chưa tải được chi tiết trận đấu.',
            action: FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
            ),
          );
        }
        return _detail(snapshot.data!);
      },
    ),
  );

  Widget _detail(RaceHistory history) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    history.isDraw
                        ? 'Trận đấu hòa'
                        : history.winnerSlot == null
                        ? 'Trận đấu kết thúc'
                        : '${history.winnerSlot!.toUpperCase()} chiến thắng',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  _DetailLine('Chế độ', _modeLabel(history.mode)),
                  _DetailLine('Đường đua', history.trackId),
                  _DetailLine('Phòng', history.roomId),
                  _DetailLine('Bắt đầu', _dateTime(history.startedAt)),
                  _DetailLine('Kết thúc', _dateTime(history.endedAt)),
                  _DetailLine('Thời gian đua', _duration(history.durationMs)),
                  _DetailLine(
                    'Kết thúc do',
                    history.endReason == 'deadline'
                        ? 'Hết thời gian chờ'
                        : 'Hoàn tất',
                  ),
                  if (history.trackSeed != null)
                    _DetailLine('Seed', history.trackSeed!),
                  if (history.generatorVersion != null)
                    _DetailLine(
                      'Phiên bản tạo track',
                      '${history.generatorVersion}',
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final player in history.players) ...[
            _PlayerResultCard(player: player, mode: history.mode),
            const SizedBox(height: 12),
          ],
        ],
      ),
    ),
  );
}

class _PlayerResultCard extends StatelessWidget {
  const _PlayerResultCard({required this.player, required this.mode});

  final RaceHistoryPlayer player;
  final HistoryRaceMode mode;

  @override
  Widget build(BuildContext context) {
    final color = player.vehicle == 'red'
        ? const Color(0xFFFF696E)
        : const Color(0xFF3267E3);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 6, backgroundColor: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${player.slot.toUpperCase()} · Xe ${player.vehicle == 'red' ? 'đỏ' : 'xanh'}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  player.status == HistoryPlayerStatus.finished
                      ? 'Về đích'
                      : 'DNF',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Điều khiển: ${player.source == 'phone' ? 'Điện thoại' : 'Bàn phím'}',
            ),
            if (player.finishTime != null)
              Text('Thời gian về đích: ${_seconds(player.finishTime!)}'),
            if (mode == HistoryRaceMode.lap) ...[
              Text('Số vòng: ${player.completedLaps}/${player.lapCount}'),
              if (player.lapTimes.isNotEmpty)
                Text(
                  'Thời gian từng vòng: ${player.lapTimes.map(_seconds).join(' · ')}',
                ),
            ] else
              Text(
                'Checkpoint: ${player.completedCheckpoints}/${player.totalCheckpoints}',
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 150, child: Text(label)),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: const Color(0xFF667085)),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}

String _modeLabel(HistoryRaceMode mode) => switch (mode) {
  HistoryRaceMode.lap => 'Lap Race',
  HistoryRaceMode.sprint => 'Sprint Race',
};

String _duration(int milliseconds) {
  final minutes = milliseconds ~/ 60000;
  final seconds = (milliseconds % 60000) ~/ 1000;
  final millis = milliseconds % 1000;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}';
}

String _seconds(double seconds) => _duration((seconds * 1000).round());

String _dateTime(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
