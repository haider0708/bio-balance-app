import 'dart:async';
import 'dart:convert';

import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/synchronization/sync_summary.dart';
import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/features/synchronization/sync_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'offline_test.dart' show FakeServer, user, store;
import 'ui_test.dart' show screenshot;

final otherStore = Store.fromJson({
  'id': 'store-b',
  'organizationId': 'org-a',
  'organizationName': 'Parahouse',
  'name': 'Magasin Sousse',
  'permissions': ['sell', 'receive'],
});

class GatedServer extends FakeServer {
  final started = Completer<void>(), release = Completer<void>();
  int pushes = 0;
  bool invalidReply = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    if (options.path == '/v1/sync/push') {
      pushes++;
      if (!started.isCompleted) started.complete();
      await release.future;
      if (invalidReply) {
        return ResponseBody.fromString(
          jsonEncode({'results': []}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
    }
    return super.fetch(options, body, cancel);
  }
}

class Fixture {
  final db = AppDatabase(NativeDatabase.memory());
  final FakeServer server;
  late final api = ApiClient(
    baseUrl: 'http://test',
    dio: Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
  )..authenticate('token', accountId: user.id);
  late final repo = OfflineRepository(db, api);
  late final vm = WorkspaceViewModel(user, repo, api)
    ..state = WorkspaceState(stores: [store, otherStore], loading: false);
  Fixture([FakeServer? server]) : server = server ?? FakeServer();
  Future<void> enqueue(String id, Store target) => repo.enqueue(user, target, {
    'operationId': id,
    'storeId': target.id,
    'organizationId': target.organizationId,
    'payloadVersion': 2,
    'command': {
      'type': 'stock.receive',
      'reason': 'Test',
      'lines': [
        {'productId': 'p', 'batch': id, 'expiry': '2029-12-31', 'quantity': 2},
      ],
    },
  }, {});
  Future<void> close() async {
    vm.dispose();
    await db.close();
  }
}

class SnapshotGateServer extends FakeServer {
  final started = Completer<void>(), release = Completer<void>();
  int snapshots = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    if (options.path.endsWith('/snapshot')) {
      snapshots++;
      if (snapshots == 1) {
        started.complete();
        await release.future;
      }
    }
    return super.fetch(options, body, cancel);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });
  for (final active in [false, true]) {
    test(
      'pending work in another store synchronizes from ${active ? 'a store' : 'the network'}',
      () async {
        final f = Fixture();
        addTearDown(f.close);
        await f.enqueue('elsewhere', otherStore);
        if (active) await f.vm.select(store, refresh: false);
        await f.vm.synchronize();
        expect(f.server.accepted, contains('elsewhere'));
        expect(await f.repo.pendingCount(user.id), 0);
        expect(f.vm.state.store?.id, active ? store.id : null);
        expect(f.vm.state.syncError, isNull);
      },
    );
  }
  test('overlapping snapshot reads install in order', () async {
    final server = SnapshotGateServer();
    final g = Fixture(server);
    addTearDown(g.close);
    final first = g.repo.refresh(user, store);
    await server.started.future;
    final second = g.repo.refresh(user, store);
    await Future<void>.delayed(Duration.zero);
    expect(server.snapshots, 1);
    server.release.complete();
    await Future.wait([first, second]);
    expect(server.snapshots, 2);
  });
  test(
    'bounded account passes eventually drain more than eight stores',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      final stores = List.generate(
        11,
        (i) => Store.fromJson({...store.toJson(), 'id': 'store-$i'}),
      );
      f.vm.state = WorkspaceState(stores: stores);
      for (var i = 0; i < stores.length; i++) {
        await f.enqueue('op-$i', stores[i]);
      }
      await f.vm.synchronize();
      expect(await f.repo.pendingCount(user.id), 3);
      await f.vm.synchronize();
      expect(await f.repo.pendingCount(user.id), 0);
      expect(f.vm.state.store, isNull);
    },
  );
  test('concurrent sync callers await the same work, including after scope changes', () async {
    final server = GatedServer();
    final g = Fixture(server);
    addTearDown(g.close);
    await g.enqueue('once', otherStore);
    final first = g.vm.synchronize();
    await server.started.future;
    g.vm.releaseStore();
    var finished = false;
    final second = g.vm.synchronize().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, false);
    expect(g.vm.state.syncing, true);
    server.release.complete();
    await Future.wait([first, second]);
    expect(server.pushes, 1);
    expect(await g.repo.pendingCount(user.id), 0);
  });
  test('repository single flight awaits a real acknowledgment rather than returning early', () async {
    final server = GatedServer();
    final g = Fixture(server);
    addTearDown(g.close);
    await g.enqueue('once', store);
    final first = g.repo.synchronize(user, store);
    await server.started.future;
    var finished = false;
    final second = g.repo.synchronize(user, store).then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, false);
    server.release.complete();
    await Future.wait([first, second]);
    expect(server.pushes, 1);
  });
  test(
    'a conflict does not prevent another store from synchronizing',
    () async {
      final f = Fixture(FakeServer()..conflicts.add('conflict'));
      addTearDown(f.close);
      await f.enqueue('conflict', store);
      await f.enqueue('other', otherStore);
      await f.vm.synchronize();
      final rows = await f.repo.accountOperations(user.id);
      expect(rows.single.operationId, 'conflict');
      expect(rows.single.status, 'conflict');
      expect(f.server.accepted, {'other'});
      final summary = await f.repo.watchSyncSummary(user.id).first;
      expect(summary.attention, 1);
      expect(summary.label, '1 à vérifier');
    },
  );
  test('failure publishes persisted retry and preserves payload; lost response is reconciled', () async {
    final f = Fixture(FakeServer()..loseResponse = true);
    addTearDown(f.close);
    await f.enqueue('uncertain', otherStore);
    final payload = (await f.repo.accountOperations(user.id)).single.payload;
    await f.vm.synchronize(silent: true);
    final row = (await f.repo.accountOperations(user.id)).single;
    expect(row.status, 'retryable');
    expect(row.mayHaveBeenSent, true);
    expect(row.payload, payload);
    expect(row.nextAttemptAt, isNotNull);
    expect(f.vm.state.syncError, isNotNull);
    await f.vm.synchronize();
    expect(await f.repo.pendingCount(user.id), 0);
    expect(f.server.applied, 1);
  });
  test(
    'malformed acknowledgment remains uncertain and schedules recovery',
    () async {
      final server = GatedServer()..invalidReply = true;
      server.release.complete();
      final f = Fixture(server);
      addTearDown(f.close);
      await f.enqueue('invalid', otherStore);
      await f.vm.synchronize();
      final row = (await f.repo.accountOperations(user.id)).single;
      expect(row.status, 'retryable');
      expect(row.mayHaveBeenSent, true);
      expect(row.nextAttemptAt, isNotNull);
    },
  );
  test('work cannot cross account/session generations', () async {
    final f = Fixture();
    addTearDown(f.close);
    await f.enqueue('original-account', otherStore);
    f.api.authenticate('new-token', accountId: 'other-account');
    await f.vm.synchronize();
    expect(f.server.submissions, isEmpty);
    expect(await f.repo.pendingCount(user.id), 1);
    expect(await f.repo.pendingCount('other-account'), 0);
  });
  test(
    'summary separates acknowledgment, dependencies and retry from conflicts',
    () {
      const summary = SyncSummary(
        waiting: 2,
        retrying: 1,
        blocked: 2,
        attention: 1,
        confirming: 1,
      );
      expect(summary.total, 7);
      expect(summary.label, '1 à vérifier');
      expect(const SyncSummary(confirming: 1).label, contains('actualisation'));
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'sync page shows another store and live state at text scale $scale',
      (t) async {
        t.view.physicalSize = const Size(360, 850);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final f = Fixture();
        addTearDown(f.close);
        await t.runAsync(() => f.enqueue('elsewhere', otherStore));
        final capture = GlobalKey();
        await t.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: capture, child: child!),
            ),
            home: SyncScreen(vm: f.vm),
          ),
        );
        await t.pumpAndSettle();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.textContaining('Parahouse · Magasin Sousse'),
          150,
        );
        expect(find.text('Tout est synchronisé'), findsNothing);
        expect(t.takeException(), isNull);
        await t.runAsync(
          () => (f.db.update(f.db.outboxRows)).write(
            const OutboxRowsCompanion(
              status: Value('conflict'),
              error: Value('Cet élément a été modifié.'),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pumpAndSettle();
        await t.scrollUntilVisible(find.text('À vérifier'), 100);
        expect(find.text('À vérifier'), findsOneWidget);
        if (scale == 1) await screenshot(t, capture, 'sync-account-recovery');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
