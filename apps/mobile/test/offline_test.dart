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
    if (options.path == '/v1/sync/push') {
      final operations = objects(options.data['operations']);
      response = {
        'results': operations.map((o) {
          if (accepted.add(o['operationId'])) applied++;
          return {'operationId': o['operationId'], 'status': 'accepted'};
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
        'store': store.toJson(),
        'products': [],
        'config': [],
        'lots': [],
        'sales': [],
        'points': {'balance': '10', 'reserved': '0'},
        'pagination': {},
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
  });
}
