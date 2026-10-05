import 'package:uuid/uuid.dart';

import '../../domain/models/models.dart';
import '../services/api/generated/models.dart';
import 'repository_context.dart';

/// Wholesale (A), store-supply (B) and retail (C) prices. The server returns
/// only the levels the signed-in role may see; a hidden level is null.
class PricingRepository {
  final RepositoryContext context;
  const PricingRepository(this.context);

  /// Current prices of a store or depot, by product id.
  Future<Map<String, Json>> current(Store store) => context.run(() async {
    final page = await context.api.pricingCurrent(
      organizationId: store.organizationId,
      storeId: store.id,
    );
    return {for (final item in page.items) item.productId: item.toJson()};
  });

  /// BioBalance's default list of one level, by product id.
  Future<Map<String, Json>> defaults(String level) => context.run(() async {
    final page = await context.api.pricingDefaults(level: level);
    return {for (final item in page.items) item.productId: item.toJson()};
  });

  Future<List<Json>> history(String productId, {Store? store, String? level}) =>
      context.run(
        () async => (await context.api.pricingHistory(
          productId: productId,
          organizationId: store?.organizationId,
          storeId: store?.id,
          level: level,
        )).items.map((e) => e.toJson()).toList(),
      );

  /// One operation id per form: a retry never records the same change twice.
  Future<Json> set(Json values, {String? operationId}) => context.run(
    () async => (await context.api.pricingSet(
      body: PricingSetRequestDto.fromJson({
        'operationId': operationId ?? const Uuid().v4(),
        ...values,
      }),
    )).toJson(),
  );
}
