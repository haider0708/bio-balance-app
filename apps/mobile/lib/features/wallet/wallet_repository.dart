import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'wallet_models.dart';

class WalletPage {
  const WalletPage(this.entries, this.nextCursor);

  final List<WalletEntry> entries;
  final String? nextCursor;
}

class WalletRepository {
  WalletRepository(this._ref);

  final Ref _ref;

  Future<WalletSummary> summary() async =>
      WalletSummary.fromJson(await _ref.read(apiClientProvider).get('/v1/wallet') as Json);

  Future<WalletPage> entries({String? cursor}) async {
    final data = await _ref.read(apiClientProvider).get('/v1/wallet/entries', query: {'cursor': cursor, 'limit': 30}) as Json;
    return WalletPage(data.list('items').map(WalletEntry.fromJson).toList(), data.strOrNull('nextCursor'));
  }

  Future<List<Payout>> payouts({String? status, String? regionId}) async {
    final data = await _ref.read(apiClientProvider).get('/v1/payouts', query: {'status': status, 'regionId': regionId});
    return jsonList(data).map(Payout.fromJson).toList();
  }

  Future<void> request(int amountMillimes) =>
      _ref.read(apiClientProvider).post('/v1/payouts', {'amountMillimes': amountMillimes});

  Future<void> cancel(String id) => _ref.read(apiClientProvider).post('/v1/payouts/$id/cancel');

  Future<void> approve(String id, {String? reference, DateTime? paidAt, String? note}) =>
      _ref.read(apiClientProvider).post('/v1/payouts/$id/approve', {
        if (reference != null && reference.isNotEmpty) 'reference': reference,
        if (paidAt != null) 'paidAt': paidAt.toUtc().toIso8601String(),
        if (note != null && note.isNotEmpty) 'note': note,
      });

  Future<void> reject(String id, String note) =>
      _ref.read(apiClientProvider).post('/v1/payouts/$id/reject', {'note': note});

  Future<List<WalletOverview>> overview({String? regionId}) async {
    final data = await _ref.read(apiClientProvider).get('/v1/wallets', query: {'regionId': regionId});
    return jsonList(data).map(WalletOverview.fromJson).toList();
  }
}

final walletRepositoryProvider = Provider<WalletRepository>(WalletRepository.new);

final walletSummaryProvider = FutureProvider.autoDispose<WalletSummary>((ref) => ref.watch(walletRepositoryProvider).summary());

final myPayoutsProvider = FutureProvider.autoDispose<List<Payout>>((ref) => ref.watch(walletRepositoryProvider).payouts());
