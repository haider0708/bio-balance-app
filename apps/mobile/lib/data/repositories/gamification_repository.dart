import '../../domain/models/models.dart';
import '../services/api/generated/models.dart';
import 'repository_context.dart';

/// BioBalance's default points and rewards, and each place's exceptions.
class GamificationRepository {
  final RepositoryContext context;
  const GamificationRepository(this.context);

  /// Default rates by product id, and default rewards, of "retail" or "wholesale".
  Future<({Map<String, int> points, List<Json> rewards})> defaults(
    String audience,
  ) => context.run(() async {
    final value = await context.api.gamificationDefaults(audience: audience);
    return (
      points: {for (final p in value.points) p.productId: p.pointsPerUnit},
      rewards: value.rewards.map((r) => r.toJson()).toList(),
    );
  });

  Future<void> setDefault(String audience, String productId, int points) =>
      context.run(
        () => context.api.gamificationPointsDefault(
          body: GamificationPointsDefaultRequestDto.fromJson({
            'audience': audience,
            'productId': productId,
            'pointsPerUnit': points,
          }),
        ),
      );

  Future<void> saveReward(Json values) => context.run(
    () => context.api.gamificationRewardTemplate(
      body: GamificationRewardTemplateRequestDto.fromJson(values),
    ),
  );

  /// A place's rate per product, with the default beside it.
  Future<Map<String, Json>> storePoints(Store store) => context.run(() async {
    final value = await context.api.gamificationStorePoints(
      store: store.id,
      organizationId: store.organizationId,
    );
    return {for (final item in value.items) item.productId: item.toJson()};
  });

  /// The place's own rate, or [points] null to return to the default.
  Future<void> setStorePoints(Store store, String productId, int? points) =>
      context.run(
        () => context.api.gamificationSetStorePoints(
          store: store.id,
          organizationId: store.organizationId,
          body: GamificationSetStorePointsRequestDto.fromJson({
            'productId': productId,
            if (points == null) 'reset': true else 'pointsPerUnit': points,
          }),
        ),
      );
}
