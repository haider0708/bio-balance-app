import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';

class AttentionRow {
  const AttentionRow({
    required this.locationId,
    required this.productId,
    required this.place,
    required this.kind,
    required this.product,
    required this.family,
    required this.quantity,
  });

  factory AttentionRow.fromJson(Json j) => AttentionRow(
    locationId: j.str('locationId'),
    productId: j.str('productId'),
    place: j.str('place'),
    kind: j.str('kind'),
    product: j.str('product'),
    family: j.str('family'),
    quantity: j.integer('quantity'),
  );

  final String locationId;
  final String productId;
  final String place;
  final String kind;
  final String product;
  final String family;
  final int quantity;
}

class ReportsRepository {
  ReportsRepository(this._ref);

  final Ref _ref;

  Future<List<AttentionRow>> attention({String? regionId}) async => jsonList(
    await _ref
        .read(apiClientProvider)
        .get('/v1/reports/stock/attention', query: {'regionId': regionId}),
  ).map(AttentionRow.fromJson).toList();
}

final reportsRepositoryProvider = Provider<ReportsRepository>(
  ReportsRepository.new,
);

final stockAttentionProvider = FutureProvider.autoDispose<List<AttentionRow>>(
  (ref) => ref.watch(reportsRepositoryProvider).attention(),
);
