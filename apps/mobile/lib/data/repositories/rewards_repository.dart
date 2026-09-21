import '../../domain/models/models.dart';
import '../services/api/generated/models.dart';
import 'repository_context.dart';

class RewardsRepository {
  final RepositoryContext context;
  RewardsRepository(this.context);
  Future<Json> ranking(Store store) => context.run(
    () async => (await context.api.workspaceRanking(
      store: store.id,
      organizationId: store.organizationId,
    )).toJson(),
  );
  Future<void> save(Store store, Json input) => context.run(() async {
    await context.api.workspaceReward(
      store: store.id,
      organizationId: store.organizationId,
      body: WorkspaceRewardRequestDto.fromJson(input),
    );
  });
}
