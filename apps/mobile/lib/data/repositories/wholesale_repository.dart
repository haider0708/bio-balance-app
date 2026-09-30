import 'package:uuid/uuid.dart';

import '../../domain/models/models.dart';
import '../services/api/generated/models.dart';
import 'repository_context.dart';

/// Grossistes (created by BioBalance) and the store orders assigned to them.
class WholesaleRepository {
  final RepositoryContext context;
  const WholesaleRepository(this.context);

  /// Administrator view of every grossiste, with its depot and invitation state.
  Future<List<Json>> list() => context.run(
    () async =>
        (await context.api.wholesaleList()).map((w) => w.toJson()).toList(),
  );

  /// The same operation id is reused by a retry of the same form, so a lost
  /// response never creates a second grossiste.
  Future<Json> create(Json values, {String? operationId}) => context.run(
    () async => (await context.api.wholesaleCreate(
      body: WholesaleCreateRequestDto.fromJson({
        'operationId': operationId ?? const Uuid().v4(),
        ...values,
      }),
    )).toJson(),
  );

  Future<Json> orders(Store depot, {String phase = 'open', String? after}) =>
      context.run(
        () async => (await context.api.wholesaleOrders(
          organizationId: depot.organizationId,
          storeId: depot.id,
          phase: phase,
          after: after,
        )).toJson(),
      );

  Future<Json> order(Store depot, String id) => context.run(
    () async => (await context.api.wholesaleOrder(
      organizationId: depot.organizationId,
      storeId: depot.id,
      id: id,
    )).toJson(),
  );
}
