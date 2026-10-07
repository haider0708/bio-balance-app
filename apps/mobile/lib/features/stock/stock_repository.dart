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
    List<String> photoIds = const [],
    required List<Map<String, Object>> lines,
    String? note,
  }) async => StockDeclaration.fromJson(
    await _ref.read(apiClientProvider).post('/v1/stock/declarations', {
      'locationId': locationId,
      if (photoIds.isNotEmpty) 'photoIds': photoIds,
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

  /// The responsable checks a grossiste's count: pass it to the admin or send it back.
  Future<void> review(String id, {required bool approve, String? note}) =>
      _ref.read(apiClientProvider).post('/v1/stock/declarations/$id/review', {
        'action': approve ? 'approve' : 'reject',
        'note': ?note,
      });

  /// The admin sets quantities directly, with the reason.
  Future<void> adjust({
    required String locationId,
    required String reason,
    required List<Map<String, Object>> lines,
  }) => _ref.read(apiClientProvider).post('/v1/stock/adjust', {
    'locationId': locationId,
    'reason': reason,
    'lines': lines,
  });

  Future<void> requestRecount(String locationId, String reason) => _ref
      .read(apiClientProvider)
      .post('/v1/stock/recounts', {'locationId': locationId, 'reason': reason});

  Future<List<RecountRequest>> recounts({String? locationId}) async => jsonList(
    await _ref
        .read(apiClientProvider)
        .get('/v1/stock/recounts', query: {'locationId': locationId}),
  ).map(RecountRequest.fromJson).toList();

  Future<void> decideRecount(
    String id, {
    required bool approve,
    String? note,
  }) => _ref.read(apiClientProvider).post(
    '/v1/stock/recounts/$id/${approve ? 'approve' : 'reject'}',
    {'note': ?note},
  );
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

final recountsProvider = FutureProvider.autoDispose
    .family<List<RecountRequest>, String>(
      (ref, locationId) =>
          ref.watch(stockRepositoryProvider).recounts(locationId: locationId),
    );

/// Grossiste counts waiting for the responsable's check.
final countsToReviewProvider =
    FutureProvider.autoDispose<List<StockDeclaration>>(
      (ref) =>
          ref.watch(stockRepositoryProvider).declarations(status: 'REVIEW'),
    );
