import '../../../data/repositories/online_operations_repository.dart';
import '../../../data/repositories/repository_context.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/team_repository.dart';
import '../../../data/repositories/reporting_repository.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../data/repositories/rewards_repository.dart';
import '../../../data/repositories/notifications_repository.dart';
import '../../../data/repositories/store_settings_repository.dart';
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
  late final RepositoryContext repositoryContext;
  late final commands = OnlineOperationsRepository(
    repositoryContext,
    repository,
    user,
  );
  late final catalog = CatalogRepository(repositoryContext);
  late final teams = TeamRepository(repositoryContext);
  late final reporting = ReportingRepository(repositoryContext);
  late final sales = SalesRepository(repositoryContext);
  late final rewards = RewardsRepository(repositoryContext);
  late final inbox = NotificationsRepository(repositoryContext);
  late final StoreSettingsRepository stores;

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
    repositoryContext = RepositoryContext(api);
    stores = StoreSettingsRepository(api);
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

  Future<Json> openNotification(String id) async {
    final message = await inbox.get(id);
    final storeId = message['storeId'] as String?;
    if (storeId != null) {
      final accessible = await repository.stores(user, refresh: true);
      final target = accessible.where((s) => s.id == storeId).firstOrNull;
      if (target == null) {
        throw const AppFailure(
          'STORE_ACCESS_REVOKED',
          'Ce magasin n’est plus accessible.',
        );
      }
      await flushDrafts();
      await select(target);
      requireAccess(target);
    }
    await inbox.read(id);
    return message;
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
      e is DioException &&
      (e.response?.statusCode == 401 ||
          (e.response?.data is Map &&
              [
                'STORE_ACCESS_REVOKED',
                'ACCESS_DISABLED',
              ].contains(e.response?.data['code'])));
  bool _networkFailure(Object e) => e is DioException && e.response == null;

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
    await commands.submit(store, command, expectedVersion: expectedVersion);
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
