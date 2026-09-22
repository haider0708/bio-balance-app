import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/inventory_rules.dart';
import '../../../domain/models/tunis_dates.dart';
import '../workspace/workspace_view_model.dart';

class StockRow {
  final Product product;
  final StockSummary summary;
  const StockRow(this.product, this.summary);
}

List<StockRow> _rows(StoreData data, String day) => List.unmodifiable([
  for (final product in data.products)
    StockRow(product, StockSummary.forProduct(data, product.id, today: day)),
]);

List<StockRow> _prepareRows((Json, String) input) =>
    _rows(StoreData(input.$1), input.$2);

/// Reuses summaries across searches/status changes. Large inventories are
/// indexed outside the UI isolate, with at most one worker and latest-state wins.
class StockViewModel extends ChangeNotifier {
  final WorkspaceViewModel workspace;
  StockViewModel(this.workspace) {
    workspace.addListener(refresh);
    refresh();
  }
  StoreData? _data;
  String? _day;
  List<StockRow> _all = const [], rows = const [];
  String query = '', filter = 'all';
  String? error;
  bool loading = false, _building = false, _closed = false;
  int _revision = 0;
  Future<void> _prepared = Future.value();
  Future<void> get prepared => _prepared;

  void refresh() {
    if (_closed) return;
    final data = workspace.state.data, day = TunisDates.today();
    if (identical(data, _data) && day == _day) return;
    _data = data;
    _day = day;
    _revision++;
    error = null;
    // Both dimensions matter: a small catalog can have thousands of lots.
    final small =
        ((data?.raw['products'] as List?)?.length ?? 0) <= 400 &&
        ((data?.raw['lots'] as List?)?.length ?? 0) <= 1200;
    if (small && !_building) {
      _all = data == null ? const [] : _rows(data, day);
      loading = false;
      _filter();
      return;
    }
    loading = true;
    _all = rows = const []; // Do not show a previous store during preparation.
    if (!_building) _prepared = _prepareLatest();
    notifyListeners();
  }

  Future<void> _prepareLatest() async {
    _building = true;
    try {
      while (!_closed) {
        final data = _data, revision = _revision, day = _day!;
        try {
          final result = data == null
              ? <StockRow>[]
              : await compute(_prepareRows, (
                  {
                    'products': data.raw['products'],
                    'lots': data.raw['lots'],
                    'config': data.raw['config'],
                  },
                  day,
                ), debugLabel: 'stock-index');
          if (_closed) return;
          if (revision != _revision) continue;
          _all = List.unmodifiable(result);
          loading = false;
          _filter();
          return;
        } catch (_) {
          if (_closed) return;
          if (revision != _revision) continue;
          loading = false;
          error = 'Le stock n’a pas pu être affiché. Rouvrez cet écran pour réessayer.';
          notifyListeners();
          return;
        }
      }
    } finally {
      _building = false;
    }
  }

  void search(String value) {
    final normalized = value.trim().toLowerCase();
    if (query == normalized) return;
    query = normalized;
    _filter();
  }

  void selectFilter(String value) {
    if (filter == value) return;
    filter = value;
    _filter();
  }

  void _filter() {
    rows = List.unmodifiable(
      _all.where(
        (row) => row.product.matches(query) && row.summary.matches(filter),
      ),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    workspace.removeListener(refresh);
    super.dispose();
  }
}
