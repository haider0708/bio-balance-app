import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/synchronization/stock_projection.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'offline_test.dart' show FakeServer, user, store;

/// Holds HTTP responses at the boundaries where refresh and upload can overlap.
class StockServer extends FakeServer {
  final firstSnapshot = Completer<void>();
  final releaseFirstSnapshot = Completer<void>();
  final secondSnapshot = Completer<void>();
  final releaseSecondSnapshot = Completer<void>();
  final committed = Completer<void>();
  final lots = <Json>[];
  bool gateSnapshots = false;
  bool failFirstSnapshot = false;
  int snapshots = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    if (options.path.endsWith('/snapshot') && gateSnapshots) {
      snapshots++;
      if (snapshots == 1) {
        firstSnapshot.complete();
        await releaseFirstSnapshot.future;
        if (failFirstSnapshot) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
      } else if (snapshots == 2) {
        secondSnapshot.complete();
        await releaseSecondSnapshot.future;
      }
    }
    final wasAccepted = Set<String>.of(accepted);
    final response = await super.fetch(options, body, cancel);
    if (options.path == '/v1/sync/push') {
      for (final operation in objects(options.data['operations'])) {
        if (wasAccepted.contains(operation['operationId'])) continue;
        final projection = StockProjection.forCommand(
          operation['storeId'],
          Map<String, dynamic>.from(operation['command']),
          StoreData({'lots': lots}),
        );
        for (final movement in projection.movements) {
          StockProjection.apply(lots, movement.toJson());
        }
      }
      if (!committed.isCompleted) committed.complete();
    }
    if (!options.path.endsWith('/snapshot')) return response;
    final snapshot = jsonDecode(
      await utf8.decoder.bind(response.stream).join(),
    ) as Map<String, dynamic>;
    snapshot['lots'] = lots
        .map(
          (lot) => {
            ...lot,
            'organizationId': store.organizationId,
            'storeId': store.id,
          },
        )
        .toList();
    // The real server proves only the operation identifiers requested by the client.
    final requested = '${options.queryParameters['acknowledgments'] ?? ''}'
        .split(',');
    snapshot['appliedOperationIds'] = accepted
        .where(requested.contains)
        .toList();
    return ResponseBody.fromString(
      jsonEncode(snapshot),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

/// Pauses between the two local reads that make up a displayed workspace.
class ReadGateRepository extends OfflineRepository {
  ReadGateRepository(super.db, super.api);
  bool pauseNextRead = false;
  final readingOutbox = Completer<void>(), releaseRead = Completer<void>();

  @override
  Future<List<OutboxRow>> operations(
    String account,
    String store, {
    bool includeResolved = false,
  }) async {
    if (pauseNextRead) {
      pauseNextRead = false;
      readingOutbox.complete();
      await releaseRead.future;
    }
    return super.operations(account, store, includeResolved: includeResolved);
  }
}

class Fixture {
  final db = AppDatabase(NativeDatabase.memory());
  final server = StockServer();
  late final api = ApiClient(
    baseUrl: 'http://test',
    dio: Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
  )..authenticate('token', accountId: user.id);
  late final repo = ReadGateRepository(db, api);

  Future<void> receive() => repo.enqueue(user, store, {
    'operationId': 'receipt',
    'storeId': store.id,
    'organizationId': store.organizationId,
    'payloadVersion': 2,
    'command': {
      'type': 'stock.receive',
      'reason': 'Réception',
      'lines': [
        {
          'productId': 'p',
          'batch': 'B1',
          'expiry': '2029-12-31',
          'quantity': 2,
        },
      ],
    },
  }, {});
}

void main() {
  test(
    'a failed refresh releases queued synchronization without losing work',
    () async {
      final f = Fixture();
      addTearDown(f.db.close);
      f.server
        ..gateSnapshots = true
        ..failFirstSnapshot = true;
      f.server.releaseSecondSnapshot.complete();
      final refresh = expectLater(
        f.repo.refresh(user, store),
        throwsA(isA<DioException>()),
      );
      await f.server.firstSnapshot.future;
      await f.receive();
      final sync = f.repo.synchronize(user, store);
      f.server.releaseFirstSnapshot.complete();
      await Future.wait([refresh, sync]);
      expect(
        (await f.repo.load(user, store))!.list('lots').single['sellable'],
        2,
      );
      expect(await f.repo.pendingCount(user.id), 0);
      expect(f.server.applied, 1);
    },
  );

  test('queued work rejects a changed session and resumes under its original account', () async {
    final f = Fixture();
    addTearDown(f.db.close);
    f.server.gateSnapshots = true;
    f.server.releaseSecondSnapshot.complete();
    final refresh = expectLater(
      f.repo.refresh(user, store),
      throwsA(isA<AppFailure>()),
    );
    await f.server.firstSnapshot.future;
    await f.receive();
    final payload = (await f.repo.operations(user.id, store.id)).single.payload;
    final sync = expectLater(
      f.repo.synchronize(user, store),
      throwsA(isA<AppFailure>()),
    );
    f.api.authenticate('other-token', accountId: 'other-account');
    f.server.releaseFirstSnapshot.complete();
    await Future.wait([refresh, sync]);
    expect(f.server.submissions, isEmpty);
    expect(
      (await f.repo.operations(user.id, store.id)).single.payload,
      payload,
    );
    expect(await f.repo.pendingCount('other-account'), 0);
    f.api.authenticate('new-original-token', accountId: user.id);
    await f.repo.synchronize(user, store);
    expect(await f.repo.pendingCount(user.id), 0);
    expect(f.server.applied, 1);
  });

  test(
    'refresh overlapping a new receipt never shows its stock effect twice',
    () async {
      final f = Fixture();
      addTearDown(f.db.close);
      f.server.gateSnapshots = true;
      final refresh = f.repo.refresh(user, store);
      await f.server.firstSnapshot.future;
      await f.receive();
      final sync = f.repo.synchronize(user, store);
      // A correct implementation holds this upload until the snapshot is installed.
      await f.server.committed.future.timeout(
        const Duration(milliseconds: 200),
        onTimeout: () {},
      );
      f.server.releaseFirstSnapshot.complete();
      await refresh;
      await f.server.secondSnapshot.future;
      final during = await f.repo.load(user, store);
      f.server.releaseSecondSnapshot.complete();
      await sync;
      final after = await f.repo.load(user, store);
      expect(during!.list('lots').single['sellable'], 2);
      expect(during.list('lots').single['version'], 2);
      expect(after!.list('lots').single['sellable'], 2);
      expect(after.list('lots').single['version'], 2);
      expect(await f.repo.pendingCount(user.id), 0);
      expect(f.server.applied, 1);
    },
  );

  test(
    'workspace reads cache and provisional effects from one local state',
    () async {
      final f = Fixture();
      addTearDown(f.db.close);
      await f.repo.refresh(user, store);
      await f.receive();
      f.server.gateSnapshots = true;
      final sync = f.repo.synchronize(user, store);
      await f.server.firstSnapshot.future;
      f.repo.pauseNextRead = true;
      final reading = f.repo.load(user, store);
      await f.repo.readingOutbox.future;
      f.server.releaseFirstSnapshot.complete();
      // Installation either completes, or waits for the reader's transaction.
      await sync.timeout(const Duration(milliseconds: 200), onTimeout: () {});
      f.repo.releaseRead.complete();
      final during = await reading;
      await sync;
      final after = await f.repo.load(user, store);
      expect(during!.list('lots').single['sellable'], 2);
      expect(during.list('lots').single['version'], 2);
      expect(after!.list('lots').single['sellable'], 2);
      expect(await f.repo.pendingCount(user.id), 0);
    },
  );
}
