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
  WorkspaceViewModel(this.user, this.repository, this.api);
  void _emit(WorkspaceState value) {
    if (_closed) return;
    state = value;
    notifyListeners();
  }

  Future<void> initialize() async {
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
          accessBlocked: _accessFailure(e),
          clearData: _accessFailure(e),
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
        accessBlocked: false,
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
      if (store.id == state.store?.id) {
        _emit(
          state.copy(
            syncing: false,
            offline: _networkFailure(e),
            accessBlocked: _accessFailure(e),
            clearData: _accessFailure(e),
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
    try {
      final value = await api.request(method, path, body: body, query: query);
      return value;
    } catch (e) {
      throw AppFailure('REQUEST', SessionViewModel.message(e));
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

  Future<void> online(Json command, {int? expectedVersion}) async {
    final store = state.store!;
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
      await repository.saveDraft(user.id, store.id, key, {});
      throw AppFailure(
        row['code'] ?? 'CONFLICT',
        row['message'] ?? 'Opération refusée.',
      );
    }
    await repository.saveDraft(user.id, store.id, key, {});
    await synchronize();
  }

  String productName(String id) =>
      state.data?.products.where((p) => p.id == id).firstOrNull?.name ??
      'Produit';
  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    super.dispose();
  }
}
