import 'dart:async';

import '../../domain/models/models.dart';
import '../features/workspace/workspace_view_model.dart';

/// Owns an editor draft independently of its route and the selected store.
class FormDraftController {
  final WorkspaceViewModel workspace;
  final Store? store;
  final String key;
  late final void Function() _unregister;
  Map<String, String> values;
  Future<void> _tail = Future.value();
  int revision = 0;
  bool completed = false;
  FormDraftController(this.workspace, this.store, this.key, this.values) {
    _unregister = workspace.registerDraft(flush);
  }
  Future<Map<String, String>?> restore() async {
    final draft = await workspace.repository.draft(
      workspace.user.id,
      store?.id ?? '',
      key,
    );
    if (revision != 0 || draft == null) return null;
    final restored = draft['values'] is Map ? draft['values'] as Map : draft;
    values = {
      for (final e in restored.entries)
        if (e.value is String) '${e.key}': e.value as String,
    };
    return values;
  }

  Future<void> change(Map<String, String> next) {
    revision++;
    values = Map.unmodifiable(next);
    return flush();
  }

  Future<void> flush() {
    if (completed) return Future.value();
    final captured = Map<String, String>.from(values);
    final next = _tail
        .catchError((Object _) {})
        .then(
          (_) => workspace.repository.saveDraft(
            workspace.user.id,
            store?.id ?? '',
            key,
            {'values': captured},
          ),
        );
    _tail = next;
    return next;
  }

  Future<void> complete() async {
    await _tail.catchError((Object _) {});
    await workspace.repository.saveDraft(
      workspace.user.id,
      store?.id ?? '',
      key,
      {},
    );
    completed = true;
  }

  void dispose() {
    _unregister();
  }
}
