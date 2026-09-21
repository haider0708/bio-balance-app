import '../../../data/services/api/session_transport.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/offline_repository.dart';
import '../../../data/services/api/generated/api_client.dart';
import '../../../domain/models/models.dart';
import '../authentication/session_view_model.dart';

class WorkspaceState {
  final List<Store> stores;
  final Store? store;
  final StoreData? data;
  final bool loading, syncing, offline, accessBlocked;
  final String? error;
  final int pending;
  final DateTime? syncedAt;
  const WorkspaceState({
    this.stores = const [],
    this.store,
    this.data,
    this.loading = false,
    this.syncing = false,
    this.offline = false,
    this.accessBlocked = false,
    this.error,
    this.pending = 0,
    this.syncedAt,
  });
  WorkspaceState copy({
    List<Store>? stores,
    Store? store,
    StoreData? data,
    bool? loading,
    bool? syncing,
    bool? offline,
    bool? accessBlocked,
    String? error,
    int? pending,
    DateTime? syncedAt,
    bool clearData = false,
    bool clearStore = false,
  }) => WorkspaceState(
    stores: stores ?? this.stores,
    store: clearStore ? null : store ?? this.store,
    data: clearData ? null : data ?? this.data,
    loading: loading ?? this.loading,
    syncing: syncing ?? this.syncing,
    offline: offline ?? this.offline,
    accessBlocked: accessBlocked ?? this.accessBlocked,
    error: error,
    pending: pending ?? this.pending,
    syncedAt: syncedAt ?? this.syncedAt,
  );
}

class WorkspaceViewModel extends ChangeNotifier {
  final UserAccount user;
  final OfflineRepository repository;
  final ApiClient api;
  WorkspaceState state = const WorkspaceState(loading: true);
  Timer? _timer;
  int _selection = 0;
  bool _closed = false;
  final _revokedStores = <String>{};
  final _draftGuards = <Future<void> Function()>{};
  late final StreamSubscription<AccessEvent> _accessEvents;
  final int _sessionGeneration;
  VoidCallback? detachSessionGuard;
  int accessRevision = 0;
  bool securingAccess = false;
  WorkspaceViewModel(this.user, this.repository, this.api)
    : _sessionGeneration = api.generation {
    _accessEvents = api.accessEvents.listen((event) {
      if (event.binding.accountId != user.id ||
          event.binding.generation != _sessionGeneration) {
        return;
      }
      if ([
        AccessCondition.expired,
        AccessCondition.disabled,
        AccessCondition.storeAccessRevoked,
      ].contains(event.condition)) {
        unawaited(denyAccess(event.storeId ?? state.store?.id));
      }
    });
  }
  VoidCallback registerDraft(Future<void> Function() save) {
    _draftGuards.add(save);
    return () => _draftGuards.remove(save);
  }

  Future<void> flushDrafts() =>
      Future.wait(_draftGuards.toList().map((save) => save()));
  void requireAccess(Store store, [String? permission]) {
    if (_closed ||
        api.generation != _sessionGeneration ||
        api.accountId != user.id ||
        api.accessBlocked ||
        _revokedStores.contains(store.id) ||
        (state.store?.id == store.id && state.accessBlocked)) {
      throw const AppFailure(
        'ACCESS_BLOCKED',
        'Votre accès doit être vérifié. Le brouillon est conservé.',
      );
    }
    if (permission != null &&
        !user.admin &&
        !store.canManage &&
        !store.permissions.contains(permission)) {
      throw const AppFailure(
        'FORBIDDEN',
        'Cette action nécessite une autorisation de votre responsable.',
      );
    }
  }

