import 'package:flutter/material.dart';

import 'race_mode.dart';

class RaceModeSelector extends StatelessWidget {
  const RaceModeSelector({
    super.key,
    required this.mode,
    required this.onChanged,
  });
  final RaceMode mode;
  final ValueChanged<RaceMode>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<RaceMode>(
        segments: const [
          ButtonSegment(
            value: RaceMode.lap,
            label: Text('Lap Race'),
            icon: Icon(Icons.loop_rounded),
          ),
          ButtonSegment(
            value: RaceMode.sprint,
            label: Text('Sprint Race'),
            icon: Icon(Icons.route_rounded),
          ),
        ],
        selected: {mode},
        onSelectionChanged: onChanged == null
            ? null
            : (value) => onChanged!(value.single),
      ),
      const SizedBox(height: 8),
      Text(
        mode == RaceMode.lap
            ? 'Lap Race · 3 vòng'
            : 'Sprint Race · Start → Finish · hai khung nhìn riêng',
        textAlign: TextAlign.center,
      ),
    ],
  );
}
