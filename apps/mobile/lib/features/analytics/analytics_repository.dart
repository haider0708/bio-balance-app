import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import '../sales/sales_models.dart';
import '../sales/sales_repository.dart';
import 'lens.dart';

/// The stores board: a period and optionally a region or a group.
typedef StoresQuery = ({
  String from,
  String to,
  String? regionId,
  String? groupId,
});

class AnalyticsRepository {
  AnalyticsRepository(this._ref);

  final Ref _ref;

  Future<Json> overview(Lens lens) async =>
      await _ref
              .read(apiClientProvider)
              .get(
                '/v1/analytics/overview',
                query: {...lens.query, 'sort': lens.sort.name},
              )
          as Json;

  Future<Json> stores(StoresQuery q) async =>
      await _ref
              .read(apiClientProvider)
              .get(
                '/v1/analytics/stores',
                query: {
                  'from': q.from,
                  'to': q.to,
                  'regionId': q.regionId,
                  'groupId': q.groupId,
                },
              )
          as Json;

  /// The sales behind a lens, newest first; [voidedOnly] keeps the cancelled ones.
  Future<SalesPage> sales(
    Lens lens, {
    String? cursor,
    int limit = 30,
    bool voidedOnly = false,
  }) => _ref
      .read(salesRepositoryProvider)
      .list(
        cursor: cursor,
        limit: limit,
        from: lens.from,
        to: lens.to,
        regionId: lens.regionId,
        groupId: lens.groupId,
        pdvId: lens.pdvId,
        sellerId: lens.sellerId,
        productId: lens.productId,
        family: lens.family,
        status: voidedOnly ? 'VOIDED' : null,
      );

  /// One line per product sold under the lens, for a spreadsheet.
  Future<Uint8List> csv(Lens lens) async => Uint8List.fromList(
    await _ref
        .read(apiClientProvider)
        .bytes('/v1/reports/sales.csv', query: lens.query),
  );
}

final analyticsRepositoryProvider = Provider<AnalyticsRepository>(
  AnalyticsRepository.new,
);

final analyticsProvider = FutureProvider.autoDispose.family<Json, Lens>(
  (ref, lens) => ref.watch(analyticsRepositoryProvider).overview(lens),
);

final storesBoardProvider = FutureProvider.autoDispose
    .family<Json, StoresQuery>(
      (ref, q) => ref.watch(analyticsRepositoryProvider).stores(q),
    );

/// The latest sales of a lens, shown under its numbers.
final latestSalesProvider = FutureProvider.autoDispose.family<List<Sale>, Lens>(
  (ref, lens) async =>
      (await ref.watch(analyticsRepositoryProvider).sales(lens, limit: 8))
          .items,
);
