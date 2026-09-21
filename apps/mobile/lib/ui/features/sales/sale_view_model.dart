import 'package:flutter/foundation.dart';

import '../../../domain/models/models.dart';
import '../../../domain/use_cases/record_sale.dart';
import '../workspace/workspace_view_model.dart';
import '../authentication/session_view_model.dart';

class SaleEditorState {
  final List<SaleLine> lines;
  final bool saving;
  final String? error;
  SaleEditorState({
    List<SaleLine> lines = const [],
    this.saving = false,
    this.error,
  }) : lines = List.unmodifiable(lines);
}

class SaleViewModel extends ChangeNotifier {
  final WorkspaceViewModel workspace;
  final Json? original;
  final Store store;
  final Json? recovery;
  SaleEditorState state = SaleEditorState();
  SaleViewModel(this.workspace, {this.original, this.recovery})
    : store = workspace.state.store!;
  String get draftKey => recovery != null
      ? 'recovery:${recovery!['saleId']}'
      : original == null
      ? 'sale'
      : 'sale:${original!['id']}';
  Future<void> restore() async {
    final draft = await workspace.repository.draft(
      workspace.user.id,
      store.id,
      draftKey,
    );
    state = SaleEditorState(
      lines: objects(
        draft?['lines'] ?? recovery?['lines'] ?? original?['lines'],
      ).map(SaleLine.fromJson).toList(),
    );
    notifyListeners();
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
  Future<void> put(SaleLine line) async {
    final lines = [...state.lines];
    final i = lines.indexWhere((l) => l.id == line.id);
    if (i < 0) {
      lines.add(line);
    } else {
      lines[i] = line;
    }
    await _change(lines);
  }

  Future<void> remove(String id) =>
      _change(state.lines.where((l) => l.id != id).toList());
  Future<void> _change(List<SaleLine> lines) async {
    try {
      await workspace.repository.saveDraft(
        workspace.user.id,
        store.id,
        draftKey,
        {'lines': lines.map((l) => l.toJson()).toList()},
      );
      state = SaleEditorState(lines: lines);
    } catch (e) {
      state = SaleEditorState(
        lines: lines,
        error: 'Le brouillon n’a pas pu être enregistré sur ce téléphone. Vérifiez l’espace disponible.',
      );
    }
    notifyListeners();
  }

  Future<bool> save(String reason) async {
    state = SaleEditorState(lines: state.lines, saving: true);
    notifyListeners();
    try {
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
      await workspace.reloadLocal();
      state = SaleEditorState(lines: state.lines);
      notifyListeners();
      return true;
    } catch (e) {
      state = SaleEditorState(
        lines: state.lines,
        error: SessionViewModel.message(e),
      );
      notifyListeners();
      return false;
    }
  }
}
