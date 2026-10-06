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
      for (final l in cart) PendingLine(productId: l.product.id, name: l.product.name, quantity: l.quantity),
    ];
    try {
      final data = await _ref.read(apiClientProvider).post('/v1/sales', {
        'id': id,
        'occurredAt': now.toUtc().toIso8601String(),
        'lines': [for (final l in lines) {'productId': l.productId, 'quantity': l.quantity}],
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

  Future<SalesPage> list({String? cursor, String? from, String? to, String? pdvId, String? sellerId, String? regionId}) async {
    final data = await _ref.read(apiClientProvider).get('/v1/sales', query: {
      'cursor': cursor, 'limit': 30, 'from': from, 'to': to, 'pdvId': pdvId, 'sellerId': sellerId, 'regionId': regionId,
    }) as Json;
    return SalesPage(data.list('items').map(Sale.fromJson).toList(), data.strOrNull('nextCursor'));
  }

  Future<Sale> get(String id) async => Sale.fromJson(await _ref.read(apiClientProvider).get('/v1/sales/$id') as Json);

  Future<Sale> correct(String id, {required String reason, required List<Map<String, Object>> lines}) async =>
      Sale.fromJson(await _ref.read(apiClientProvider).post('/v1/sales/$id/correct', {'reason': reason, 'lines': lines}) as Json);
}

final salesRepositoryProvider = Provider<SalesRepository>(SalesRepository.new);

final saleProvider = FutureProvider.autoDispose.family<Sale, String>((ref, id) => ref.watch(salesRepositoryProvider).get(id));
