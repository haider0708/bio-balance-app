import 'package:flutter/material.dart';

/// A single horizontal row, independent of the surrounding page's scroll.
class FilterBar<T extends Object> extends StatefulWidget {
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final Key Function(T)? itemKey;
  const FilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.itemKey,
  });

  @override
  State<FilterBar<T>> createState() => _FilterBarState<T>();
}

class _FilterBarState<T extends Object> extends State<FilterBar<T>> {
  final scroll = ScrollController();
  final anchors = <T, GlobalKey>{};
  @override
  void initState() {
    super.initState();
    reveal();
  }

  @override
  void didUpdateWidget(covariant FilterBar<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) reveal();
  }

  void reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !scroll.hasClients) return;
    final target = anchors[widget.selected]?.currentContext?.findRenderObject();
    if (target != null) scroll.position.ensureVisible(target, alignment: .5);
  });
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: scroll,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: scroll,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          for (final option in widget.options.entries)
            Padding(
              key: anchors.putIfAbsent(option.key, GlobalKey.new),
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: widget.itemKey?.call(option.key),
                label: Text(option.value),
                selected: widget.selected == option.key,
                onSelected: (_) => widget.onChanged(option.key),
              ),
            ),
        ],
      ),
    ),
  );
}
