import 'package:flutter/material.dart';

/// One segment: a label, an icon and how many items it holds.
class Segment {
  final String label;
  final IconData icon;
  final int count;
  const Segment(this.label, this.icon, this.count);
}

/// Segments with their counts, wrapped over as many lines as needed so none is hidden.
class SegmentBar extends StatelessWidget {
  final Map<String, Segment> segments;
  final String selected;
  final ValueChanged<String> onChanged;
  final String keyPrefix;
  const SegmentBar({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.keyPrefix = 'segment',
  });
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final e in segments.entries)
        ChoiceChip(
          key: ValueKey('$keyPrefix.${e.key}'),
          avatar: Icon(e.value.icon, size: 18),
          label: Text('${e.value.label} · ${e.value.count}'),
          selected: selected == e.key,
          onSelected: (_) => onChanged(e.key),
        ),
    ],
  );
}
