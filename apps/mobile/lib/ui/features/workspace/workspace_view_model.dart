import '../../../data/repositories/online_operations_repository.dart';
import '../../../data/repositories/repository_context.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/photo_repository.dart';
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
import '../../../domain/synchronization/sync_summary.dart';
import '../authentication/session_view_model.dart';

class WorkspaceState {
  final List<Store> stores;
  final Store? store;
  final StoreData? data;
  final bool loading, syncing, offline, accessBlocked;
  final String? error;
  final int pending;
  final DateTime? syncedAt;
  final SyncSummary syncSummary;
  final String? syncError;
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
    this.syncSummary = const SyncSummary(),
    this.syncError,
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
    SyncSummary? syncSummary,
    String? syncError,
    bool clearSyncError = false,
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
    syncedAt: clearStore || clearData ? null : syncedAt ?? this.syncedAt,
    syncSummary: syncSummary ?? this.syncSummary,
    syncError: clearSyncError ? null : syncError ?? this.syncError,
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
  late final photos = PhotoRepository(repositoryContext, repository, user.id);
  late final teams = TeamRepository(repositoryContext);
  late final reporting = ReportingRepository(repositoryContext);
  late final sales = SalesRepository(repositoryContext);
  late final rewards = RewardsRepository(repositoryContext);
  late final inbox = NotificationsRepository(
    repositoryContext,
    local: repository,
    accountId: user.id,
  );
  late final StoreSettingsRepository stores;

  final UserAccount user;
  final OfflineRepository repository;
  final ApiClient api;
  WorkspaceState state = const WorkspaceState(loading: true);
  Timer? _timer;
  Future<void>? _synchronization;
  int syncRevision = 0, _syncStoreOffset = 0;
  StreamSubscription<SyncSummary>? _outboxChanges;
  int _selection = 0;
  bool _closed = false, _foreground = true;
  final _revokedStores = <String>{};
  bool _confirmedDirectory = false;
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

  /// Begin observing durable work when the workspace is used, not during
  /// construction. Screens and foreground recovery share one subscription.
  void observeSynchronization() {
    if (_closed || _outboxChanges != null) return;
    _outboxChanges = repository
        .watchSyncSummary(user.id)
        .listen(
          (summary) {
            if (_closed ||
                api.generation != _sessionGeneration ||
                api.accountId != user.id) {
              return;
            }
            syncRevision++;
            _emit(
              state.copy(
                pending: summary.total,
                syncSummary: summary,
                error: state.error,
              ),
            );
          },
          onError: (Object error) {
            _emit(
              state.copy(
                syncError: 'Impossible de lire les opérations enregistrées. Libérez de l’espace puis réessayez.',
              ),
            );
          },
        );
  }

  VoidCallback registerDraft(Future<void> Function() save) {
    _draftGuards.add(save);
    return () => _draftGuards.remove(save);
  }

  Future<void> flushDrafts() =>
      Future.wait(_draftGuards.toList().map((save) => save()));
  Future<void> closeProtectedRoutes() async {
    await flushDrafts();
    if (_closed) return;
    accessRevision++;
    _emit(state.copy());
  }

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

