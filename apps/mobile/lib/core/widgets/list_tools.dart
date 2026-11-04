import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import 'states.dart';

const _accents = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ÿ': 'y',
  'œ': 'oe',
  'æ': 'ae',
  '’': "'",
};

/// Lower case, accents removed: "Sérum" and "serum" are the same word when searching.
String foldText(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_accents[char] ?? char);
  }
  return out.toString();
}

/// Whether every word of [query] is found in one of [fields] (accents and case ignored).
/// An empty query matches everything.
bool matchesSearch(String query, Iterable<String?> fields) {
  final words = foldText(query)
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final haystack = fields.whereType<String>().map(foldText).join(' ');
  return words.every(haystack.contains);
}

/// The search box above a list: a magnifier, a clear button once something is typed, and the keyboard's
/// "search" key. [onChanged] gets what was typed, trimmed; filter with [matchesSearch].
class SearchBox extends StatefulWidget {
  const SearchBox({
    required this.hint,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: widget.padding,
    child: TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(LucideIcons.search, size: 20),
        suffixIcon: ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: AppLocalizations.of(context).clearSearch,
                  icon: const Icon(LucideIcons.x, size: 18),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                ),
        ),
      ),
      onChanged: (v) => widget.onChanged(v.trim()),
    ),
  );
}

/// One row of choice chips that scrolls sideways; [value] is the chosen one (null: the "all" chip).
class FilterChips<T> extends StatelessWidget {
  const FilterChips({
    required this.options,
    required this.value,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// Each option is its value and its label; the first is usually "All" with a null value.
  final List<(T?, String)> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: padding,
    child: Row(
      children: [
        for (final (option, label) in options)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilterChip(
              label: Text(label),
              selected: value == option,
              showCheckmark: false,
              onSelected: (_) => onChanged(option),
            ),
          ),
      ],
    ),
  );
}

/// The sort button of an app bar: a menu of ways to order the list, the current one ticked.
class SortMenu<T> extends StatelessWidget {
  const SortMenu({
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: AppLocalizations.of(context).sortBy,
    icon: const Icon(LucideIcons.arrowDownUp),
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final (option, label) in options)
        CheckedPopupMenuItem(
          value: option,
          checked: value == option,
          child: Text(label),
        ),
    ],
  );
}

/// What sits above a list: the search box with the sort button beside it, and a row of filter chips under it.
class ListToolbar extends StatelessWidget {
  const ListToolbar({
    required this.hint,
    required this.onSearch,
    this.sort,
    this.chips,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 4),
    super.key,
  });

  final String hint;
  final ValueChanged<String> onSearch;

  /// A [SortMenu], shown beside the box.
  final Widget? sort;

  /// A [FilterChips] row (or several, in a column).
  final Widget? chips;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SearchBox(hint: hint, onChanged: onSearch),
            ),
            if (sort != null) ...[const SizedBox(width: 4), sort!],
          ],
        ),
        if (chips != null) ...[const SizedBox(height: 8), chips!],
      ],
    ),
  );
}

/// A filter chip of a [SearchableList]: its label and which items it keeps.
class ListFilter<T> {
  const ListFilter(this.label, this.keeps);

  final String label;
  final bool Function(T item) keeps;
}

/// A way to order a [SearchableList].
class ListSort<T> {
  const ListSort(this.label, this.compare);

  final String label;
  final int Function(T a, T b) compare;
}

/// A list with a search box, filter chips and a sort menu above it: the same everywhere in the app.
/// [fields] gives the texts a search looks in; the first [filters] entry and the first [sorts] entry are the
/// starting ones (usually "All" and the natural order).
class SearchableList<T> extends StatefulWidget {
  const SearchableList({
    required this.items,
    required this.fields,
    required this.itemBuilder,
    required this.hint,
    required this.emptyTitle,
    this.filters = const [],
    this.sorts = const [],
    this.onRefresh,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 96),
    this.spacing = 8,
    this.header,
    super.key,
  });

  final List<T> items;
  final List<String?> Function(T item) fields;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String hint;

  /// Shown when the search or a filter leaves nothing.
  final String emptyTitle;
  final List<ListFilter<T>> filters;
  final List<ListSort<T>> sorts;
  final Future<void> Function()? onRefresh;
  final EdgeInsetsGeometry padding;
  final double spacing;

  /// Something shown above the items, under the toolbar (a summary, a banner).
  final Widget? header;

  @override
  State<SearchableList<T>> createState() => _SearchableListState<T>();
}

class _SearchableListState<T> extends State<SearchableList<T>> {
  String _query = '';
  int _filter = 0;
  int _sort = 0;

  @override
  Widget build(BuildContext context) {
    final shown = widget.items
        .where(
          (i) =>
              (widget.filters.isEmpty || widget.filters[_filter].keeps(i)) &&
              matchesSearch(_query, widget.fields(i)),
        )
        .toList();
    if (widget.sorts.isNotEmpty) shown.sort(widget.sorts[_sort].compare);
    final list = shown.isEmpty
        ? ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              EmptyState(icon: LucideIcons.search, title: widget.emptyTitle),
            ],
          )
        : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: widget.padding,
            itemCount: shown.length,
            separatorBuilder: (_, _) => SizedBox(height: widget.spacing),
            itemBuilder: (context, i) => widget.itemBuilder(context, shown[i]),
          );
    return Column(
      children: [
        ListToolbar(
          hint: widget.hint,
          onSearch: (v) => setState(() => _query = v),
          sort: widget.sorts.length > 1
              ? SortMenu<int>(
                  value: _sort,
                  onChanged: (v) => setState(() => _sort = v),
                  options: [
                    for (var i = 0; i < widget.sorts.length; i++)
                      (i, widget.sorts[i].label),
                  ],
                )
              : null,
          chips: widget.filters.length > 1
              ? FilterChips<int>(
                  value: _filter,
                  onChanged: (v) => setState(() => _filter = v ?? 0),
                  options: [
                    for (var i = 0; i < widget.filters.length; i++)
                      (i, widget.filters[i].label),
                  ],
                )
              : null,
        ),
        if (widget.header != null) widget.header!,
        Expanded(
          child: widget.onRefresh == null
              ? list
              : RefreshIndicator(onRefresh: widget.onRefresh!, child: list),
        ),
      ],
    );
  }
}

/// How a list of documents (transfers, returns, orders…) can be ordered.
enum DocSort {
  newest,
  oldest,
  piecesMost,
  piecesLeast;

  /// The menu entries, with their words.
  static List<(DocSort, String)> options(AppLocalizations t) => [
    (newest, t.sortNewest),
    (oldest, t.sortOldest),
    (piecesMost, t.sortPiecesMost),
    (piecesLeast, t.sortPiecesLeast),
  ];

  /// Orders two documents by their date and their number of pieces.
  int compare(DateTime aDate, int aUnits, DateTime bDate, int bUnits) =>
      switch (this) {
        newest => bDate.compareTo(aDate),
        oldest => aDate.compareTo(bDate),
        piecesMost => bUnits.compareTo(aUnits),
        piecesLeast => aUnits.compareTo(bUnits),
      };
}
