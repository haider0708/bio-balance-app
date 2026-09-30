import '../../domain/models/models.dart';
import 'repository_context.dart';

/// Damaged or expired goods flagged by stores and depots, and BioBalance's decisions.
class QualityRepository {
  final RepositoryContext context;
  const QualityRepository(this.context);

  /// A store, a group or depot, or (BioBalance only) the whole network.
  Future<List<Json>> list({
    String? organizationId,
    String? storeId,
    String status = 'open',
  }) => context.run(
    () async => (await context.api.qualityList(
      organizationId: organizationId,
      storeId: storeId,
      status: status,
    )).items.map((f) => f.toJson()).toList(),
  );
}
