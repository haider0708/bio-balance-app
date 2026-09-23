import 'package:flutter/foundation.dart';

import '../../../domain/models/dashboard.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../authentication/session_view_model.dart';

class DashboardViewModel extends ChangeNotifier {
  final DashboardRepository repository;
  final String scope;
  final String? groupId, storeId;
  DashboardPeriod period;
  DashboardData? data;
  String? error;
  bool loading = false, closed = false;
  int _request = 0;
  DashboardViewModel(
    this.repository, {
    required this.scope,
    this.groupId,
    this.storeId,
  }) : period = scope == 'personal'
           ? DashboardPeriod.today()
           : DashboardPeriod.month();
  Future<void> load([DashboardPeriod? next]) async {
    if (loading && next == null) return;
    if (next != null) {
      period = next;
      data = null;
    }
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.load(
        scope,
        period,
        organizationId: groupId,
        storeId: storeId,
      );
      if (!closed && request == _request) data = result;
    } catch (e) {
      if (!closed && request == _request) error = SessionViewModel.message(e);
    } finally {
      if (!closed && request == _request) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    closed = true;
    _request++;
    super.dispose();
  }
}
