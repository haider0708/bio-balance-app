import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../data/repositories/notifications_repository.dart';
import '../../../domain/models/models.dart';
import '../authentication/session_view_model.dart';

/// One foreground, account-bound feed shared by the bell and inbox.
class NotificationsViewModel extends ChangeNotifier {
  final NotificationsRepository repository;
  NotificationsViewModel(this.repository);
  List<Json> items = const [];
  String? error, nextCursor, _accessKey;
  int unreadCount = 0;
  bool cached = false;
  Future<void> restore() async {
    Json? value;
    try {
      value = await repository.cached();
    } catch (_) {
      return;
    }
    if (_closed || value == null || !loading) return;
    items = List.unmodifiable(objects(value['items']));
    unreadCount = integer(value['unreadCount']);
    nextCursor = value['nextCursor'];
    _accessKey = value['accessKey'];
    cached = true;
    notifyListeners();
  }

  bool loading = true;
  bool _active = false, _closed = false, _fetching = false, _blocked = false;
  int _failures = 0;
  bool _expanded = false;
  Timer? _timer;

  void setActive(bool active) {
    if (_closed || _active == active) return;
    _active = active;
    _timer?.cancel();
    if (active && !_blocked) unawaited(load());
  }

  Future<void> load({bool more = false}) async {
    if (_closed || !_active || _fetching) return;
    _timer?.cancel();
    _expanded = _expanded || more;
    _fetching = true;
    var changed = loading || error != null;
    try {
      final page = await repository.page(cursor: more ? nextCursor : null);
      final result = objects(page['items']);
      if (_closed) return;
      if (_accessKey != null && _accessKey != page['accessKey']) {
        items = const [];
        _expanded = false;
        changed = true;
      }
      _accessKey = page['accessKey'];
      final count = integer(page['unreadCount']);
      changed = changed || count != unreadCount || cached;
      unreadCount = count;
      if (more || !_expanded) nextCursor = page['nextCursor'];
      cached = false;
      if (_expanded) {
        final byId = more
            ? {
                for (final n in items) n['id']: n,
                for (final n in result) n['id']: n,
              }
            : {
                for (final n in result) n['id']: n,
                for (final n in items.where(
                  (old) => !result.any((n) => n['id'] == old['id']),
                ))
                  n['id']: n,
              };
        items = List.unmodifiable(byId.values.take(500));
        changed = true;
      } else if (result.length != items.length ||
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
      cached = items.isNotEmpty;
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
      if (_blocked) {
        items = const [];
        unreadCount = 0;
        nextCursor = null;
        changed = true;
      }
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
