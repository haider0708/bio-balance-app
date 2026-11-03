import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'orders_models.dart';

class OrdersRepository {
  OrdersRepository(this._ref);

  final Ref _ref;

  Future<OrdersOverview> overview() async => OrdersOverview.fromJson(
    await _ref.read(apiClientProvider).get('/v1/orders/overview') as Json,
  );

  Future<List<ParaRow>> paras({String? q, bool lowOnly = false}) async =>
      jsonList(
        await _ref
            .read(apiClientProvider)
            .get(
              '/v1/orders/paras',
              query: {
                if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
                if (lowOnly) 'low': 'true',
              },
            ),
      ).map(ParaRow.fromJson).toList();

  Future<ParaDetail> para(String id) async => ParaDetail.fromJson(
    await _ref.read(apiClientProvider).get('/v1/orders/paras/$id') as Json,
  );

  /// "Do you need anything?": tells the para's team and its responsable.
  Future<void> ask(String id, {String? message}) async {
    await _ref.read(apiClientProvider).post('/v1/orders/paras/$id/ask', {
      if (message != null && message.trim().isNotEmpty)
        'message': message.trim(),
    });
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>(
  OrdersRepository.new,
);

final ordersOverviewProvider = FutureProvider.autoDispose<OrdersOverview>(
  (ref) => ref.watch(ordersRepositoryProvider).overview(),
);

typedef ParaQuery = ({String q, bool lowOnly});

final parasProvider = FutureProvider.autoDispose
    .family<List<ParaRow>, ParaQuery>(
      (ref, query) => ref
          .watch(ordersRepositoryProvider)
          .paras(q: query.q, lowOnly: query.lowOnly),
    );

final paraDetailProvider = FutureProvider.autoDispose
    .family<ParaDetail, String>(
      (ref, id) => ref.watch(ordersRepositoryProvider).para(id),
    );
