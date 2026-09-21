import '../../domain/models/models.dart';
import 'repository_context.dart';

class NotificationsRepository {
  final RepositoryContext context;
  NotificationsRepository(this.context);
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