  Future<void> denyAccess(String? storeId) async {
    if (_closed) return;
    if (storeId != null) _revokedStores.add(storeId);
    final current = storeId == null || state.store?.id == storeId;
    if (current) {
      securingAccess = true;
      _emit(
        state.copy(
          accessBlocked: true,
          loading: false,
          error:
              'Votre accès doit être vérifié. Les brouillons sont conservés.',
        ),
      );
    }
    try {
      await repository.saveDraft(user.id, '', 'access', {
        'revokedStores': _revokedStores.toList(),
      });
      await flushDrafts();
      if (current && !_closed) {
        accessRevision++;
        securingAccess = false;
        _emit(state.copy(accessBlocked: true, loading: false));
      }
    } catch (e) {
      if (current) {
        _emit(
          state.copy(
            accessBlocked: true,
            error: 'Impossible de conserver le brouillon. Libérez de l’espace puis réessayez.',
          ),
        );
      }
    }
  }

  void _emit(WorkspaceState value) {
    if (_closed) return;
    state = value;
    notifyListeners();
  }

  Future<void> initialize() async {
    final access = await repository.draft(user.id, '', 'access');
    _revokedStores.addAll(List<String>.from(access?['revokedStores'] ?? []));
    final cached = await repository.stores(user);
    _emit(state.copy(stores: cached));
    if (cached.isNotEmpty) {
      final saved = await repository.draft(user.id, '', 'selection');
      await select(
        cached.firstWhere(
          (s) => s.id == saved?['storeId'],
          orElse: () => cached.first,
        ),
        refresh: false,
      );
    }
    try {
      final stores = await repository.stores(user, refresh: true);
      final previousStore = state.store;
      if (previousStore != null &&
          !stores.any((s) => s.id == previousStore.id)) {
        await denyAccess(previousStore.id);
      }
      _emit(
        state.copy(
          stores: stores,
          loading: false,
          clearStore: stores.isEmpty,
          clearData: stores.isEmpty,
        ),
      );
      if (stores.isNotEmpty) {
        await select(
          stores.firstWhere(
            (s) => s.id == state.store?.id,
            orElse: () => stores.first,
          ),
        );
      }
    } catch (e) {
      _emit(
        state.copy(
          loading: false,
          offline: _networkFailure(e),
          accessBlocked:
              state.accessBlocked || _accessFailure(e) || api.accessBlocked,

          error: SessionViewModel.message(e),
        ),
      );
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!state.syncing && state.store != null) {
        unawaited(synchronize(silent: true));
      }
    });
  }

  Future<void> select(Store store, {bool refresh = true}) async {
    final selection = ++_selection;
    _emit(
      state.copy(
        store: store,
        clearData: true,
        loading: true,
        accessBlocked: _revokedStores.contains(store.id) || api.accessBlocked,
      ),
    );
    await repository.saveDraft(user.id, '', 'selection', {'storeId': store.id});
    final data = await repository.load(user, store);
    if (selection != _selection) return;
    _emit(
      state.copy(
        data: data,
        loading: false,
        pending: await repository.pendingCount(user.id),
      ),
    );
    if (refresh) await synchronize();
  }

  Future<void> reloadLocal() async {
    final store = state.store;
    if (store == null || state.accessBlocked) return;
    final data = await repository.load(user, store);
    if (store.id != state.store?.id) return;
    final permissions = List<String>.from(
      data?.raw['permissions'] ?? store.permissions,
    );
    if (store.permissions.any((p) => !permissions.contains(p))) {
      await flushDrafts();
      accessRevision++;
    }
    _emit(
      state.copy(
        data: data,
        store: data == null
            ? store
            : Store.fromJson({
                ...store.toJson(),
                ...Map<String, dynamic>.from(data.raw['store'] ?? {}),
                'permissions': data.raw['permissions'] ?? store.permissions,
              }),
        pending: await repository.pendingCount(user.id),
      ),
    );
  }

  Future<void> synchronize({bool silent = false}) async {
    final store = state.store;
    if (store == null || state.syncing) return;
    _emit(state.copy(syncing: true));
    try {
      await repository.synchronize(user, store);
      if (store.id == state.store?.id) {
        _revokedStores.remove(store.id);
        await repository.saveDraft(user.id, '', 'access', {
          'revokedStores': _revokedStores.toList(),
        });
        _emit(state.copy(accessBlocked: false));
        await reloadLocal();
        _emit(
          state.copy(
            syncing: false,
            offline: false,
            accessBlocked: false,
            syncedAt: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      if (_accessFailure(e)) await denyAccess(store.id);
      if (store.id == state.store?.id) {
        _emit(
          state.copy(
            syncing: false,
            offline: _networkFailure(e),
            accessBlocked:
                state.accessBlocked || _accessFailure(e) || api.accessBlocked,

            error: silent && !_accessFailure(e)
                ? null
                : SessionViewModel.message(e),
          ),
        );
      }
    } finally {
      if (state.syncing) _emit(state.copy(syncing: false));
    }
  }

  bool _accessFailure(Object e) =>
      e is DioException && [401, 403].contains(e.response?.statusCode);
  bool _networkFailure(Object e) => e is DioException && e.response == null;

  Future<dynamic> request(
    String method,
    String path, {
    Json? body,
    Json? query,
  }) async {
    if (_closed || api.generation != _sessionGeneration) {
      throw const AppFailure('ACCOUNT_CHANGED', 'La session a changé.');
    }
    try {
      final value = await api.request(method, path, body: body, query: query);
      return value;
    } catch (e) {
      if (_accessFailure(e)) await denyAccess(state.store?.id);
      rethrow;
    }
  }

  Future<dynamic> storeRequest(String method, String path, {Json? body}) {
    final store = state.store!;
    return request(
      method,
      '/v1/stores/${store.id}/$path',
      body: body,
      query: {'organizationId': store.organizationId},
    );
  }

  Future<void> queue(
    Json command, {
    int? expectedVersion,
    Json effect = const {},
    Store? targetStore,
    String? draftKey,
  }) async {
    final store = targetStore ?? state.store!;
    requireAccess(
      store,
      command['type'] == 'delivery.receive' ? 'receive' : 'manage',
    );
    await repository.enqueue(
      user,
      store,
      {
        'operationId': const Uuid().v4(),
        'organizationId': store.organizationId,
        'storeId': store.id,
        'payloadVersion': 2,
        'expectedVersion': ?expectedVersion,
        'command': command,
      },
      effect,
      draftKey: draftKey,
    );
    await reloadLocal();
    unawaited(synchronize(silent: true));
  }

  Future<void> online(
    Json command, {
    int? expectedVersion,
    Store? targetStore,
  }) async {
    final store = targetStore ?? state.store!;
    requireAccess(store);
    if (api.accountId != user.id) {
      throw const AppFailure('ACCOUNT_CHANGED', 'Veuillez vous reconnecter.');
    }
    final target =
        command['rewardId'] ??
        command['claimId'] ??
        (command['type'] == 'order.create' ? 'new' : command['orderId']) ??
        'new';
    final key = 'online:${command['type']}:$target';
    final prior = await repository.draft(user.id, store.id, key);
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
    await repository.saveDraft(user.id, store.id, key, {
      'operation': operation,
    });
    final result = await api.push([operation]);
    final row = objects(result['results']).single;
    if (row['status'] != 'accepted') {
      final access = switch (row['code']) {
        'SESSION_EXPIRED' => AccessCondition.expired,
        'ACCESS_DISABLED' => AccessCondition.disabled,
        'STORE_ACCESS_REVOKED' => AccessCondition.storeAccessRevoked,
        _ => null,
      };
      if (access != null) api.confirmAccessLoss(access, storeId: store.id);
      if (access == null &&
          (row['status'] == 'rejected' || row['status'] == 'conflict')) {
        await repository.saveDraft(user.id, store.id, key, {});
      }
      throw AppFailure(
        row['code'] ?? 'CONFLICT',
        row['message'] ?? 'Opération refusée.',
      );
    }
    await repository.saveDraft(user.id, store.id, key, {});
    if (state.store?.id == store.id) await synchronize();
  }

  String productName(String id) =>
      state.data?.products.where((p) => p.id == id).firstOrNull?.name ??
      'Produit';
  @override
  void dispose() {
    _closed = true;
    unawaited(_accessEvents.cancel());
    detachSessionGuard?.call();
    _draftGuards.clear();
    _timer?.cancel();
    super.dispose();
  }
}
