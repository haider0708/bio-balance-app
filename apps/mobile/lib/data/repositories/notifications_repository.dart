import '../../domain/models/models.dart';
import 'repository_context.dart';
import 'offline_repository.dart';

class NotificationsRepository {
  final RepositoryContext context;
  final OfflineRepository? local;
  final String? accountId;
  NotificationsRepository(this.context, {this.local, this.accountId});
  Future<Json?> cached() async => accountId == null
      ? null
      : local?.draft(accountId!, '', 'notification-inbox');
  Future<Json> page({String? cursor}) => context.run(() async {
    final result = (await context.api.notificationsInbox(cursor: cursor))
        .toJson();
    if (cursor == null && local != null && accountId != null) {
      context.check();
      await local!.saveDraft(accountId!, '', 'notification-inbox', result);
    }
    return result;
  });
  Future<List<Json>> list({String? before}) => context.run(
    () async =>
        (await context.api.notificationsList(before: before))
            .map((n) => n.toJson())
            .toList(),
  );
  Future<Json> get(String id) => context.run(
    () async => (await context.api.notificationsGet(id: id)).toJson(),
  );
  Future<void> read(String id) => context.run(() async {
    await context.api.notificationsRead(id: id);
  });
}
