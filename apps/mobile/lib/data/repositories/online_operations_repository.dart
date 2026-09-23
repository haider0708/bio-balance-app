import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

import '../../domain/models/models.dart';
import '../services/api/generated/models.dart';
import '../services/api/session_transport.dart';
import 'offline_repository.dart';
import 'repository_context.dart';

/// Connected commands retain their original identity through uncertain responses.
class OnlineOperationsRepository {
  final RepositoryContext context;
  final OfflineRepository local;
  final UserAccount user;
  OnlineOperationsRepository(this.context, this.local, this.user);
  final _inflight = <String, Future<void>>{};
  Future<void> submit(Store store, Json command, {int? expectedVersion}) {
    final target =
        command['deliveryId'] ??
        command['rewardId'] ??
        command['claimId'] ??
        (command['type'] == 'order.create' ? 'new' : command['orderId']) ??
        'new';
    final key = 'online:${command['type']}:$target';
    final scope = '${store.organizationId}:${store.id}:$key';
    return _inflight.putIfAbsent(
      scope,
      () => _submit(store, command, key, expectedVersion).whenComplete(() {
        _inflight.remove(scope);
      }),
    );
  }

  Future<void> _submit(
    Store store,
    Json command,
    String key,
    int? expectedVersion,
  ) async {
    final prior = await local.draft(user.id, store.id, key);
    final operation =
        prior?['operation'] as Json? ??
        <String, dynamic>{
          'operationId': const Uuid().v4(),
          'organizationId': store.organizationId,
          'storeId': store.id,
          'payloadVersion': 2,
          'expectedVersion': ?expectedVersion,
          'command': command,
        };
    final changed = !const DeepCollectionEquality().equals(
      operation['command'],
      command,
    );
    await local.saveDraft(user.id, store.id, key, {'operation': operation});
    final result = (await context.run(() => context.api.pushRaw([operation])))
        .results
        .single;
    if (result is! SyncResultAcceptedDto) {
      final failure = switch (result) {
        SyncResultConflictDto(:final code, :final message) => (
          code: code,
          message: message,
          definitive: true,
        ),
        SyncResultRejectedDto(:final code, :final message) => (
          code: code,
          message: message,
          definitive: true,
        ),
        SyncResultBlockedDto(:final code, :final message) => (
          code: code,
          message: message,
          definitive: false,
        ),
        SyncResultRetryableDto(:final code, :final message) => (
          code: code,
          message: message,
          definitive: false,
        ),
        _ => throw const AppFailure(
          'INVALID_RESULT',
          'Résultat de commande invalide.',
        ),
      };
      final access = switch (failure.code) {
        'SESSION_EXPIRED' => AccessCondition.expired,
        'ACCESS_DISABLED' => AccessCondition.disabled,
        'STORE_ACCESS_REVOKED' => AccessCondition.storeAccessRevoked,
        _ => null,
      };
      if (access != null) {
        context.api.confirmAccessLoss(access, storeId: store.id);
      }
      if (access == null && failure.definitive) {
        await local.saveDraft(user.id, store.id, key, {});
      }
      throw AppFailure(failure.code, failure.message);
    }
    await local.saveDraft(user.id, store.id, key, {});
    if (changed) {
      throw const AppFailure(
        'PREVIOUS_COMMAND_CONFIRMED',
        'La première demande a été confirmée. Vos nouvelles modifications ne sont pas envoyées. Actualisez le suivi avant de les soumettre.',
      );
    }
  }
}
