import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:dio/dio.dart';

import '../../domain/models/models.dart';
import '../../domain/repositories/workspace_repository.dart';
import '../services/api/generated/api_client.dart';
import '../services/local_database/database.dart';

class OfflineRepository implements WorkspaceRepository {
  final AppDatabase db;
  final ApiClient api;
  bool _syncing = false;
  OfflineRepository(this.db, this.api);
  Future<void> _cache(
    String account,
    String store,
    String resource,
    String id,
    Json value,
  ) => db
      .into(db.cacheEntries)
      .insertOnConflictUpdate(
        CacheEntriesCompanion.insert(
          accountId: account,
          storeId: store,
          resource: resource,
          entityId: id,
          payload: jsonEncode(value),
        ),
      );
  Future<List<CacheEntry>> _entries(
    String account,
    String store,
    String resource,
  ) =>
      (db.select(db.cacheEntries)..where(
            (t) =>
                t.accountId.equals(account) &
                t.storeId.equals(store) &
                t.resource.equals(resource),
          ))
          .get();
  @override
  Future<List<Store>> stores(UserAccount user, {bool refresh = false}) async {
    if (refresh) {
      _sameAccount(user);
      final values = objects(await api.request('GET', '/v1/stores'));
      _sameAccount(user);
      await db.transaction(() async {
        await (db.delete(db.cacheEntries)..where(
              (t) => t.accountId.equals(user.id) & t.resource.equals('stores'),
            ))
            .go();
        for (final v in values) {
          await _cache(user.id, '', 'stores', v['id'], v);
        }
      });
    }
    return (await _entries(
        user.id,
        '',
        'stores',
      )).map((e) => Store.fromJson(jsonDecode(e.payload))).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<StoreData?> load(UserAccount user, Store store) async {
    final entries =
        await (db.select(db.cacheEntries)..where(
              (t) => t.accountId.equals(user.id) & t.storeId.equals(store.id),
            ))
            .get();
    if (entries.isEmpty) return null;
    final raw = <String, dynamic>{};
    for (final entry in entries) {
      final value = jsonDecode(entry.payload);
      if (entry.resource == 'meta') {
        raw.addAll(Map<String, dynamic>.from(value));
      } else {
        (raw[entry.resource] ??= <dynamic>[]).add(value);
      }
    }
    final pending = await operations(user.id, store.id);
    final sales = objects(raw['sales']);
    final lots = objects(raw['lots']);
    for (final row in pending) {
      final effect = Map<String, dynamic>.from(jsonDecode(row.effect));
      if (effect['sale'] != null) {
        final sale = Map<String, dynamic>.from(effect['sale']);
        sales.removeWhere((s) => s['id'] == sale['id']);
        sales.insert(0, {
          ...sale,
          'syncStatus': row.status,
          'syncError': row.error,
        });
      }
      for (final patch in objects(effect['lots'])) {
        final index = lots.indexWhere((l) => l['id'] == patch['id']);
        if (index >= 0) {
          lots[index] = {
            ...lots[index],
            'sellable':
                integer(lots[index]['sellable']) + integer(patch['delta']),
            'version': integer(patch['version'] ?? lots[index]['version']),
          };
        } else if (patch['productId'] != null) {
          lots.add({
            ...patch,
            'sellable': integer(patch['delta']),
            'damaged': 0,
            'version': 1,
          });
        }
      }
    }
    raw['sales'] = sales;
    raw['lots'] = lots;
    raw['queuedCount'] = pending.length;
    return StoreData(raw);
  }

  Future<List<OutboxRow>> operations(
    String account,
    String store, {
    bool includeResolved = false,
  }) =>
      (db.select(db.outboxRows)
            ..where(
              (t) =>
                  t.accountId.equals(account) &
                  t.storeId.equals(store) &
                  (includeResolved
                      ? const Constant(true)
                      : t.status.equals('resolved').not()),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
          .get();
  @override
  Future<void> refresh(UserAccount user, Store store) async {
    _sameAccount(user);
    final acknowledged = (await operations(
      user.id,
      store.id,
    )).where((o) => o.status == 'accepted').map((o) => o.operationId).toList();
    final metaRows = await _entries(user.id, store.id, 'meta');
    final prior = metaRows.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(metaRows.single.payload));
    final snapshot = Map<String, dynamic>.from(
      await api.request(
        'GET',
        '/v1/stores/${store.id}/snapshot',
        query: {
          'organizationId': store.organizationId,
          if (prior['syncProtocol'] == 2) 'after': prior['cursor'],
          if (prior['syncProtocol'] == 2)
            'catalogRevision': prior['catalogRevision'],
        },
      ),
    );
    _sameAccount(user);
    final merge = List<String>.from(snapshot.remove('mergeResources') ?? []);
    final pagination = Map<String, dynamic>.from(
      snapshot.remove('pagination') ?? {},
    );
    for (final resource in ['lots', 'products', 'config']) {
      var cursor = pagination[resource] as String?;
      while (cursor != null) {
        final page = objects(
          await api.request(
            'GET',
            '/v1/stores/${store.id}/collections/$resource',
            query: {'organizationId': store.organizationId, 'after': cursor},
          ),
        );
        _sameAccount(user);
        (snapshot[resource] as List).addAll(page);
        cursor = page.length == 200 ? page.last['id'] : null;
      }
    }
    _sameAccount(user);
    await db.transaction(() async {
      await (db.delete(db.cacheEntries)..where(
            (t) =>
                t.accountId.equals(user.id) &
                t.storeId.equals(store.id) &
                t.resource.isNotIn(merge),
          ))
          .go();
      final meta = <String, dynamic>{};
      for (final entry in snapshot.entries) {
        if (entry.value is List) {
          for (final item in objects(entry.value)) {
            await _cache(
              user.id,
              store.id,
              entry.key,
              '${item['id'] ?? item['productId']}',
              item,
            );
          }
        } else {
          meta[entry.key] = entry.value;
        }
      }
      await _cache(user.id, store.id, 'meta', 'meta', meta);
      await (db.delete(db.outboxRows)..where(
            (t) =>
                t.accountId.equals(user.id) &
                t.storeId.equals(store.id) &
                t.operationId.isIn(acknowledged),
          ))
          .go();
    });
  }

  @override
  Future<void> enqueue(
    UserAccount user,
    Store store,
    Json operation,
    Json effect, {
    String? draftKey,
    List<String> supersedes = const [],
  }) async {
    if (operation['storeId'] != store.id ||
        operation['organizationId'] != store.organizationId) {
      throw const AppFailure(
        'STORE_MISMATCH',
        'Le magasin de cette opération a changé.',
      );
    }
    await db.transaction(() async {
      if (supersedes.isNotEmpty) {
        await _resolve(
          user.id,
          store.id,
          supersedes,
          'Remplacée par une saisie vérifiée : ${operation['operationId']}',
        );
      }
      await db
          .into(db.outboxRows)
          .insert(
            OutboxRowsCompanion.insert(
              operationId: operation['operationId'],
              accountId: user.id,
              storeId: store.id,
              payload: jsonEncode(operation),
              effect: jsonEncode(effect),
            ),
          );
      if (draftKey != null) {
        await (db.delete(db.draftRows)..where(
              (t) =>
                  t.accountId.equals(user.id) &
                  t.storeId.equals(store.id) &
                  t.key.equals(draftKey),
            ))
            .go();
      }
    });
  }

  @override
  Future<int> pendingCount(String accountId) async {
    final result = await db
        .customSelect(
          "SELECT COUNT(*) AS n FROM outbox_rows WHERE account_id = ? AND status <> 'resolved'",
          variables: [Variable(accountId)],
        )
        .getSingle();
    return result.read<int>('n');
  }

  /// Keep the original payload and error for diagnostics; remove only its
  /// provisional effect. A pending operation with an uncertain response cannot
  /// be discarded until the server has explicitly rejected it.
  Future<void> resolve(
    UserAccount user,
    Store store,
    List<String> ids,
    String reason,
  ) async {
    _sameAccount(user);
    await refresh(user, store);
    await db.transaction(() => _resolve(user.id, store.id, ids, reason));
  }

  Future<void> _resolve(
    String account,
    String store,
    List<String> ids,
    String reason,
  ) async {
    final rows = await operations(account, store);
    final selected = rows.where((r) => ids.contains(r.operationId)).toList();
    if (selected.length != ids.length ||
        selected.isEmpty ||
        !['conflict', 'rejected'].contains(selected.first.status) ||
        selected.any((r) => r.status == 'accepted')) {
      throw const AppFailure(
        'UNCONFIRMED_OPERATION',
        'Synchronisez cette opération avant de la résoudre.',
      );
    }
    final first = Map<String, dynamic>.from(
      jsonDecode(selected.first.payload)['command'],
    );
    String target(Json command) =>
        '${command['saleId'] ?? command['deliveryId'] ?? command['lotId'] ?? command['orderId'] ?? command['claimId'] ?? ''}';
    if (selected
        .skip(1)
        .any(
          (r) =>
              target(
                Map<String, dynamic>.from(jsonDecode(r.payload)['command']),
              ) !=
              target(first),
        )) {
      throw const AppFailure(
        'UNRELATED_OPERATIONS',
        'Vérifiez les opérations sélectionnées.',
      );
    }
    await (db.update(db.outboxRows)..where(
          (t) =>
              t.accountId.equals(account) &
              t.storeId.equals(store) &
              t.operationId.isIn(ids),
        ))
        .write(
          OutboxRowsCompanion(
            status: const Value('resolved'),
            resolution: Value(reason),
            resolvedAt: Value(DateTime.now()),
          ),
        );
  }

  void _sameAccount(UserAccount user) {
    if (api.accountId != user.id) {
      throw const AppFailure(
        'ACCOUNT_CHANGED',
        'Reconnectez-vous au compte d’origine pour synchroniser ses opérations.',
      );
    }
  }

  @override
  Future<void> synchronize(UserAccount user, Store store) async {
    if (_syncing) return;
    _syncing = true;
    try {
      final pending = await operations(user.id, store.id);
      for (final operation in pending.take(50)) {
        if (operation.status == 'accepted') continue;
        if (operation.status != 'pending') break;
        _sameAccount(user);
        final result = await api.push([
          Map<String, dynamic>.from(jsonDecode(operation.payload)),
        ]);
        final accepted = objects(result['results']).single;
        await (db.update(db.outboxRows)..where(
              (t) =>
                  t.operationId.equals(operation.operationId) &
                  t.accountId.equals(user.id),
            ))
            .write(
              OutboxRowsCompanion(
                status: Value(accepted['status']),
                error: Value(accepted['message']),
                attempts: Value(operation.attempts + 1),
              ),
            );
        if (accepted['status'] != 'accepted') break;
      }
      await refresh(user, store);
    } on DioException {
      rethrow;
    } finally {
      _syncing = false;
    }
  }

  @override
  Future<void> saveDraft(
    String accountId,
    String storeId,
    String key,
    Json value,
  ) => db
      .into(db.draftRows)
      .insertOnConflictUpdate(
        DraftRowsCompanion.insert(
          accountId: accountId,
          storeId: storeId,
          key: key,
          payload: jsonEncode(value),
        ),
      );
  @override
  Future<Json?> draft(String accountId, String storeId, String key) async {
    final row =
        await (db.select(db.draftRows)..where(
              (t) =>
                  t.accountId.equals(accountId) &
                  t.storeId.equals(storeId) &
                  t.key.equals(key),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(row.payload));
  }
}
