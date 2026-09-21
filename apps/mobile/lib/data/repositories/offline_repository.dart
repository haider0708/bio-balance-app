import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:dio/dio.dart';

import '../../domain/models/models.dart';
import '../../domain/synchronization/stock_projection.dart';
import '../../domain/synchronization/retry_policy.dart';
import '../../domain/repositories/workspace_repository.dart';
import '../services/api/generated/api_client.dart';
import '../services/local_database/database.dart';

class OfflineRepository implements WorkspaceRepository {
  final AppDatabase db;
  final ApiClient api;
  bool _syncing = false;
  final DateTime Function() now;
  final RetryPolicy retryPolicy;
  OfflineRepository(
    this.db,
    this.api, {
    DateTime Function()? now,
    RetryPolicy? retryPolicy,
  }) : now = now ?? DateTime.now,
       retryPolicy = retryPolicy ?? RetryPolicy();
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
      final command = Map<String, dynamic>.from(
        jsonDecode(row.payload)['command'] ?? {},
      );
      if (effect['projectionVersion'] != 2 && command.isNotEmpty) {
        final projection = StockProjection.forCommand(
          store.id,
          command,
          StoreData({...raw, 'sales': sales, 'lots': lots}),
          now: now(),
        );
        effect['lots'] = projection.movements.map((m) => m.toJson()).toList();
      }
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
        StockProjection.apply(lots, patch);
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
    // Expiration retries start from a new snapshot; pending work stays intact.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _refresh(user, store);
        return;
      } on DioException catch (e) {
        if (e.response?.statusCode != 410 || attempt == 2) rethrow;
      }
    }
  }

  Future<void> _refresh(UserAccount user, Store store) async {
    _sameAccount(user);
    final outstanding = await operations(user.id, store.id);
    final uncertain = outstanding
        .where(
          (o) =>
              o.mayHaveBeenSent &&
              (!['conflict', 'rejected', 'blocked'].contains(o.status)) &&
              (o.acknowledgment == null ||
                  jsonDecode(o.acknowledgment!)['committedCursor'] == null),
        )
        .toList();
    for (var start = 0; start < uncertain.length; start += 50) {
      final batch = uncertain.skip(start).take(50).toList();
      final response = Map<String, dynamic>.from(
        await api.request(
          'POST',
          '/v1/sync/status',
          body: {
            'operations': batch.map((o) => jsonDecode(o.payload)).toList(),
          },
        ),
      );
      _sameAccount(user);
      for (final result in objects(response['results'])) {
        final row = batch
            .where((o) => o.operationId == result['operationId'])
            .firstOrNull;
        if (row != null && result['status'] == 'accepted') {
          await _update(
            row,
            OutboxRowsCompanion(
              status: const Value('accepted'),
              acknowledgment: Value(jsonEncode(result)),
            ),
          );
        }
      }
    }
    final queued = await operations(user.id, store.id);
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
          'protocol': 3,
          if (integer(prior['syncProtocol']) >= 3) 'after': prior['cursor'],
          if (integer(prior['syncProtocol']) >= 3)
            'catalogRevision': prior['catalogRevision'],
          if (queued.isNotEmpty)
            'acknowledgments': queued
                .take(50)
                .map((o) => o.operationId)
                .join(','),
        },
      ),
    );
    _sameAccount(user);
    final merge = List<String>.from(snapshot.remove('mergeResources') ?? []);
    final pages = Map<String, dynamic>.from(
      snapshot.remove('snapshotPages') ?? {},
    );
    if (integer(snapshot['syncProtocol']) >= 3) {
      for (final resource in ['lots', 'products', 'config']) {
        String? token = pages[resource];
        final seen = <String>{};
        while (token != null) {
          if (!seen.add(token)) {
            throw const AppFailure(
              'INVALID_SNAPSHOT',
              'Copie du magasin invalide.',
            );
          }
          final page = Map<String, dynamic>.from(
            await api.request(
              'GET',
              '/v1/stores/${store.id}/snapshot-pages/$token',
              query: {'organizationId': store.organizationId},
            ),
          );
          _sameAccount(user);
          if (page['resource'] != resource ||
              page['cursor'] != snapshot['cursor']) {
            throw const AppFailure(
              'INVALID_SNAPSHOT',
              'Copie du magasin invalide.',
            );
          }
          (snapshot[resource] as List).addAll(objects(page['items']));
          token = page['nextPage'];
        }
      }
    } else if (Map<String, dynamic>.from(snapshot['pagination'] ?? {}).values
        .any((v) => v != null)) {
      // Do not install a live, inconsistent multi-page legacy snapshot.
      throw const AppFailure(
        'SYNC_UPGRADE_REQUIRED',
        'Le serveur doit être mis à jour pour synchroniser ce magasin.',
      );
    }
    snapshot.remove('pagination');
    final proven = Set<String>.from(
      snapshot.remove('appliedOperationIds') ?? [],
    );
    final cursor = BigInt.tryParse('${snapshot['cursor']}') ?? BigInt.zero;
    final acknowledged = queued
        .where((o) {
          if (proven.contains(o.operationId)) return true;
          final ack = o.acknowledgment == null
              ? null
              : jsonDecode(o.acknowledgment!);
          final committed = BigInt.tryParse('${ack?['committedCursor']}');
          return o.status == 'accepted' &&
              committed != null &&
              committed <= cursor &&
              integer(snapshot['syncProtocol']) >= 3;
        })
        .map((o) => o.operationId)
        .toList();
    _sameAccount(user);
    await db.transaction(() async {
      _sameAccount(user);
      await (db.delete(db.cacheEntries)..where(
            (t) =>
                t.accountId.equals(user.id) &
                t.storeId.equals(store.id) &
                t.resource.isNotIn(merge),
          ))
          .go();
      final meta = <String, dynamic>{};
      for (final entry in snapshot.entries) {
        if (entry.value is List && entry.key != 'permissions') {
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
      final current = await load(user, store);
      final command = Map<String, dynamic>.from(operation['command'] ?? {});
      final projection = StockProjection.forCommand(
        store.id,
        command,
        current,
        now: now(),
      );
      final predecessors = <String, String>{};
      for (final row in await operations(user.id, store.id)) {
        final keys = List<String>.from(jsonDecode(row.records));
        if (keys.isEmpty) {
          final oldCommand = Map<String, dynamic>.from(
            jsonDecode(row.payload)['command'] ?? {},
          );
          final oldEffect = Map<String, dynamic>.from(jsonDecode(row.effect));
          keys.addAll(objects(oldEffect['lots']).map((p) => 'lot:${p['id']}'));
          for (final key in ['saleId', 'deliveryId', 'orderId', 'claimId']) {
            if (oldCommand[key] != null) {
              keys.add('${key == 'saleId' ? 'sale' : key}:${oldCommand[key]}');
            }
          }
        }
        for (final key in keys) {
          predecessors[key] = row.operationId;
        }
      }
      final dependencies = projection.records
          .map((key) => predecessors[key])
          .whereType<String>()
          .toSet()
          .toList();
      final envelope = {
        ...operation,
        if (operation['payloadVersion'] == 2) 'dependencies': dependencies,
      };
      final projectedEffect = {
        ...effect,
        'projectionVersion': 2,
        'lots': projection.movements.map((m) => m.toJson()).toList(),
      };
      await db
          .into(db.outboxRows)
          .insert(
            OutboxRowsCompanion.insert(
              operationId: operation['operationId'],
              accountId: user.id,
              storeId: store.id,
              payload: jsonEncode(envelope),
              effect: jsonEncode(projectedEffect),
              dependencies: Value(jsonEncode(dependencies)),
              records: Value(jsonEncode(projection.records.toList())),
              mayHaveBeenSent: const Value(false),
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
    final related = dependentOperations(rows, selected.first.operationId);
    if (related.any((r) => !ids.contains(r.operationId)) ||
        selected.any(
          (r) => !related.any((d) => d.operationId == r.operationId),
        )) {
      throw const AppFailure(
        'DEPENDENT_OPERATIONS',
        'Vérifiez toutes les opérations liées avant de résoudre ce conflit.',
      );
    }
    if (selected
        .skip(1)
        .any(
          (r) =>
              r.mayHaveBeenSent && !['conflict', 'rejected'].contains(r.status),
        )) {
      throw const AppFailure(
        'UNCONFIRMED_OPERATION',
        'Une opération liée doit être vérifiée sur le serveur avant de poursuivre.',
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

  List<OutboxRow> dependentOperations(
    List<OutboxRow> rows,
    String operationId,
  ) {
    final ids = <String>{operationId};
    for (final row in rows) {
      if (row.status == 'resolved') continue;
      if (List<String>.from(jsonDecode(row.dependencies)).any(ids.contains)) {
        ids.add(row.operationId);
      }
    }
    return rows
        .where((r) => ids.contains(r.operationId) && r.status != 'resolved')
        .toList();
  }

  Future<void> _upgradeDependencyMetadata(UserAccount user, Store store) async {
    await db.transaction(() async {
      final previous = <String, String>{};
      for (final row in await operations(user.id, store.id)) {
        var keys = List<String>.from(jsonDecode(row.records));
        if (keys.isEmpty) {
          final command = Map<String, dynamic>.from(
            jsonDecode(row.payload)['command'] ?? {},
          );
          final effect = Map<String, dynamic>.from(jsonDecode(row.effect));
          keys = {
            ...StockProjection.forCommand(store.id, command, null).records,
            ...objects(effect['lots']).map((p) => 'lot:${p['id']}'),
          }.toList();
          final dependencies = keys
              .map((k) => previous[k])
              .whereType<String>()
              .toSet()
              .toList();
          await _update(
            row,
            OutboxRowsCompanion(
              records: Value(jsonEncode(keys)),
              dependencies: Value(jsonEncode(dependencies)),
            ),
          );
        }
        for (final key in keys) {
          previous[key] = row.operationId;
        }
      }
    });
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
      _sameAccount(user);
      await _upgradeDependencyMetadata(user, store);
      final queued = await operations(user.id, store.id, includeResolved: true);
      final statuses = {for (final row in queued) row.operationId: row.status};
      var submitted = 0;
      for (final operation in queued) {
        if (submitted >= 50) break;
        if (!['pending', 'blocked', 'retryable'].contains(operation.status)) {
          continue;
        }
        final dependencies = List<String>.from(
          jsonDecode(operation.dependencies),
        );
        final blockers = dependencies.where(
          (id) => statuses.containsKey(id) && statuses[id] != 'accepted',
        );
        if (blockers.isNotEmpty) {
          statuses[operation.operationId] = 'blocked';
          await _update(
            operation,
            const OutboxRowsCompanion(
              status: Value('blocked'),
              error: Value(
                'Une opération précédente doit être synchronisée ou corrigée.',
              ),
            ),
          );
          continue;
        }
        if (operation.nextAttemptAt != null &&
            operation.nextAttemptAt!.isAfter(now())) {
          continue;
        }
        _sameAccount(user);
        submitted++;
        final attempts = operation.attempts + 1;
        // Commit uncertainty before network I/O; a killed process must retry the same bytes.
        await _update(
          operation,
          OutboxRowsCompanion(
            attempts: Value(attempts),
            mayHaveBeenSent: const Value(true),
          ),
        );
        try {
          final result = await api.push([
            Map<String, dynamic>.from(jsonDecode(operation.payload)),
          ]);
          _sameAccount(user);
          final accepted = objects(result['results']).single;
          if (accepted['operationId'] != operation.operationId) {
            throw const AppFailure(
              'INVALID_ACK',
              'Réponse de synchronisation invalide.',
            );
          }
          final status = accepted['status'] as String;
          if ([
            'FORBIDDEN',
            'ACCESS_DISABLED',
            'SESSION_EXPIRED',
          ].contains(accepted['code'])) {
            throw DioException(
              requestOptions: RequestOptions(),
              response: Response(
                requestOptions: RequestOptions(),
                statusCode: accepted['code'] == 'SESSION_EXPIRED' ? 401 : 403,
                data: accepted,
              ),
            );
          }
          statuses[operation.operationId] = status;
          await _update(
            operation,
            OutboxRowsCompanion(
              status: Value(status),
              error: Value(accepted['message']),
              acknowledgment: Value(
                status == 'accepted' ? jsonEncode(accepted) : null,
              ),
              nextAttemptAt: Value(
                status == 'retryable'
                    ? now().add(
                        retryPolicy.delay(
                          attempts,
                          now(),
                          retryAfter: accepted['retryAfterMs'] == null
                              ? null
                              : '${(integer(accepted['retryAfterMs']) / 1000).ceil()}',
                        ),
                      )
                    : null,
              ),
            ),
          );
        } on DioException catch (e) {
          _sameAccount(user);
          final code = e.response?.statusCode;
          if (code == 401 || code == 403) rethrow;
          final retryable =
              code == null || code == 408 || code == 429 || code >= 500;
          await _update(
            operation,
            OutboxRowsCompanion(
              status: Value(retryable ? 'retryable' : 'rejected'),
              error: Value(
                retryable
                    ? 'Connexion interrompue. Nouvelle tentative programmée.'
                    : 'Opération refusée. Vérifiez les informations saisies.',
              ),
              nextAttemptAt: Value(
                retryable
                    ? now().add(
                        retryPolicy.delay(
                          attempts,
                          now(),
                          retryAfter: e.response?.headers.value('retry-after'),
                        ),
                      )
                    : null,
              ),
            ),
          );
          statuses[operation.operationId] = retryable
              ? 'retryable'
              : 'rejected';
          if (retryable) rethrow;
        }
      }
      await refresh(user, store);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _update(OutboxRow operation, OutboxRowsCompanion values) async {
    await (db.update(db.outboxRows)..where(
          (t) =>
              t.operationId.equals(operation.operationId) &
              t.accountId.equals(operation.accountId),
        ))
        .write(values);
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
