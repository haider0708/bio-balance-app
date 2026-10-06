import '../../core/api/json.dart';
import '../../core/l10n/server_text.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.key,
    this.params = const {},
    this.title,
    this.body,
    this.pinned = false,
    this.entityType,
    this.entityId,
    this.readAt,
  });

  factory AppNotification.fromJson(Json j) => AppNotification(
        id: j.str('id'),
        kind: j.str('kind'),
        key: j.strOrNull('key'),
        params: j.obj('params'),
        title: j.strOrNull('title'),
        body: j.strOrNull('body'),
        pinned: j.flag('pinned'),
        entityType: j.strOrNull('entityType'),
        entityId: j.strOrNull('entityId'),
        readAt: j.dateOrNull('readAt'),
        createdAt: j.date('createdAt'),
      );

  final String id;

  /// MESSAGE (written by the admin) or SYSTEM (an event).
  final String kind;
  final String? key;
  final Json params;
  final String? title;
  final String? body;
  final bool pinned;
  final String? entityType;
  final String? entityId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isMessage => kind == 'MESSAGE';
  bool get unread => readAt == null;

  /// The headline in the person's language.
  String headline(String locale) => isMessage ? (title ?? '') : ServerText.notification(locale, key ?? '', params, fallback: title);
}

class NotificationsPage {
  const NotificationsPage({required this.items, required this.pinned, required this.unread, this.nextCursor});

  factory NotificationsPage.fromJson(Json j) => NotificationsPage(
        items: j.list('items').map(AppNotification.fromJson).toList(),
        pinned: j.list('pinned').map(AppNotification.fromJson).toList(),
        unread: j.integer('unread'),
        nextCursor: j.strOrNull('nextCursor'),
      );

  final List<AppNotification> items;
  final List<AppNotification> pinned;
  final int unread;
  final String? nextCursor;
}
