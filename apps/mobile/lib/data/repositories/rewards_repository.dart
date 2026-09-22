import '../../domain/models/models.dart';
import '../../domain/models/ranking.dart';
import '../services/api/generated/models.dart';
import 'repository_context.dart';

class RewardsRepository {
  final RepositoryContext context;
  RewardsRepository(this.context);
  Future<StoreRanking> ranking(Store store) => context.run(() async {
    final value = await context.api.workspaceRanking(
      store: store.id,
      organizationId: store.organizationId,
    );
    return StoreRanking(
      value.month,
      value.scores.map(
        (score) => RankingScore(
          score.userId,
          score.name,
          int.parse(score.score),
          int.parse(score.rank),
        ),
      ),
    );
  });
  Future<void> save(Store store, Json input) => context.run(() async {
    await context.api.workspaceReward(
      store: store.id,
      organizationId: store.organizationId,
      body: WorkspaceRewardRequestDto.fromJson(input),
    );
  });
}
