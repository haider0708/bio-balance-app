import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../data/repositories/notifications_repository.dart';
import '../../../domain/models/models.dart';
import '../authentication/session_view_model.dart';

/// Polls only a visible inbox. One request at a time, with backoff on failure.
class NotificationsViewModel extends ChangeNotifier {
  final NotificationsRepository repository;
  NotificationsViewModel(this.repository);
  List<Json> items = const [];
  String? error;
  bool loading = true;
  bool _active = false, _closed = false, _fetching = false, _blocked = false;
  int _failures = 0;
  Timer? _timer;

  void setActive(bool active) {
    if (_closed || _active == active) return;
    _active = active;
    _timer?.cancel();
    if (active && !_blocked) unawaited(load());
  }

  Future<void> load() async {
    if (_closed || !_active || _fetching) return;
    _timer?.cancel();
    _fetching = true;
    var changed = loading || error != null;
    try {
      final result = await repository.list();
      if (_closed) return;
      if (result.length != items.length ||
          result.asMap().entries.any(
            (e) => !mapEquals(e.value, items[e.key]),
          )) {
        items = List.unmodifiable(result);
        changed = true;
      }
      _failures = 0;
      _blocked = false;
      error = null;
    } catch (e) {
      if (_closed) return;
      final message = SessionViewModel.message(e);
      changed = changed || message != error;
      error = message;
      _failures = math.min(4, _failures + 1);
      _blocked =
          (e is DioException && [401, 403].contains(e.response?.statusCode)) ||
          (e is AppFailure &&
              [
                'SESSION_EXPIRED',
                'ACCESS_BLOCKED',
                'FORBIDDEN',
                'ACCOUNT_CHANGED',
                'ACCESS_DISABLED',
                'STORE_ACCESS_REVOKED',
              ].contains(e.code));
    } finally {
      _fetching = false;
      if (!_closed) {
        loading = false;
        if (changed) notifyListeners();
        if (_active && !_blocked) {
          _timer = Timer(
            Duration(seconds: math.min(60, 4 * (1 << _failures))),
            () => unawaited(load()),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    super.dispose();
  }
}
