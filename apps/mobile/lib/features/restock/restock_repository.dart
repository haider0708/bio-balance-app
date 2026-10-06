import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'restock_models.dart';

class RestockRepository {
  RestockRepository(this._ref);

  final Ref _ref;

  Future<List<RestockOrder>> list({
    String? status,
    bool? active,
    String? regionId,
    String? destId,
  }) async => jsonList(
    await _ref
        .read(apiClientProvider)
        .get(
          '/v1/restocks',
          query: {
            'status': status,
            'active': active == null ? null : '$active',
            'regionId': regionId,
            'destId': destId,
          },
        ),
  ).map(RestockOrder.fromJson).toList();

  Future<RestockOrder> get(String id) async => RestockOrder.fromJson(
    await _ref.read(apiClientProvider).get('/v1/restocks/$id') as Json,
  );

  Future<RestockOrder> create({
    String? destId,
    String? note,
    required List<Map<String, Object>> lines,
  }) async => RestockOrder.fromJson(
    await _ref.read(apiClientProvider).post('/v1/restocks', {
      'destId': ?destId,
      if (note != null && note.isNotEmpty) 'note': note,
      'lines': lines,
    }) as Json,
  );

  Future<void> assign(
    String id, {
    required String depotId,
    List<Map<String, Object>>? lines,
  }) => _ref.read(apiClientProvider).post('/v1/restocks/$id/assign', {
    'depotId': depotId,
    'lines': ?lines,
  });

  Future<void> sendDirect(String id, {List<Map<String, Object>>? lines}) => _ref
      .read(apiClientProvider)
      .post('/v1/restocks/$id/send-direct', {'lines': ?lines});

  Future<void> ship(String id, List<Map<String, Object>> lines) => _ref
      .read(apiClientProvider)
      .post('/v1/restocks/$id/ship', {'lines': lines});

  Future<void> setReceiver(String id, String? userId) => _ref
      .read(apiClientProvider)
      .put('/v1/restocks/$id/receiver', {'userId': userId});

  Future<void> receive(
    String id, {
    required String photoId,
    required List<Map<String, Object>> lines,
    String? note,
  }) => _ref.read(apiClientProvider).post('/v1/restocks/$id/receipt', {
    'photoId': photoId,
    'lines': lines,
    if (note != null && note.isNotEmpty) 'note': note,
  });

  Future<void> approve(
    String id, {
    List<Map<String, Object>>? lines,
    String? note,
  }) => _ref.read(apiClientProvider).post('/v1/restocks/$id/approve', {
    'lines': ?lines,
    if (note != null && note.isNotEmpty) 'note': note,
  });

  Future<void> rejectReceipt(String id, String note) => _ref
      .read(apiClientProvider)
      .post('/v1/restocks/$id/reject-receipt', {'note': note});

  Future<void> cancel(String id, String note) => _ref
      .read(apiClientProvider)
      .post('/v1/restocks/$id/cancel', {'note': note});
}

final restockRepositoryProvider = Provider<RestockRepository>(
  RestockRepository.new,
);

typedef RestockQuery = ({
  bool? active,
  String? status,
  String? regionId,
  String? destId,
});

final restocksProvider = FutureProvider.autoDispose
    .family<List<RestockOrder>, RestockQuery>(
      (ref, q) => ref
          .watch(restockRepositoryProvider)
          .list(
            active: q.active,
            status: q.status,
            regionId: q.regionId,
            destId: q.destId,
          ),
    );

final restockProvider = FutureProvider.autoDispose.family<RestockOrder, String>(
  (ref, id) => ref.watch(restockRepositoryProvider).get(id),
);
