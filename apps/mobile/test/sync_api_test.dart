import 'support/test_origin.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/batch_declaration.dart';
import 'package:biobalance/domain/models/money.dart';
import 'package:biobalance/domain/synchronization/stock_projection.dart';
import 'package:biobalance/domain/use_cases/record_sale.dart';
import 'package:biobalance/domain/use_cases/record_return.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

class LostResponseAdapter implements HttpClientAdapter {
  final HttpClientAdapter delegate;
  bool loseResponse = true, loseSnapshot = false;
  LostResponseAdapter(this.delegate);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    final result = await delegate.fetch(options, stream, cancel);
    if (options.path.endsWith('/snapshot') && loseSnapshot) {
      loseSnapshot = false;
      await result.stream.drain<void>();
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    if (options.path == '/v1/sync/push' && loseResponse) {
      loseResponse = false;
      await result.stream.drain<void>();
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    return result;
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
}

void main() {
  final env = Platform.environment;
  test(
    'real API recovery preserves stock, versions, points and histories',
    () async {
      final user = UserAccount(
        id: env['BIOBALANCE_TEST_USER']!,
        name: 'Offline test',
        email: 'test@example.test',
        admin: false,
      );
      final store = Store.fromJson({
        'id': env['BIOBALANCE_TEST_STORE'],
        'organizationId': env['BIOBALANCE_TEST_ORG'],
        'name': 'Test store',
        'permissions': ['manage', 'sell', 'receive'],
      });
      final product = env['BIOBALANCE_TEST_PRODUCT']!;
      final dio = Dio(testOptions(env['BIOBALANCE_TEST_URL']!));
      dio.httpClientAdapter = LostResponseAdapter(dio.httpClientAdapter);
      final api = ApiClient(baseUrl: env['BIOBALANCE_TEST_URL']!, dio: dio)
        ..authenticate(env['BIOBALANCE_TEST_TOKEN'], accountId: user.id);
      final directory = await Directory.systemTemp.createTemp(
        'biobalance-real-sync-',
      );
      final file = File('${directory.path}/local.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      final clock = DateTime.now();
      var repo = OfflineRepository(db, api, now: () => clock);
      addTearDown(() async {
        await db.close();
        dio.close(force: true);
        await directory.delete(recursive: true);
      });
      await repo.refresh(user, store);
      final receiptLine = {
        'productId': product,
        'batch': 'CHAIN',
        'expiry': '2029-12-31',
        'quantity': 10,
      };
      final lotId = StockProjection.lotIdentity(store.id, receiptLine);
      Future<void> queue(Json command, {int? version, String? draft}) =>
          repo.enqueue(
            user,
            store,
            {
              'operationId': const Uuid().v4(),
              'storeId': store.id,
              'organizationId': store.organizationId,
              'payloadVersion': 2,
              'expectedVersion': ?version,
              'command': command,
            },
            {},
            draftKey: draft,
          );
      await repo.saveDraft(user.id, store.id, 'receipt', {
        'lines': [receiptLine],
      });
      await queue({
        'type': 'stock.receive',
        'reason': 'receipt',
        'lines': [receiptLine],
      }, draft: 'receipt');
      expect(await repo.draft(user.id, store.id, 'receipt'), isNull);
      expect((await repo.load(user, store))!.lots.single.version, 2);
      final lineId = const Uuid().v4();
      List<SaleLine> lines(int quantity) => [
        SaleLine(
          id: lineId,
          productId: product,
          quantity: quantity,
          price: Money(1000),
          allocations: [
            {'lotId': lotId, 'quantity': quantity},
          ],
        ),
      ];
      await RecordSale(repo).execute(user, store, lines(4));
      expect((await repo.load(user, store))!.lots.single.version, 3);
      await queue({
        'type': 'stock.damage',
        'lotId': lotId,
        'quantity': 1,
        'reason': 'Casse',
      }, version: 3);
      expect((await repo.load(user, store))!.lots.single.version, 5);
      var sale = (await repo.load(user, store))!.list('sales').single;
      await RecordSale(repo).execute(
        user,
        store,
        lines(3),
        original: sale,
        reason: 'Erreur de quantité',
      );
      sale = (await repo.load(user, store))!.list('sales').single;
      await RecordReturn(repo).execute(
        user,
        store,
        sale,
        lineId: lineId,
        lotId: lotId,
        quantity: 1,
        sellable: true,
        reason: 'Retour client',
      );
      final local = (await repo.load(user, store))!.list('lots').single;
      expect(local, containsPair('sellable', 7));
      expect(local, containsPair('damaged', 1));
      expect(local, containsPair('version', 7));
      final operations = await repo.operations(user.id, store.id);
      expect(operations.length, 5);
      for (final row in operations.skip(1)) {
        expect(row.dependencies, isNot('[]'));
      }
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      repo = OfflineRepository(db, api, now: () => clock);
      await expectLater(
        repo.synchronize(user, store),
        throwsA(isA<DioException>()),
      );
      final uncertain = (await repo.operations(user.id, store.id)).first;
      expect(uncertain.mayHaveBeenSent, isTrue);
      expect(uncertain.nextAttemptAt, isNotNull);
      expect(uncertain.payload, operations.first.payload);
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      repo = OfflineRepository(db, api, now: () => clock);
      // Read-only reconciliation proves the lost receipt response; the next pass sends dependents.
      await repo.synchronize(user, store);
      (dio.httpClientAdapter as LostResponseAdapter).loseSnapshot = true;
      await expectLater(
        repo.synchronize(user, store),
        throwsA(isA<DioException>()),
      );
      final provisional = (await repo.load(user, store))!.lots.single;
      expect(provisional.sellable, 7);
      expect(provisional.version, 7);
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      repo = OfflineRepository(db, api, now: () => clock);
      await repo.synchronize(user, store);
      expect(await repo.pendingCount(user.id), 0);
      final synchronized = (await repo.load(user, store))!;
      expect(synchronized.list('lots').single['sellable'], 7);
      expect(synchronized.list('lots').single['damaged'], 1);
      expect(synchronized.lots.single.version, 7);
      expect(synchronized.list('sales').single['version'], 3);
      expect(synchronized.raw['points']['balance'], '20');
    },
    skip: env['BIOBALANCE_TEST_URL'] == null
        ? 'Run npm run test:mobile-sync against the isolated test database.'
        : false,
  );
  test(
    'real seller missing-batch sale has no incoming stock',
    () async {
      final api = ApiClient(baseUrl: env['BIOBALANCE_TEST_URL']!)
        ..authenticate(
          env['BIOBALANCE_TEST_TOKEN'],
          accountId: env['BIOBALANCE_TEST_USER'],
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final user = UserAccount(
        id: env['BIOBALANCE_TEST_USER']!,
        name: 'Seller',
        email: 'test@example.test',
        admin: false,
      );
      final store = Store.fromJson({
        'id': env['BIOBALANCE_TEST_EMPTY_STORE'],
        'organizationId': env['BIOBALANCE_TEST_ORG'],
        'name': 'Empty',
        'permissions': ['sell', 'receive'],
      });
      final repo = OfflineRepository(db, api);
      await repo.refresh(user, store);
      final batch = BatchDeclaration.create(
        store.id,
        env['BIOBALANCE_TEST_PRODUCT']!,
        'NEW-BATCH',
        '12/2029',
      );
      await RecordSale(repo).execute(user, store, [
        SaleLine(
          id: const Uuid().v4(),
          productId: batch.productId,
          quantity: 2,
          price: Money(14990),
          allocations: [
            {'lotId': batch.lotId, 'quantity': 2},
          ],
          batchDeclarations: [batch],
        ),
      ]);
      expect((await repo.load(user, store))!.lots.single.sellable, -2);
      expect((await repo.load(user, store))!.lots.single.version, 2);
      await repo.synchronize(user, store);
      expect(await repo.pendingCount(user.id), 0);
      expect((await repo.load(user, store))!.lots.single.sellable, -2);
      expect((await repo.load(user, store))!.lots.single.version, 2);
    },
    skip: env['BIOBALANCE_TEST_URL'] == null
        ? 'Run npm run test:mobile-sync.'
        : false,
  );
}
