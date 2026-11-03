import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'transfer_models.dart';

class TransfersRepository {
  TransfersRepository(this._ref);

  final Ref _ref;

  Future<List<Transfer>> list({TransferStatus? status}) async => jsonList(
    await _ref
        .read(apiClientProvider)
        .get('/v1/transfers', query: {'status': status?.wire}),
  ).map(Transfer.fromJson).toList();

  Future<Transfer> get(String id) async => Transfer.fromJson(
    await _ref.read(apiClientProvider).get('/v1/transfers/$id') as Json,
  );

  Future<Partners> partners({String? pdvId}) async => Partners.fromJson(
    await _ref
            .read(apiClientProvider)
            .get('/v1/transfers/partners', query: {'pdvId': pdvId})
        as Json,
  );

  Future<Transfer> create(Json body) async => Transfer.fromJson(
    await _ref.read(apiClientProvider).post('/v1/transfers', body) as Json,
  );

  Future<Transfer> edit(String id, List<Map<String, Object>> lines) async =>
      Transfer.fromJson(
        await _ref.read(apiClientProvider).post('/v1/transfers/$id/edit', {
          'lines': lines,
        }) as Json,
      );

  Future<Transfer> cancel(String id) async => Transfer.fromJson(
    await _ref.read(apiClientProvider).post('/v1/transfers/$id/cancel') as Json,
  );

  Future<Transfer> approve(
    String id, {
    List<Map<String, Object>>? lines,
    String? note,
  }) async => Transfer.fromJson(
    await _ref.read(apiClientProvider).post('/v1/transfers/$id/approve', {
      'lines': ?lines,
      if (note != null && note.isNotEmpty) 'note': note,
    }) as Json,
  );

  Future<Transfer> reject(String id, String note) async => Transfer.fromJson(
    await _ref.read(apiClientProvider).post('/v1/transfers/$id/reject', {
      'note': note,
    }) as Json,
  );
}

final transfersRepositoryProvider = Provider<TransfersRepository>(
  TransfersRepository.new,
);

final transfersProvider = FutureProvider.autoDispose
    .family<List<Transfer>, TransferStatus?>(
      (ref, status) =>
          ref.watch(transfersRepositoryProvider).list(status: status),
    );

final transferProvider = FutureProvider.autoDispose.family<Transfer, String>(
  (ref, id) => ref.watch(transfersRepositoryProvider).get(id),
);

/// The paras of the same group as the given para (null: the team member's own).
final transferPartnersProvider = FutureProvider.autoDispose
    .family<Partners, String?>(
      (ref, pdvId) =>
          ref.watch(transfersRepositoryProvider).partners(pdvId: pdvId),
    );
