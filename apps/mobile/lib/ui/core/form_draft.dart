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
  bool completed = false, submitting = false;
  FormDraftController(this.workspace, this.store, this.key, this.values) {
    _unregister = workspace.registerDraft(flush);
  }
  Future<Map<String, String>?> restore() async {
    final draft = await workspace.repository.draft(
      workspace.user.id,
      store?.id ?? '',
      key,
    );
    if (revision != 0 || draft == null || submitting || completed) return null;
    final restored = draft['values'] is Map ? draft['values'] as Map : draft;
    values = {
      for (final e in restored.entries)
        if (e.value is String) '${e.key}': e.value as String,
    };
    return values;
  }

  Future<void> change(Map<String, String> next) {
    if (completed || submitting) return _tail;
    revision++;
    values = Map.unmodifiable(next);
    return flush();
  }

  Future<void> flush() {
    if (completed) return Future.value();
    if (submitting) return _tail;
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

  Future<void> beginSubmission() async {
    final persisted = flush();
    submitting = true;
    // Every prior write must finish before an outbox transaction removes this
    // draft. Access/lifecycle guards may await it, but cannot append stale data.
    await persisted;
  }

  void submissionFailed() => submitting = false;

  Future<void> complete() async {
    completed = true;
    await _tail.catchError((Object _) {});
    await workspace.repository.saveDraft(
      workspace.user.id,
      store?.id ?? '',
      key,
      {},
    );
  }

  void dispose() {
    _unregister();
  }
}
