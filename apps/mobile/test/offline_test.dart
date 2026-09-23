import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/money.dart';
import 'package:biobalance/domain/use_cases/record_sale.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:biobalance/domain/use_cases/record_return.dart';
import 'package:biobalance/domain/synchronization/retry_policy.dart';
import 'package:biobalance/domain/synchronization/stock_projection.dart';
import 'package:flutter_test/flutter_test.dart';

const user = UserAccount(
  id: 'owner',
  name: 'Test',
  email: 'test@example.test',
  admin: false,
);
final store = Store.fromJson({
  'id': 'store-a',
  'organizationId': 'org-a',
  'name': 'Test',
  'permissions': ['sell'],
});

class FakeServer implements HttpClientAdapter {
  bool offline = false, loseResponse = false;
  final accepted = <String>{};
  final conflicts = <String>{};
  final submissions = <String>[];
  int applied = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    dynamic response;
    if (options.path == '/v1/sync/status') {
      response = {
        'results': objects(options.data['operations'])
            .map(
              (o) => {
                'operationId': o['operationId'],
                'status': accepted.contains(o['operationId'])
                    ? 'accepted'
                    : 'unknown',
                if (accepted.contains(o['operationId']))
                  'committedCursor': '$applied',
                if (accepted.contains(o['operationId']))
                  'data': {'id': o['operationId']},
              },
            )
            .toList(),
      };
    } else if (options.path == '/v1/sync/push') {
      final operations = objects(options.data['operations']);
      response = {
        'results': operations.map((o) {
          submissions.add(o['operationId']);
          if (conflicts.contains(o['operationId'])) {
            return {
              'operationId': o['operationId'],
              'status': 'conflict',
              'code': 'VERSION_CONFLICT',
              'message': 'Version modifiée.',
            };
          }
          if (accepted.add(o['operationId'])) applied++;
          return {
            'operationId': o['operationId'],
            'status': 'accepted',
            'data': {'id': o['operationId']},
            'committedCursor': '$applied',
            'affectedVersions': [],
          };
        }).toList(),
      };
      if (loseResponse) {
        loseResponse = false;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      }
    } else {
      response = {
        'syncProtocol': 3,
        'appliedOperationIds': accepted.toList(),
        'store': {
          'id': store.id,
          'organizationId': store.organizationId,
          'name': store.name,
          'address': 'Test',
          'city': 'Tunis',
          'phone': null,
          'imageId': null,
          'timezone': 'Africa/Tunis',
          'onboardingStep': 1,
          'workingAlone': false,
          'noOpeningStock': false,
          'version': 1,
          'createdAt': '2026-01-01T00:00:00Z',
        },
        'snapshotPages': {},
        'snapshotExpiresAt': '2099-01-01T00:00:00Z',
        'catalogRevision': '0:0',
        'mode': 'snapshot',
        'mergeResources': [],
        'summary': {'saleCount': '0', 'totalMillimes': '0'},
        'onboarding': null,
        'permissions': ['sell'],
        'alerts': [],
        'rewards': [],
        'claims': [],
        'orders': [],
        'outstandingSupply': [],
        'deliveries': [],
        'team': [],
        'invitations': [],
        'serverTime': '2026-01-01T00:00:00Z',
        'products': [],
        'config': [],
        'lots': [],
        'sales': [],
        'points': {'balance': '10', 'reserved': '0'},
        'pagination': {'lots': null, 'products': null, 'config': null},
        'cursor': '$applied',
      };
    }
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('TND parsing is exact with French decimal commas', () {
    expect(Money.parse('49,900').times(3).millimes, 149700);
    expect(Money.parse('0,001').formatted, '0,001 TND');
    expect(() => Money.parse('2,0001'), throwsFormatException);
  });
  test('sale and queue survive process restart; lost responses do not duplicate the server effect', () async {
    final directory = await Directory.systemTemp.createTemp(
      'biobalance-offline-',
    );
    final file = File('${directory.path}/test.sqlite');
    final server = FakeServer();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = server;
    final api = ApiClient(baseUrl: 'http://test', dio: dio)
      ..authenticate('token', accountId: user.id);
    var db = AppDatabase(NativeDatabase(file));
    var repository = OfflineRepository(db, api);
    await repository.refresh(user, store);
    await RecordSale(repository).execute(user, store, [
      SaleLine(
        id: 'line',
        productId: 'product',
        quantity: 2,
        price: Money(49900),
        allocations: [
          {'lotId': 'lot', 'quantity': 2},
        ],
      ),
    ]);
    expect(await repository.pendingCount(user.id), 1);
    expect(
      (await repository.load(
        user,
        store,
      ))!.list('sales').single['totalMillimes'],
      '99800',
    );
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    repository = OfflineRepository(db, api);
    expect(await repository.pendingCount(user.id), 1);
    server.loseResponse = true;
    await expectLater(
      repository.synchronize(user, store),
      throwsA(isA<DioException>()),
    );
    expect(server.applied, 1);
    expect(await repository.pendingCount(user.id), 1);
    await repository.synchronize(user, store);
    expect(server.applied, 1);
    expect(await repository.pendingCount(user.id), 0);
    await db.close();
    await directory.delete(recursive: true);
  });
  test(
    'store switching and account switching cannot reroute queued operations',
    () async {
      final db = AppDatabase(NativeDatabase.memory()), server = FakeServer();
      final api = ApiClient(
        baseUrl: 'http://test',
        dio: Dio(BaseOptions(baseUrl: 'http://test'))
          ..httpClientAdapter = server,
      )..authenticate('token', accountId: user.id);
      final repo = OfflineRepository(db, api);
      await repo.enqueue(user, store, {
        'operationId': 'op',
        'storeId': store.id,
        'organizationId': store.organizationId,
        'command': {'type': 'sale.create'},
      }, {});
      final other = Store.fromJson({
        'id': 'store-b',
        'organizationId': 'org-a',
        'name': 'Other',
      });
      expect(await repo.operations(user.id, other.id), isEmpty);
      api.authenticate('different-token', accountId: 'other-person');
      await expectLater(
        repo.synchronize(user, store),
        throwsA(isA<AppFailure>()),
      );
      expect(server.applied, 0);
      expect(await repo.pendingCount(user.id), 1);
      await db.close();
    },
  );
  test('offline failures preserve the draft and queued work', () async {
    final db = AppDatabase(NativeDatabase.memory()),
        server = FakeServer()..offline = true;
    final api = ApiClient(
      baseUrl: 'http://test',
      dio: Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
    )..authenticate('token', accountId: user.id);
    final repo = OfflineRepository(db, api);
    await repo.saveDraft(user.id, store.id, 'sale', {
      'lines': [
        {'productId': 'p'},
      ],
    });
    await repo.enqueue(user, store, {
      'operationId': 'op',
      'storeId': store.id,
      'organizationId': store.organizationId,
    }, {});
    await expectLater(
      repo.synchronize(user, store),
      throwsA(isA<DioException>()),
    );
    expect(await repo.draft(user.id, store.id, 'sale'), isNotNull);
    expect(await repo.pendingCount(user.id), 1);
    await db.close();
  });
  test(
    'failed sale replacement is atomic and retains the original operation',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final server = FakeServer();
      final api = ApiClient(
        baseUrl: 'http://test',
        dio: Dio(BaseOptions(baseUrl: 'http://test'))
          ..httpClientAdapter = server,
      )..authenticate('token', accountId: user.id);
      final repo = OfflineRepository(db, api);
      await repo.refresh(user, store);
      final lines = [
        SaleLine(
          id: 'l',
          productId: 'p',
          quantity: 2,
          price: Money(1000),
          allocations: [
            {'lotId': 'lot', 'quantity': 2},
          ],
        ),
      ];
      await RecordSale(repo).execute(user, store, lines);
      final old = (await repo.operations(user.id, store.id)).single;
      final sale = (await repo.load(user, store))!.list('sales').single;
      await expectLater(
        repo.resolve(user, store, [old.operationId], 'review'),
        throwsA(isA<AppFailure>()),
      );
      await (db.update(
        db.outboxRows,
      )..where((r) => r.operationId.equals(old.operationId))).write(
        const OutboxRowsCompanion(
          status: Value('conflict'),
          error: Value('Version conflict'),
        ),
      );
      await RecordSale(repo).execute(
        user,
        store,
        lines,
        recoveredSaleId: sale['id'],
        recoveredDate: sale['occurredAt'],
        supersedes: [old.operationId],
      );
      final active = await repo.operations(user.id, store.id);
      expect(active.length, 1);
      expect(active.single.operationId, isNot(old.operationId));
      expect(
        jsonDecode(active.single.payload)['command']['saleId'],
        sale['id'],
      );
      final history = await repo.operations(
        user.id,
        store.id,
        includeResolved: true,
      );
      expect(history.length, 2);
      expect(history.first.status, 'resolved');
      expect(history.first.payload, old.payload);
      expect(history.first.resolvedAt, isNotNull);
      expect((await repo.load(user, store))!.list('sales').length, 1);
    },
  );
  test(
    'offline returns update eligible quantities and the next version',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = OfflineRepository(db, ApiClient(baseUrl: 'http://test'));
      await db.customStatement(
        'INSERT INTO cache_entries VALUES (?, ?, ?, ?, ?)',
        [
          user.id,
          store.id,
          'sales',
          'sale',
          jsonEncode({
            'id': 'sale',
            'sellerId': user.id,
            'version': 1,
            'returned': {},
            'lines': [
              {
                'id': 'line',
                'allocations': [
                  {'lotId': 'lot', 'quantity': 2},
                ],
              },
            ],
          }),
        ],
      );
      final sale = (await repo.load(user, store))!.list('sales').single;
      await RecordReturn(repo).execute(
        user,
        store,
        sale,
        lineId: 'line',
        lotId: 'lot',
        quantity: 2,
        sellable: true,
        reason: 'Retour',
      );
      final current = (await repo.load(user, store))!.list('sales').single;
      expect(current['version'], 2);
      expect(current['returned']['line:lot'], 2);
      await expectLater(
        RecordReturn(repo).execute(
          user,
          store,
          current,
          lineId: 'line',
          lotId: 'lot',
          quantity: 1,
          sellable: true,
          reason: 'Doublon',
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(await repo.pendingCount(user.id), 1);
    },
  );
  test('retry schedule uses jitter, Retry-After and a five-minute ceiling', () {
    final policy = RetryPolicy(random: () => 0.5),
        now = DateTime.utc(2026, 9, 21);
    expect(policy.delay(1, now).inMilliseconds, 750);
    expect(policy.delay(2, now).inMilliseconds, 1500);
    expect(policy.delay(3, now, retryAfter: '30'), const Duration(seconds: 30));
    expect(
      policy.delay(
        3,
        now,
        retryAfter: HttpDate.format(now.add(const Duration(seconds: 45))),
      ),
      const Duration(seconds: 45),
    );
    expect(
      policy.delay(99, now, retryAfter: '900'),
      const Duration(minutes: 5),
    );
  });
  test(
    'a conflict blocks dependent lots while unrelated work continues',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final server = FakeServer()..conflicts.add('receipt');
      final api = ApiClient(
        baseUrl: 'http://test',
        dio: Dio(BaseOptions(baseUrl: 'http://test'))
          ..httpClientAdapter = server,
      )..authenticate('token', accountId: user.id);
      final repo = OfflineRepository(db, api);
      await repo.refresh(user, store);
      final line = {
        'productId': 'p',
        'batch': 'B',
        'expiry': '2029-12-31',
        'quantity': 10,
      };
      final lot = StockProjection.lotIdentity(store.id, line);
      Future<void> enqueue(String id, Json command, int? version) =>
          repo.enqueue(user, store, {
            'operationId': id,
            'storeId': store.id,
            'organizationId': store.organizationId,
            'payloadVersion': 2,
            'expectedVersion': ?version,
            'command': command,
          }, {});
      await enqueue('receipt', {
        'type': 'stock.receive',
        'reason': 'receipt',
        'lines': [line],
      }, null);
      await enqueue('damage', {
        'type': 'stock.damage',
        'lotId': lot,
        'quantity': 1,
        'reason': 'Casse',
      }, 2);
      await enqueue('unrelated', {
        'type': 'stock.receive',
        'reason': 'receipt',
        'lines': [
          {...line, 'batch': 'C'},
        ],
      }, null);
      await repo.synchronize(user, store);
      final rows = await repo.operations(user.id, store.id);
      expect(server.submissions, ['receipt', 'unrelated']);
      expect(rows.map((r) => r.status), ['conflict', 'blocked']);
      expect(jsonDecode(rows.last.dependencies), ['receipt']);
      expect(rows.last.mayHaveBeenSent, isFalse);
      expect(repo.dependentOperations(rows, 'receipt').length, 2);
      await expectLater(
        repo.resolve(user, store, ['receipt'], 'review'),
        throwsA(isA<AppFailure>()),
      );
      await repo.resolve(user, store, ['receipt', 'damage'], 'review');
      expect(await repo.operations(user.id, store.id), isEmpty);
      expect(
        (await repo.operations(
          user.id,
          store.id,
          includeResolved: true,
        )).length,
        2,
      );
    },
  );
  test('stock expiry routes returned units to damaged and preserves movement increments', () {
    final lots = <Json>[
      {
        'id': 'lot',
        'productId': 'p',
        'batch': 'B',
        'expiry': '2026-09-20',
        'sellable': 0,
        'damaged': 0,
        'version': 5,
      },
    ];
    final projection = StockProjection.forCommand(
      store.id,
      {
        'type': 'sale.return',
        'saleId': 'sale',
        'lines': [
          {'lotId': 'lot', 'quantity': 2, 'sellable': true},
        ],
      },
      StoreData({'lots': lots}),
      now: DateTime.utc(2026, 9, 21),
    );
    StockProjection.apply(lots, projection.movements.single.toJson());
    expect(lots.single['sellable'], 0);
    expect(lots.single['damaged'], 2);
    expect(lots.single['version'], 6);
  });
  test('delivery condition projection agrees with sellable and damaged server buckets', () {
    final projection = StockProjection.forCommand(store.id, {
      'type': 'delivery.receive',
      'deliveryId': 'delivery',
      'lines': [
        {'productId': 'p', 'batch': 'B', 'expiry': '2028-12', 'quantity': 6},
        {
          'productId': 'p',
          'batch': 'B',
          'expiry': '2028-12',
          'quantity': 2,
          'condition': 'damaged',
        },
        {
          'productId': 'p',
          'batch': 'B',
          'expiry': '2028-12',
          'quantity': 2,
          'condition': 'refused',
        },
      ],
    }, null);
    final lots = <Json>[];
    for (final effect in projection.movements) {
      StockProjection.apply(lots, effect.toJson());
    }
    expect(projection.movements.length, 2);
    expect(lots.single['sellable'], 6);
    expect(lots.single['damaged'], 2);
    expect(lots.single['version'], 3);
  });
  test('SQLite version 1 migration preserves a populated outbox', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            "CREATE TABLE outbox_rows (sequence INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, operation_id TEXT NOT NULL UNIQUE, account_id TEXT NOT NULL, store_id TEXT NOT NULL, payload TEXT NOT NULL, effect TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending', error TEXT, attempts INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL DEFAULT (strftime('%s', CURRENT_TIMESTAMP)))",
          );
          raw.execute(
            "INSERT INTO outbox_rows(operation_id,account_id,store_id,payload,effect) VALUES ('op','owner','store-a','{}','{}')",
          );
          raw.execute('PRAGMA user_version=1');
        },
      ),
    );
    addTearDown(db.close);
    final rows = await db.select(db.outboxRows).get();
    expect(rows.single.operationId, 'op');
    expect(rows.single.resolution, isNull);
    expect(rows.single.status, 'pending');
    expect(rows.single.payload, '{}');
    expect(rows.single.mayHaveBeenSent, isTrue);
    expect(rows.single.dependencies, '[]');
    expect(rows.single.nextAttemptAt, isNull);
  });
}
