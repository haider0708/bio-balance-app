import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'stock_models.dart';

class StockRepository {
  StockRepository(this._ref);

  final Ref _ref;

  Future<StockLevels> levels(String locationId) async => StockLevels.fromJson(
    await _ref.read(apiClientProvider).get('/v1/stock/locations/$locationId')
        as Json,
  );

  Future<StockDeclaration> declare({
    required String locationId,
    String? photoId,
    required List<Map<String, Object>> lines,
    String? note,
  }) async => StockDeclaration.fromJson(
    await _ref.read(apiClientProvider).post('/v1/stock/declarations', {
      'locationId': locationId,
      'photoId': ?photoId,
      'lines': lines,
      if (note != null && note.isNotEmpty) 'note': note,
    }) as Json,
  );

  Future<List<StockDeclaration>> declarations({
    String? status,
    String? locationId,
    String? regionId,
  }) async => jsonList(
    await _ref
        .read(apiClientProvider)
        .get(
          '/v1/stock/declarations',
          query: {
            'status': status,
            'locationId': locationId,
            'regionId': regionId,
          },
        ),
  ).map(StockDeclaration.fromJson).toList();

  Future<StockDeclaration> declaration(String id) async =>
      StockDeclaration.fromJson(
        await _ref.read(apiClientProvider).get('/v1/stock/declarations/$id')
            as Json,
      );

  Future<void> approve(
    String id, {
    List<Map<String, Object>>? lines,
    String? note,
  }) => _ref.read(apiClientProvider).post(
    '/v1/stock/declarations/$id/approve',
    {'lines': ?lines, if (note != null && note.isNotEmpty) 'note': note},
  );

  Future<void> reject(String id, String note) => _ref
      .read(apiClientProvider)
      .post('/v1/stock/declarations/$id/reject', {'note': note});
}

final stockRepositoryProvider = Provider<StockRepository>(StockRepository.new);

final stockLevelsProvider = FutureProvider.autoDispose
    .family<StockLevels, String>(
      (ref, id) => ref.watch(stockRepositoryProvider).levels(id),
    );

final declarationProvider = FutureProvider.autoDispose
    .family<StockDeclaration, String>(
      (ref, id) => ref.watch(stockRepositoryProvider).declaration(id),
    );

final declarationsProvider = FutureProvider.autoDispose
    .family<List<StockDeclaration>, String?>(
      (ref, locationId) => ref
          .watch(stockRepositoryProvider)
          .declarations(locationId: locationId),
    );
