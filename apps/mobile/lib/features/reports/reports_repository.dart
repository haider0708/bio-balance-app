import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';

class ReportRow {
  const ReportRow({
    required this.key,
    required this.label,
    required this.sales,
    required this.units,
    required this.rewardMillimes,
    this.imageId,
  });

  factory ReportRow.fromJson(Json j) => ReportRow(
    key: j.str('key'),
    label: j.str('label'),
    sales: j.integer('sales'),
    units: j.integer('units'),
    rewardMillimes: j.integer('rewardMillimes'),
    imageId: j.strOrNull('imageId'),
  );

  final String? imageId;
  final String key;
  final String label;
  final int sales;
  final int units;
  final int rewardMillimes;
}

class SalesReport {
  const SalesReport({
    required this.rows,
    required this.sales,
    required this.units,
    required this.rewardMillimes,
    required this.previousUnits,
    required this.previousRewardMillimes,
    required this.trend,
  });

  factory SalesReport.fromJson(Json j) => SalesReport(
    rows: j.list('rows').map(ReportRow.fromJson).toList(),
    sales: j.obj('totals').integer('sales'),
    units: j.obj('totals').integer('units'),
    rewardMillimes: j.obj('totals').integer('rewardMillimes'),
    previousUnits: j.objOrNull('previous')?.integer('units') ?? 0,
    previousRewardMillimes:
        j.objOrNull('previous')?.integer('rewardMillimes') ?? 0,
    trend: ((j['trend'] as List<dynamic>?) ?? const []).cast<Json>(),
  );

  /// Units and rewards of the period just before this one, to show the direction.
  final int previousUnits;
  final int previousRewardMillimes;
  final List<Json> trend;

  /// Change against the previous period, in percent; null when there was nothing to compare with.
  static int? change(int now, int before) =>
      before == 0 ? null : ((now - before) * 100 / before).round();

  final List<ReportRow> rows;
  final int sales;
  final int units;
  final int rewardMillimes;
}

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

typedef ReportQuery = ({
  String from,
  String to,
  String groupBy,
  String? regionId,
  String? pdvId,
  String? sellerId,
  String? productId,
  String? family,
});

class ReportsRepository {
  ReportsRepository(this._ref);

  final Ref _ref;

  Future<SalesReport> sales(ReportQuery q) async => SalesReport.fromJson(
    await _ref
            .read(apiClientProvider)
            .get(
              '/v1/reports/sales',
              query: {
                'from': q.from,
                'to': q.to,
                'groupBy': q.groupBy,
                'regionId': q.regionId,
                'pdvId': q.pdvId,
                'sellerId': q.sellerId,
                'productId': q.productId,
                'family': q.family,
              },
            )
        as Json,
  );

  Future<Uint8List> csv({
    required String from,
    required String to,
    String? regionId,
  }) async => Uint8List.fromList(
    await _ref
        .read(apiClientProvider)
        .bytes(
          '/v1/reports/sales.csv',
          query: {'from': from, 'to': to, 'regionId': regionId},
        ),
  );

  Future<List<AttentionRow>> attention({String? regionId}) async => jsonList(
    await _ref
        .read(apiClientProvider)
        .get('/v1/reports/stock/attention', query: {'regionId': regionId}),
  ).map(AttentionRow.fromJson).toList();
}

final reportsRepositoryProvider = Provider<ReportsRepository>(
  ReportsRepository.new,
);

final salesReportProvider = FutureProvider.autoDispose
    .family<SalesReport, ReportQuery>(
      (ref, q) => ref.watch(reportsRepositoryProvider).sales(q),
    );

final stockAttentionProvider = FutureProvider.autoDispose<List<AttentionRow>>(
  (ref) => ref.watch(reportsRepositoryProvider).attention(),
);
