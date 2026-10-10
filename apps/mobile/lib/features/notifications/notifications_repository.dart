import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/alerts/background_alerts.dart';
import '../../core/alerts/push.dart';
import '../../core/auth/session.dart';
import 'notification_models.dart';

class NotificationsRepository {
  NotificationsRepository(this._ref);

  final Ref _ref;

  Future<NotificationsPage> page({
    String? cursor,
    String? category,
    bool unreadOnly = false,
  }) async => NotificationsPage.fromJson(
    await _ref
            .read(apiClientProvider)
            .get(
              '/v1/notifications',
              query: {
                'cursor': cursor,
                'limit': 30,
                'category': category,
                'unreadOnly': unreadOnly ? 'true' : null,
              },
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

/// The unread badge: checked now, every minute while the app is in front, and on coming back
/// to it. Nothing is asked while signed out or in the background.
class UnreadCount extends Notifier<int> {
  @override
  int build() {
    final account = ref.watch(accountProvider);
    if (account == null) return 0;
    final repo = ref.watch(notificationsRepositoryProvider);
    Future<void> check() async {
      try {
        final unread = await repo.unread();
        if (ref.mounted) state = unread;
      } catch (_) {
        // Offline: keep showing the last number.
      }
    }

    unawaited(check());
    unawaited(BackgroundAlerts.enable(account, ref.read(apiClientProvider)));
    // The number on the iPhone icon follows the one in the app.
    listenSelf((_, unread) => unawaited(Push.badge(unread)));
    final every = ref.watch(unreadPollIntervalProvider);
    if (every != null) {
      final timer = Timer.periodic(every, (_) {
        if (_inFront) unawaited(check());
      });
      final lifecycle = AppLifecycleListener(
        onResume: () => unawaited(check()),
      );
      ref.onDispose(() {
        timer.cancel();
        lifecycle.dispose();
      });
    }
    return 0;
  }

  static bool get _inFront => switch (WidgetsBinding.instance.lifecycleState) {
    null || AppLifecycleState.resumed => true,
    _ => false,
  };

  Future<void> refresh() async {
    if (ref.read(accountProvider) == null) return;
    try {
      final unread = await ref.read(notificationsRepositoryProvider).unread();
      if (ref.mounted) state = unread;
    } catch (_) {
      // Keep the last number.
    }
  }
}

final unreadCountProvider = NotifierProvider<UnreadCount, int>(UnreadCount.new);
