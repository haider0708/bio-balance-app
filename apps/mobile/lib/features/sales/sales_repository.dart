import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import '../catalog/product.dart';
import 'sales_models.dart';
import 'sales_outbox.dart';

/// What happened when a sale was recorded: confirmed by the server, or kept on the phone for later.
sealed class SaleOutcome {
  const SaleOutcome();
}

class SaleRecorded extends SaleOutcome {
  const SaleRecorded(this.sale);

  final Sale sale;
}

class SaleQueued extends SaleOutcome {
  const SaleQueued(this.pending);

  final PendingSale pending;
}

class CartLine {
  const CartLine(this.product, this.quantity);

  final Product product;
  final int quantity;
}

class SalesRepository {
  SalesRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  /// Record a sale. With no connection it is saved on the phone and sent later.
  Future<SaleOutcome> record(List<CartLine> cart) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final lines = [
      for (final l in cart)
        PendingLine(
          productId: l.product.id,
          name: l.product.name,
          quantity: l.quantity,
        ),
    ];
    try {
      final data = await _ref.read(apiClientProvider).post('/v1/sales', {
        'id': id,
        'occurredAt': now.toUtc().toIso8601String(),
        'lines': [
          for (final l in lines)
            {'productId': l.productId, 'quantity': l.quantity},
        ],
      }) as Json;
      return SaleRecorded(Sale.fromJson(data));
    } on ApiException catch (error) {
      // Timeouts count too: the server may have it already, and the same id makes a resend harmless.
      if (error.isOffline || error.code == 'TIMEOUT') {
        final pending = PendingSale(id: id, occurredAt: now, lines: lines);
        await _ref.read(salesOutboxProvider.notifier).add(pending);
        return SaleQueued(pending);
      }
      rethrow;
    }
  }

  Future<SalesPage> list({
    String? cursor,
    String? from,
    String? to,
    String? pdvId,
    String? sellerId,
    String? regionId,
    String? groupId,
    String? productId,
    String? family,
    String? status,
    int limit = 30,
  }) async {
    final data =
        await _ref
                .read(apiClientProvider)
                .get(
                  '/v1/sales',
                  query: {
                    'cursor': cursor,
                    'limit': limit,
                    'from': from,
                    'to': to,
                    'pdvId': pdvId,
                    'sellerId': sellerId,
                    'regionId': regionId,
                    'groupId': groupId,
                    'productId': productId,
                    'family': family,
                    'status': status,
                  },
                )
            as Json;
    return SalesPage(
      data.list('items').map(Sale.fromJson).toList(),
      data.strOrNull('nextCursor'),
    );
  }

  /// One row per day, to read a long history at a glance.
  Future<List<SaleDay>> days({
    required String from,
    required String to,
    String? pdvId,
    String? sellerId,
  }) async => jsonList(
    await _ref
        .read(apiClientProvider)
        .get(
          '/v1/sales/days',
          query: {'from': from, 'to': to, 'pdvId': pdvId, 'sellerId': sellerId},
        ),
  ).map(SaleDay.fromJson).toList();

  Future<Sale> get(String id) async => Sale.fromJson(
    await _ref.read(apiClientProvider).get('/v1/sales/$id') as Json,
  );

  Future<Sale> correct(
    String id, {
    required String reason,
    required List<Map<String, Object>> lines,
  }) async => Sale.fromJson(
    await _ref.read(apiClientProvider).post('/v1/sales/$id/correct', {
      'reason': reason,
      'lines': lines,
    }) as Json,
  );
}

final salesRepositoryProvider = Provider<SalesRepository>(SalesRepository.new);

final saleProvider = FutureProvider.autoDispose.family<Sale, String>(
  (ref, id) => ref.watch(salesRepositoryProvider).get(id),
);

typedef SalesDaysQuery = ({
  String from,
  String to,
  String? pdvId,
  String? sellerId,
});

final salesDaysProvider = FutureProvider.autoDispose
    .family<List<SaleDay>, SalesDaysQuery>(
      (ref, q) => ref
          .watch(salesRepositoryProvider)
          .days(from: q.from, to: q.to, pdvId: q.pdvId, sellerId: q.sellerId),
    );

typedef SalesOfDayQuery = ({String day, String? pdvId, String? sellerId});

/// The sales of one day, opened from the overview.
final salesOfDayProvider = FutureProvider.autoDispose
    .family<List<Sale>, SalesOfDayQuery>(
      (ref, q) async =>
          (await ref
                  .watch(salesRepositoryProvider)
                  .list(
                    from: q.day,
                    to: q.day,
                    pdvId: q.pdvId,
                    sellerId: q.sellerId,
                    limit: 100,
                  ))
              .items,
    );