  Future<void> initialize({bool autoSelect = true}) async {
    observeSynchronization();
    _emit(state.copy(loading: true));
    try {
      final access = await repository.draft(user.id, '', 'access');
      _revokedStores.addAll(List<String>.from(access?['revokedStores'] ?? []));
      final cached = await repository.stores(user);
      _emit(state.copy(stores: cached));
      if (autoSelect && cached.isNotEmpty) {
        final saved = await repository.draft(user.id, '', 'selection');
        await select(
          cached.firstWhere(
            (s) => s.id == saved?['storeId'],
            orElse: () => cached.first,
          ),
          refresh: false,
        );
      }
      final stores = await repository.stores(user, refresh: true);
      repositoryContext.check();
      if (!_confirmedDirectory && !state.accessBlocked) {
        _revokedStores.removeWhere((id) => stores.any((s) => s.id == id));
        await repository.saveDraft(user.id, '', 'access', {
          'revokedStores': _revokedStores.toList(),
        });
        _confirmedDirectory = true;
      }
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
      if (autoSelect && stores.isNotEmpty) {
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
    _scheduleSync();
    unawaited(synchronize(silent: true));
  }

  void setForeground(bool value) {
    if (_closed || _foreground == value) return;
    _foreground = value;
    _timer?.cancel();
    if (value) {
      unawaited(synchronize(silent: true));
      _scheduleSync();
    }
  }

  void _scheduleSync() {
    _timer?.cancel();
    if (_closed || !_foreground || api.accessBlocked) return;
    var delay = const Duration(seconds: 30);
    final retryAt = state.syncSummary.nextAttemptAt;
    if (state.syncSummary.waiting > 0 &&
        !state.offline &&
        state.syncError == null) {
      delay = const Duration(seconds: 2);
    } else if (retryAt != null) {
      delay = Duration(
        milliseconds: retryAt
            .difference(repository.now())
            .inMilliseconds
            .clamp(1000, 30000),
      );
    }
    _timer = Timer(delay, () async {
      if (_closed || !_foreground) return;
      await synchronize(silent: true);
      _scheduleSync();
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
    try {
      await repository.saveDraft(user.id, '', 'selection', {
        'storeId': store.id,
      });
      final data = await repository.load(user, store);
      final pending = await repository.pendingCount(user.id);
      if (selection != _selection) return;
      _emit(state.copy(data: data, loading: false, pending: pending));
      if (refresh) {
        // A pass already running belongs to its captured stores. Once it
        // finishes, load the newly selected workspace without waiting 30 s.
        final inFlight = _synchronization;
        if (inFlight != null) await inFlight;
        if (selection == _selection) await synchronize();
      }
    } catch (e) {
      if (selection != _selection) return;
      _emit(state.copy(loading: false, error: SessionViewModel.message(e)));
    }
  }

  void releaseStore() {
    _selection++;
    _emit(
      state.copy(
        clearStore: true,
        clearData: true,
        loading: false,
        accessBlocked: api.accessBlocked,
      ),
    );
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
      // Reading the inbox must not silently replace the operational workspace.
      // Navigation is owned by the scope coordinator, not by a notification read.
      message['storeName'] = target.name;
    }
    await inbox.read(id);
    return message;
  }

  Future<void> reloadLocal() async {
    final store = state.store;
    final selection = _selection;
    if (store == null || state.accessBlocked) return;
    final data = await repository.load(user, store);
    final pending = await repository.pendingCount(user.id);
    if (selection != _selection || state.accessBlocked || _closed) return;
    final permissions = List<String>.from(
      data?.raw['permissions'] ?? store.permissions,
    );
    if (store.permissions.any((p) => !permissions.contains(p))) {
      await flushDrafts();
      if (selection != _selection || state.accessBlocked || _closed) return;
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
        pending: pending,
      ),
    );
  }

  Future<void> synchronize({bool silent = false}) {
    observeSynchronization();
    final existing = _synchronization;
    if (existing != null) return existing;
    if (_closed ||
        !_foreground ||
        api.generation != _sessionGeneration ||
        api.accountId != user.id ||
        api.accessBlocked) {
      return Future.value();
    }
    late final Future<void> work;
    work = _synchronizeAccount(silent: silent).whenComplete(() {
      if (identical(_synchronization, work)) _synchronization = null;
      _scheduleSync();
    });
    _synchronization = work;
    return work;
  }

  Future<void> _synchronizeAccount({required bool silent}) async {
    _emit(state.copy(syncing: true, clearSyncError: true));
    try {
      repositoryContext.check();
      final queued = await repository.accountOperations(user.id);
      repositoryContext.check();
      final pendingStores = queued.map((r) => r.storeId).toSet().toList();
      var directory = state.stores;
      if (pendingStores.any((id) => !directory.any((s) => s.id == id))) {
        directory = await repository.stores(user, refresh: true);
        repositoryContext.check();
        _emit(state.copy(stores: directory));
      }
      final targets = <String, Store>{};
      final active = state.store;
      if (active != null) targets[active.id] = active;
      // Bound each pass, rotating pending stores so an unavailable or busy
      // workspace cannot starve another store. No navigation state is changed.
      for (var i = 0; i < pendingStores.length && targets.length < 8; i++) {
        final id = pendingStores[(i + _syncStoreOffset) % pendingStores.length];
        final target = directory.where((s) => s.id == id).firstOrNull;
        if (target != null) targets[id] = target;
      }
      if (pendingStores.isNotEmpty) {
        _syncStoreOffset = (_syncStoreOffset + 7) % pendingStores.length;
      }
      if (pendingStores.any((id) => !directory.any((s) => s.id == id))) {
        _emit(
          state.copy(
            syncError: 'Une saisie appartient à un magasin inaccessible. Elle reste conservée : consultez la synchronisation.',
          ),
        );
      }
      for (final store in targets.values) {
        if (_closed || !_foreground || api.accessBlocked) break;
        repositoryContext.check();
        try {
          await repository.synchronize(user, store);
          repositoryContext.check();
          _emit(state.copy(offline: false));
          _revokedStores.remove(store.id);
          await repository.saveDraft(user.id, '', 'access', {
            'revokedStores': _revokedStores.toList(),
          });
          if (store.id == state.store?.id) {
            final selection = _selection;
            _emit(state.copy(accessBlocked: false));
            await reloadLocal();
            if (selection == _selection) {
              _emit(state.copy(offline: false, syncedAt: repository.now()));
            }
          }
        } catch (e) {
          repositoryContext.check();
          if (_accessFailure(e)) await denyAccess(store.id);
          _emit(
            state.copy(
              offline: _networkFailure(e),
              syncError: '${store.name} : ${SessionViewModel.message(e)}',
              error: silent ? state.error : SessionViewModel.message(e),
            ),
          );
          if (api.accessBlocked || _networkFailure(e)) break;
        }
      }
    } catch (e) {
      if (!_closed &&
          api.generation == _sessionGeneration &&
          api.accountId == user.id) {
        _emit(
          state.copy(
            offline: _networkFailure(e),
            syncError: SessionViewModel.message(e),
          ),
        );
      }
    } finally {
      syncRevision++;
      if (!_closed &&
          api.generation == _sessionGeneration &&
          api.accountId == user.id) {
        _emit(state.copy(syncing: false, error: state.error));
      }
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
    requireAccess(store, 'manage');
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
    await afterLocalCommit();
  }

  /// The durable operation already exists. A failed readback must never invite
  /// the caller to submit it again with another operation identifier.
  Future<void> afterLocalCommit() async {
    try {
      await reloadLocal();
    } catch (_) {
      _emit(
        state.copy(
          loading: false,
          error: 'Opération enregistrée sur ce téléphone. L’affichage n’a pas pu être actualisé. Réessayez la synchronisation.',
        ),
      );
      return;
    }
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
      state.data?.productsById[id]?.name ?? 'Produit';
  @override
  void dispose() {
    photos.dispose();
    _closed = true;
    unawaited(_accessEvents.cancel());
    unawaited(_outboxChanges?.cancel());
    detachSessionGuard?.call();
    _draftGuards.clear();
    _timer?.cancel();
    super.dispose();
  }
}
