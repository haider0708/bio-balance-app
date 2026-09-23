import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/api/session_transport.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/data/services/notifications/push_notifications.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/core/forms.dart';
import 'package:biobalance/ui/features/authentication/session_view_model.dart';
import 'package:biobalance/ui/features/workspace/workspace_navigator.dart';
import 'package:biobalance/ui/features/workspace/scope_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const user = UserAccount(
  id: 'a',
  name: 'Test',
  email: 'a@example.test',
  admin: false,
);
final store = Store.fromJson({
  'id': 'store',
  'organizationId': 'org',
  'name': 'Store',
  'permissions': ['manage', 'sell', 'receive'],
});
ResponseBody jsonBody(Object value, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
void savedSession() => FlutterSecureStorage.setMockInitialValues({
  'session': jsonEncode({
    'token': 'old',
    'user': {
      'id': 'a',
      'name': 'Test',
      'email': 'a@example.test',
      'platformAdmin': false,
    },
    'expiresAt': '2099-01-01T00:00:00Z',
  }),
});

class DeferredServer implements HttpClientAdapter {
  final started = Completer<void>(), response = Completer<ResponseBody>();
  String? authorization;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) {
    authorization = options.headers['Authorization'];
    if (!started.isCompleted) started.complete();
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

class DeferredPush extends PushNotifications {
  final finished = Completer<void>();
  DeferredPush(super.api);
  @override
  Future<void> resume() async {}
  @override
  Future<void> unbind() => finished.future;
}

class MemoryDraftRepository extends OfflineRepository {
  final saved = <String, Json>{};
  bool failWrites = false;
  MemoryDraftRepository(super.db, super.api);
  @override
  Future<void> saveDraft(
    String accountId,
    String storeId,
    String key,
    Json value,
  ) async {
    if (failWrites) throw const AppFailure('STORAGE_FULL', 'Storage full');
    saved['$accountId:$storeId:$key'] = value;
  }

  @override
  Future<Json?> draft(String accountId, String storeId, String key) async =>
      saved['$accountId:$storeId:$key'];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final nextAccount in ['a', 'b']) {
    test(
      'late cache response is rejected after a new session for $nextAccount',
      () async {
        final server = DeferredServer(),
            db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final api = ApiClient(
          baseUrl: 'http://test',
          dio: Dio(BaseOptions(baseUrl: 'http://test'))
            ..httpClientAdapter = server,
        )..authenticate('old', accountId: 'a');
        final repo = OfflineRepository(db, api);
        final request = repo.refresh(user, store);
        final rejected = expectLater(request, throwsA(isA<AppFailure>()));
        await server.started.future;
        api.authenticate('new', accountId: nextAccount);
        server.response.complete(
          jsonBody({
            'syncProtocol': 3,
            'cursor': '0',
            'lots': [],
            'permissions': ['manage'],
          }),
        );
        await rejected;
        expect(server.authorization, 'Bearer old');
        expect(await db.select(db.cacheEntries).get(), isEmpty);
      },
    );
  }
  test(
    'logout saves drafts and never waits for network or push cleanup',
    () async {
      savedSession();
      final server = DeferredServer();
      final api = ApiClient(
        baseUrl: 'http://test',
        dio: Dio(BaseOptions(baseUrl: 'http://test'))
          ..httpClientAdapter = server,
      );
      final push = DeferredPush(api);
      final session = SessionViewModel(
        api,
        const FlutterSecureStorage(),
        notifications: push,
      );
      addTearDown(session.dispose);
      await session.restore();
      var saved = false;
      session.registerExitGuard(() async {
        saved = true;
      });
      await session.logout().timeout(const Duration(seconds: 1));
      expect(saved, isTrue);
      expect(session.state.status, SessionStatus.signedOut);
      expect(api.accountId, isNull);
      expect(await const FlutterSecureStorage().read(key: 'session'), isNull);
      await server.started.future;
      api.authenticate('new', accountId: 'b');
      server.response.complete(jsonBody({'ok': true}));
      push.finished.complete();
      expect(api.accountId, 'b');
      expect(server.authorization, 'Bearer old');
    },
  );
  test(
    'known revoked access survives selection and preserves original outbox',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final api = ApiClient(baseUrl: 'http://test')
        ..authenticate('token', accountId: 'a');
      final repo = OfflineRepository(db, api),
          vm = WorkspaceViewModel(user, OfflineRepository(db, api), api);
      addTearDown(vm.dispose);
      vm.state = WorkspaceState(
        stores: [store],
        store: store,
        data: StoreData({'lots': [], 'products': []}),
      );
      await repo.enqueue(user, store, {
        'operationId': 'op',
        'storeId': store.id,
        'organizationId': store.organizationId,
        'command': {},
      }, {});
      await vm.denyAccess(store.id);
      await vm.select(store, refresh: false);
      expect(vm.state.accessBlocked, isTrue);
      expect(() => vm.requireAccess(store, 'sell'), throwsA(isA<AppFailure>()));
      expect((await repo.operations('a', store.id)).single.operationId, 'op');
      expect((await repo.draft('a', '', 'access'))!['revokedStores'], [
        store.id,
      ]);
      api.authenticate('other', accountId: 'b');
      expect(() => vm.requireAccess(store), throwsA(isA<AppFailure>()));
      expect(await repo.operations('b', store.id), isEmpty);
    },
  );
  testWidgets(
    'access loss saves the editor before replacing protected routes',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final api = ApiClient(baseUrl: 'http://test')
        ..authenticate('token', accountId: 'a');
      final repository = MemoryDraftRepository(db, api);
      final vm = WorkspaceViewModel(user, repository, api);
      final session = SessionViewModel(api, const FlutterSecureStorage());
      vm.state = WorkspaceState(
        stores: [store],
        store: store,
        data: StoreData({
          'store': {'onboardingStep': 5},
          'lots': [],
          'products': [],
          'points': {'balance': '0', 'reserved': '0'},
        }),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: vm),
            ChangeNotifierProvider.value(value: session),
          ],
          child: const MaterialApp(home: WorkspaceNavigator()),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        openEditor(
          tester.element(find.byType(ScopeScreen)),
          title: 'Réception de test',
          fields: [const FieldSpec('batch', 'Lot')],
          submit: (_) async {},
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'BATCH-KEEP');
      await tester.pump();
      repository.failWrites = true;
      await vm.denyAccess(store.id);
      await tester.pumpAndSettle();
      expect(vm.securingAccess, isTrue);
      expect(vm.accessRevision, 0);
      repository.failWrites = false;
      await vm.denyAccess(store.id);
      await tester.pumpAndSettle();
      expect(find.text('Votre accès doit être vérifié'), findsOneWidget);
      expect(find.text('Réception de test'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(
        repository.saved.values.any(
          (d) => jsonEncode(d).contains('BATCH-KEEP'),
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      session.dispose();
      await tester.pump(
        const Duration(milliseconds: 1),
      ); // Drain Drift's deferred stream cancellation.
    },
  );
  test('confirmed expiry prevents another protected request', () async {
    savedSession();
    final api = ApiClient(baseUrl: 'http://test');
    final session = SessionViewModel(api, const FlutterSecureStorage());
    addTearDown(session.dispose);
    await session.restore();
    api.confirmAccessLoss(AccessCondition.expired);
    expect(session.state.status, SessionStatus.expired);
    await expectLater(
      api.request('GET', '/v1/stores'),
      throwsA(isA<DioException>()),
    );
    expect(session.state.user!.id, 'a');
  });
  for (final condition in [AccessCondition.expired, AccessCondition.disabled]) {
    test(
      'confirmed ${condition.name} survives restart without replay or data loss',
      () async {
        savedSession();
        final api = ApiClient(baseUrl: 'http://test');
        final first = SessionViewModel(api, const FlutterSecureStorage());
        await first.restore();
        api.confirmAccessLoss(condition);
        await first.flushAccessState();
        first.dispose();
        final restartedApi = ApiClient(baseUrl: 'http://test');
        final restarted = SessionViewModel(
          restartedApi,
          const FlutterSecureStorage(),
        );
        addTearDown(restarted.dispose);
        await restarted.restore();
        expect(restartedApi.accessBlocked, isTrue);
        expect(restarted.state.status.name, condition.name);
        expect(restarted.state.user!.id, 'a');
        await expectLater(
          restartedApi.request('GET', '/v1/stores'),
          throwsA(isA<DioException>()),
        );
      },
    );
  }
  test('known store revocation revalidates with a read before submitting queued work', () async {
    final server = DeferredServer();
    final api = ApiClient(
      baseUrl: 'http://test',
      dio: Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
    )..authenticate('old', accountId: 'a');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = OfflineRepository(db, api);
    await repo.saveDraft('a', '', 'access', {
      'revokedStores': ['store'],
    });
    final pending = repo.synchronize(user, store);
    final failure = expectLater(pending, throwsA(isA<AppFailure>()));
    await server.started.future;
    server.response.complete(jsonBody([]));
    await failure;
    expect(await repo.draft('a', '', 'access'), {
      'revokedStores': ['store'],
    });
    await expectLater(
      repo.enqueue(user, store, {
        'storeId': 'store',
        'organizationId': 'org',
      }, {}),
      throwsA(isA<AppFailure>()),
    );
  });
}
