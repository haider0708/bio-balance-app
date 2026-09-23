import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/group_repository.dart';
import '../../../domain/models/models.dart';
import '../authentication/session_view_model.dart';

class LifecycleViewModel extends ChangeNotifier {
  final GroupRepository repository;
  final String groupId;
  final String? storeId;
  final int version;
  final String initialStatus;
  LifecycleViewModel(
    this.repository, {
    required this.groupId,
    this.storeId,
    required this.version,
    required this.initialStatus,
  });
  Json? impact;
  String? error;
  bool loading = false, saving = false, closed = false;
  Json? _submission;
  bool get hasUncertainSubmission => _submission != null;
  Future<void> load() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      impact = await repository.lifecycleImpact(groupId, storeId: storeId);
      error = null;
    } catch (e) {
      error = SessionViewModel.message(e);
    } finally {
      loading = false;
      if (!closed) notifyListeners();
    }
  }

  Future<bool> save(String status, String reason) async {
    if (saving) return false;
    if (reason.trim().length < 3) {
      error = 'Précisez le motif (au moins 3 caractères).';
      notifyListeners();
      return false;
    }
    saving = true;
    error = null;
    notifyListeners();
    _submission ??= {
      'operationId': const Uuid().v4(),
      'expectedVersion': version,
      'status': status,
      'reason': reason.trim(),
    };
    try {
      await repository.lifecycle(groupId, _submission!, storeId: storeId);
      return true;
    } catch (e) {
      error = SessionViewModel.message(e);
      if (e is AppFailure && e.code != 'RETRY_LATER') _submission = null;
      return false;
    } finally {
      saving = false;
      if (!closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }
}
