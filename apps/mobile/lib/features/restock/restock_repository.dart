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

  /// A request for goods (responsable), or, for the admin restocking a grossiste, the delivery
  /// itself with its photos: it is added to the stock at once.
  Future<RestockOrder> create({
    required String destId,
    String? note,
    required List<Map<String, Object>> lines,
    List<String> photoIds = const [],
    String? supplierId,
  }) async => RestockOrder.fromJson(
    await _ref.read(apiClientProvider).post('/v1/restocks', {
      'destId': destId,
      'supplierId': ?supplierId,
      if (note != null && note.isNotEmpty) 'note': note,
      'lines': lines,
      if (photoIds.isNotEmpty) 'photoIds': photoIds,
    }) as Json,
  );

  /// The grossistes a responsable allowed to choose may suggest, and whether each covers the lines.
  Future<List<SupplierCoverage>> coverage(
    List<Map<String, Object>> lines,
  ) async => [
    for (final j in jsonList(
      await _ref.read(apiClientProvider).post('/v1/restocks/suppliers', {
        'lines': lines,
      }),
    ))
      SupplierCoverage.fromJson(j),
  ];

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

  /// The delivery paper (photos or documents) and a note. Quantities only when the admin receives
  /// (they approve at once); anyone else leaves them to the admin's approval.
  Future<void> receive(
    String id, {
    required List<String> photoIds,
    List<Map<String, Object>>? lines,
    String? note,
  }) => _ref.read(apiClientProvider).post('/v1/restocks/$id/receipt', {
    'photoIds': photoIds,
    'lines': ?lines,
    if (note != null && note.isNotEmpty) 'note': note,
  });

  /// Every active grossiste with what it holds of this order's products.
  Future<List<SupplierOption>> suppliers(String id) async => [
    for (final j in jsonList(
      await _ref.read(apiClientProvider).get('/v1/restocks/$id/suppliers'),
    ))
      SupplierOption.fromJson(j),
  ];

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
