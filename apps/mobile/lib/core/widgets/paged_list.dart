import 'package:flutter/material.dart';

import 'states.dart';

class PageResult<T> {
  const PageResult(this.items, this.nextCursor);

  final List<T> items;
  final String? nextCursor;
}

/// Loads a cursor-paginated list a page at a time and keeps the rows.
class PagedController<T> extends ChangeNotifier {
  PagedController(this._fetch) {
    load();
  }

  final Future<PageResult<T>> Function(String? cursor) _fetch;

  final List<T> items = [];
  Object? error;
  bool loading = false;
  String? _cursor;
  bool _done = false;
  bool _disposed = false;

  bool get hasMore => !_done;
  bool get initialLoading => loading && items.isEmpty;

  Future<void> load() async {
    if (loading || _done) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _fetch(_cursor);
      items.addAll(page.items);
      _cursor = page.nextCursor;
      _done = page.nextCursor == null;
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> refresh() async {
    items.clear();
    _cursor = null;
    _done = false;
    error = null;
    loading = false;
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A scrolling list that loads more rows as you reach the end, with pull-to-refresh.
class PagedList<T> extends StatefulWidget {
  const PagedList({
    required this.controller,
    required this.itemBuilder,
    required this.empty,
    this.header,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
    super.key,
  });

  final PagedController<T> controller;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget empty;
  final Widget? header;
  final EdgeInsetsGeometry padding;

  @override
  State<PagedList<T>> createState() => _PagedListState<T>();
}

class _PagedListState<T> extends State<PagedList<T>> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        if (c.initialLoading) return const LoadingState();
        if (c.error != null && c.items.isEmpty)
          return ErrorState(error: c.error!, onRetry: c.refresh);
        final header = widget.header;
        if (c.items.isEmpty && header == null) return widget.empty;
        return RefreshIndicator(
          onRefresh: c.refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) c.load();
              return false;
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: widget.padding,
              itemCount:
                  c.items.length +
                  (header == null ? 0 : 1) +
                  (c.items.isEmpty ? 1 : 0) +
                  (c.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (header != null) {
                  if (index == 0) return header;
                  index--;
                }
                if (c.items.isEmpty) return widget.empty;
                if (index >= c.items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: c.error != null
                          ? ErrorState(error: c.error!, onRetry: c.load)
                          : const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                    ),
                  );
                }
                return widget.itemBuilder(context, c.items[index], index);
              },
            ),
          ),
        );
      },
    );
  }
}
