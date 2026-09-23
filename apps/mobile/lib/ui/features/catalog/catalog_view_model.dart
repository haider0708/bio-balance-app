import 'package:flutter/foundation.dart';

import '../../../domain/models/models.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class CatalogViewModel extends ChangeNotifier {
  final WorkspaceViewModel workspace;
  List<Json> products = [];
  String? error;
  bool loading = false, offline = false, closed = false;
  StoreData? _storeData;
  CatalogViewModel(this.workspace) {
    _storeData = workspace.state.data;
    products = _storeData?.list('products') ?? [];
    workspace.addListener(_changed);
  }
  void _changed() {
    if (closed || identical(_storeData, workspace.state.data)) return;
    _storeData = workspace.state.data;
    final indexed = {for (final p in products) p['id']: p};
    for (final p in _storeData?.list('products') ?? <Json>[]) {
      if (integer(p['version']) >= integer(indexed[p['id']]?['version'])) {
        indexed[p['id']] = p;
      }
    }
    products = List.unmodifiable(indexed.values);
    notifyListeners();
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      final cached = await workspace.repository.draft(
        workspace.user.id,
        '',
        'global-catalog',
      );
      if (closed) return;
      if (products.isEmpty) {
        products = objects(cached?['items']).isNotEmpty
            ? objects(cached?['items'])
            : workspace.state.data?.list('products') ?? [];
      }
      notifyListeners();
      final fresh = await workspace.catalog.list();
      workspace.repositoryContext.check();
      await workspace.repository.saveDraft(
        workspace.user.id,
        '',
        'global-catalog',
        {'items': fresh},
      );
      if (closed) return;
      products = fresh;
      error = null;
      offline = false;
    } catch (e) {
      if (!closed) {
        error = SessionViewModel.message(e);
        offline = true;
      }
    } finally {
      if (!closed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    closed = true;
    workspace.removeListener(_changed);
    super.dispose();
  }
}
