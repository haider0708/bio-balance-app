import '../../domain/models/models.dart';
import 'repository_context.dart';

class ReportingRepository {
  final RepositoryContext context;
  ReportingRepository(this.context);
  Future<Json> overview() =>
      context.run(() async => (await context.api.adminOverview()).toJson());
  Future<Json> history(
    Store store,
    String resource, {
    String? productId,
    String? before,
  }) => context.run(
    () async => (await context.api.workspaceHistory(
      store: store.id,
      organizationId: store.organizationId,
      resource: resource,
      productId: productId,
      before: before,
    )).toJson(),
  );
}
