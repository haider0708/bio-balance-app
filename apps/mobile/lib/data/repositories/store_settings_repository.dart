import '../../domain/models/models.dart';
import '../services/api/generated/api_client.dart';
import '../services/api/generated/models.dart';
import 'repository_context.dart';

class StoreSettingsRepository {
  final RepositoryContext context;
  StoreSettingsRepository(ApiClient api) : context = RepositoryContext(api);
  Future<List<Json>> organizations() => context.run(
    () async => (await context.api.workspaceOrganizations())
        .map((o) => o.toJson())
        .toList(),
  );
  Future<Store> create(Json input) => context.run(
    () async => Store.fromJson(
      (await context.api.workspaceCreate(
        body: WorkspaceCreateRequestDto.fromJson(input),
      )).toJson(),
    ),
  );
  Future<void> update(Store store, Json input) => context.run(() async {
    await context.api.workspaceUpdateStore(
      store: store.id,
      organizationId: store.organizationId,
      body: WorkspaceUpdateStoreRequestDto.fromJson(input),
    );
  });
  Future<void> onboarding(Store store, Json input) => context.run(() async {
    await context.api.workspaceOnboarding(
      store: store.id,
      organizationId: store.organizationId,
      body: WorkspaceOnboardingRequestDto.fromJson(input),
    );
  });
}
