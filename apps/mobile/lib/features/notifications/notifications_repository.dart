import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'notification_models.dart';

class NotificationsRepository {
  NotificationsRepository(this._ref);

  final Ref _ref;

  Future<NotificationsPage> page({String? cursor}) async =>
      NotificationsPage.fromJson(
        await _ref
                .read(apiClientProvider)
                .get(
                  '/v1/notifications',
                  query: {'cursor': cursor, 'limit': 30},
                )
            as Json,
      );

  Future<int> unread() async =>
      ((await _ref
                  .read(apiClientProvider)
                  .get('/v1/notifications/unread-count'))
              as Json)
          .integer('unread');

  Future<void> markRead(String id) =>
      _ref.read(apiClientProvider).post('/v1/notifications/$id/read');

  Future<void> markAllRead() =>
      _ref.read(apiClientProvider).post('/v1/notifications/read-all');
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  NotificationsRepository.new,
);

/// How often the unread badge refreshes while the app is open; null turns polling off (tests).
final unreadPollIntervalProvider = Provider<Duration?>(
  (_) => const Duration(seconds: 60),
);

/// The unread badge: checked now and every minute while the app is open.
class UnreadCount extends Notifier<int> {
  @override
  int build() {
    final repo = ref.watch(notificationsRepositoryProvider);
    Future<void> check() async {
      try {
        state = await repo.unread();
      } catch (_) {
        // Offline: keep showing the last number.
      }
    }

    unawaited(check());
    final every = ref.watch(unreadPollIntervalProvider);
    if (every != null) {
      final timer = Timer.periodic(every, (_) => unawaited(check()));
      ref.onDispose(timer.cancel);
    }
    return 0;
  }

  Future<void> refresh() async {
    try {
      state = await ref.read(notificationsRepositoryProvider).unread();
    } catch (_) {
      // Keep the last number.
    }
  }
}

final unreadCountProvider = NotifierProvider<UnreadCount, int>(UnreadCount.new);
