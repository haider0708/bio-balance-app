import '../../domain/models/models.dart';
import '../services/api/generated/models.dart';
import 'repository_context.dart';

class CatalogRepository {
  final RepositoryContext context;
  CatalogRepository(this.context);
  Future<Product> save(Json input) => context.run(
    () async => Product.fromJson(
      (await context.api.catalogSave(
        body: CatalogSaveRequestDto.fromJson(input),
      )).toJson(),
    ),
  );
  Future<void> importRows(List<Json> rows, {required bool commit}) =>
      context.run(() async {
        await context.api.catalogImport(
          body: CatalogImportRequestDto.fromJson({
            'rows': rows,
            'commit': commit,
          }),
        );
      });
  Future<void> configure(Store store, String productId, Json input) =>
      context.run(() async {
        await context.api.workspaceConfig(
          store: store.id,
          organizationId: store.organizationId,
          product: productId,
          body: WorkspaceConfigRequestDto.fromJson(input),
        );
      });
}
