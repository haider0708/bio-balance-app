import '../../domain/models/models.dart';
import 'repository_context.dart';

class SalesRepository {
  final RepositoryContext context;
  SalesRepository(this.context);
  Future<Json> details(Store store, String saleId) => context.run(
    () async => (await context.api.workspaceSale(
      store: store.id,
      organizationId: store.organizationId,
      sale: saleId,
    )).toJson(),
  );
}
