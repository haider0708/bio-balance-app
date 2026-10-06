import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'rewards_models.dart';

class RewardsRepository {
  RewardsRepository(this._ref);

  final Ref _ref;

  Future<List<RewardRule>> rules(String when) async => jsonList(
    await _ref
        .read(apiClientProvider)
        .get('/v1/reward-rules', query: {'when': when}),
  ).map(RewardRule.fromJson).toList();

  Future<List<EffectiveReward>> effective(String day) async => jsonList(
    await _ref
        .read(apiClientProvider)
        .get('/v1/reward-rules/effective', query: {'day': day}),
  ).map(EffectiveReward.fromJson).toList();

  Future<void> create(Json body) =>
      _ref.read(apiClientProvider).post('/v1/reward-rules', body);

  Future<void> cancel(String id) =>
      _ref.read(apiClientProvider).delete('/v1/reward-rules/$id');
}

final rewardsRepositoryProvider = Provider<RewardsRepository>(
  RewardsRepository.new,
);

final rewardRulesProvider = FutureProvider.autoDispose
    .family<List<RewardRule>, String>(
      (ref, when) => ref.watch(rewardsRepositoryProvider).rules(when),
    );

final effectiveRewardsProvider = FutureProvider.autoDispose
    .family<List<EffectiveReward>, String>(
      (ref, day) => ref.watch(rewardsRepositoryProvider).effective(day),
    );
