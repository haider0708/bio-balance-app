import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'return_models.dart';

class ReturnsRepository {
  ReturnsRepository(this._ref);

  final Ref _ref;

  Future<List<StockReturn>> list() async =>
      jsonList(await _ref.read(apiClientProvider).get('/v1/returns'))
          .map(StockReturn.fromJson)
          .toList();

  Future<StockReturn> get(String id) async => StockReturn.fromJson(
    await _ref.read(apiClientProvider).get('/v1/returns/$id') as Json,
  );

  Future<StockReturn> create(Json body) async => StockReturn.fromJson(
    await _ref.read(apiClientProvider).post('/v1/returns', body) as Json,
  );

  Future<StockReturn> edit(String id, List<Map<String, Object>> lines) async =>
      StockReturn.fromJson(
        await _ref.read(apiClientProvider).post('/v1/returns/$id/edit', {
          'lines': lines,
        }) as Json,
      );

  Future<StockReturn> cancel(String id) async => StockReturn.fromJson(
    await _ref.read(apiClientProvider).post('/v1/returns/$id/cancel') as Json,
  );

  Future<StockReturn> approve(
    String id, {
    List<Map<String, Object>>? lines,
    String? toPdvId,
  }) async => StockReturn.fromJson(
    await _ref.read(apiClientProvider).post('/v1/returns/$id/approve', {
      'lines': ?lines,
      'toPdvId': ?toPdvId,
    }) as Json,
  );

  Future<StockReturn> reject(String id, String note) async =>
      StockReturn.fromJson(
        await _ref.read(apiClientProvider).post('/v1/returns/$id/reject', {
          'note': note,
        }) as Json,
      );
}

final returnsRepositoryProvider = Provider<ReturnsRepository>(
  ReturnsRepository.new,
);

final returnsProvider = FutureProvider.autoDispose<List<StockReturn>>(
  (ref) => ref.watch(returnsRepositoryProvider).list(),
);

final returnProvider = FutureProvider.autoDispose.family<StockReturn, String>(
  (ref, id) => ref.watch(returnsRepositoryProvider).get(id),
);
