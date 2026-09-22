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
  Future<Map<String, String>?>? _restoration;
  int revision = 0, _persistedRevision = -1;
  bool _writing = false;
  bool completed = false, submitting = false;
  FormDraftController(this.workspace, this.store, this.key, this.values) {
    _unregister = workspace.registerDraft(flush);
  }
  Future<Map<String, String>?> restore() => _restoration = _restore();

  Future<Map<String, String>?> _restore() async {
    final draft = await workspace.repository.draft(
      workspace.user.id,
      store?.id ?? '',
      key,
    );
    if (revision != 0 || submitting || completed) return null;
    _persistedRevision = revision;
    if (draft == null) return null;
    final restored = draft['values'] is Map ? draft['values'] as Map : draft;
    values = {
      for (final e in restored.entries)
        if (e.value is String) '${e.key}': e.value as String,
    };
    _persistedRevision = revision;
    return values;
  }

  Future<void> change(Map<String, String> next) {
    if (completed || submitting) return _tail;
    revision++;
    values = Map.unmodifiable(next);
    return flush();
  }

  Future<void> flush() async {
    await _restoration;
    return _flush();
  }

  Future<void> _flush() {
    if (completed) return Future.value();
    if (submitting) return _tail;
    if (_writing || _persistedRevision == revision) return _tail;
    _writing = true;
    _tail = _drain();
    return _tail;
  }

  Future<void> _drain() async {
    try {
      // Coalesce rapid edits while SQLite is busy. Never enqueue an unbounded
      // write per keystroke, and keep the latest revision dirty after a failure.
      while (_persistedRevision != revision) {
        final capturedRevision = revision;
        final captured = Map<String, String>.from(values);
        await workspace.repository.saveDraft(
          workspace.user.id,
          store?.id ?? '',
          key,
          {'values': captured},
        );
        _persistedRevision = capturedRevision;
      }
    } finally {
      _writing = false;
    }
  }

  Future<void> beginSubmission() async {
    await flush();
    submitting = true;
    final persisted = _tail;
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
