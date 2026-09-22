import 'package:flutter/foundation.dart';

import '../../../domain/models/models.dart';
import '../../../domain/use_cases/record_sale.dart';
import '../workspace/workspace_view_model.dart';
import '../authentication/session_view_model.dart';

class SaleEditorState {
  final List<SaleLine> lines;
  final bool saving, restoring;
  final String? error;
  SaleEditorState({
    List<SaleLine> lines = const [],
    this.saving = false,
    this.restoring = false,
    this.error,
  }) : lines = List.unmodifiable(lines);
}

class SaleViewModel extends ChangeNotifier {
  final WorkspaceViewModel workspace;
  final Json? original;
  final Store store;
  final Json? recovery;
  SaleEditorState state = SaleEditorState(restoring: true);
  bool _closed = false, _completed = false, _restored = false;
  int _revision = 0;
  Future<void> _draftTail = Future.value();
  Future<bool>? _saving;
  late final VoidCallback _unregisterDraft;
  SaleViewModel(this.workspace, {this.original, this.recovery})
    : store = workspace.state.store! {
    _unregisterDraft = workspace.registerDraft(() async {
      if (_completed || !_restored) return;
      if (state.saving) {
        await _saving;
        return;
      }
      await _persist();
    });
  }
  bool get canEdit => _restored && !state.saving && !_completed && !_closed;
  String get draftKey => recovery != null
      ? 'recovery:${recovery!['saleId']}'
      : original == null
      ? 'sale'
      : 'sale:${original!['id']}';

  void _emit(SaleEditorState value) {
    state = value;
    if (!_closed) notifyListeners();
  }

  Future<void> restore() async {
    if (_restored || _closed) return;
    _emit(SaleEditorState(restoring: true));
    try {
      final draft = await workspace.repository.draft(
        workspace.user.id,
        store.id,
        draftKey,
      );
      if (_closed) return;
      final restored = SaleEditorState(
        lines: objects(
          draft?['lines'] ?? recovery?['lines'] ?? original?['lines'],
        ).map(SaleLine.fromJson).toList(),
      );
      _restored = true;
      _emit(restored);
    } catch (e) {
      _emit(
        SaleEditorState(
          error:
              'Impossible de charger le brouillon. ${SessionViewModel.message(e)}',
        ),
      );
    }
  }

  int get total =>
      state.lines.fold(0, (s, l) => s + l.price.millimes * l.quantity);
  int get estimatedPoints => state.lines.fold(
    0,
    (s, l) =>
        s +
        l.quantity *
            integer(workspace.state.data?.config(l.productId)['pointsPerUnit']),
  );

  Future<bool> put(SaleLine line) {
    final lines = [...state.lines];
    final i = lines.indexWhere((l) => l.id == line.id);
    if (i < 0) {
      lines.add(line);
    } else {
      lines[i] = line;
    }
    return _change(lines);
  }

  Future<bool> remove(String id) =>
      _change(state.lines.where((l) => l.id != id).toList());

  Future<void> _persist() {
    final lines = state.lines.map((l) => l.toJson()).toList();
    final next = _draftTail.then(
      (_) => workspace.repository.saveDraft(
        workspace.user.id,
        store.id,
        draftKey,
        {'lines': lines},
      ),
    );
    _draftTail = next.catchError((Object _) {});
    return next;
  }

  Future<bool> _change(List<SaleLine> lines) async {
    if (!canEdit) return false;
    final revision = ++_revision;
    // Publish immediately so a second edit is based on the latest lines.
    // Serialize disk writes so an older draft cannot overwrite a newer one.
    _emit(SaleEditorState(lines: lines));
    try {
      await _persist();
      return true;
    } catch (_) {
      if (revision == _revision && !_completed) {
        _emit(
          SaleEditorState(
            lines: state.lines,
            saving: state.saving,
            error: 'Le brouillon n’a pas pu être enregistré sur ce téléphone. Vérifiez l’espace disponible.',
          ),
        );
      }
      return false;
    }
  }

  Future<bool> save(String reason) {
    if (_completed) return Future.value(true);
    if (_saving != null) return _saving!;
    if (!canEdit) return Future.value(false);
    return _saving = _save(reason).whenComplete(() => _saving = null);
  }

  Future<bool> _save(String reason) async {
    _emit(SaleEditorState(lines: state.lines, saving: true));
    try {
      // No draft writer may run after enqueue atomically completes this draft.
      await _draftTail;
      workspace.requireAccess(store, 'sell');
      await RecordSale(workspace.repository).execute(
        workspace.user,
        store,
        state.lines,
        original: original,
        reason: reason,
        recoveredSaleId: recovery?['saleId'],
        recoveredDate: recovery?['occurredAt'],
        supersedes: List<String>.from(recovery?['operationIds'] ?? []),
      );
      _completed = true;
    } catch (e) {
      _emit(
        SaleEditorState(lines: state.lines, error: SessionViewModel.message(e)),
      );
      return false;
    }
    await workspace.afterLocalCommit();
    _emit(SaleEditorState(lines: state.lines));
    return true;
  }

  @override
  void dispose() {
    _closed = true;
    _unregisterDraft();
    super.dispose();
  }
}
