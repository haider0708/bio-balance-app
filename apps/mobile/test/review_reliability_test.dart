import 'dart:async';
import 'dart:convert';

import 'package:biobalance/data/repositories/online_operations_repository.dart';
import 'package:biobalance/data/repositories/repository_context.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/ranking.dart';
import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/core/form_draft.dart';
import 'package:biobalance/ui/core/forms.dart';
import 'package:biobalance/ui/features/authentication/session_view_model.dart';
import 'package:biobalance/ui/features/rewards/ranking_view_model.dart';
import 'package:biobalance/ui/features/training/training_editor_view_model.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_test.dart' as fixtures;
import 'support/test_origin.dart';

import 'package:biobalance/ui/features/synchronization/sync_screen.dart';

class DraftStore extends fixtures.MemoryDraftRepository {
  DraftStore(super.db, super.api);
  Completer<void>? gate;
  bool failReads = false;
  int writes = 0;
  List<OutboxRow> operationsToShow = [];
  @override
  Future<List<OutboxRow>> operations(
    String accountId,
    String storeId, {
    bool includeResolved = false,
  }) async => operationsToShow;
  @override
  Future<Json?> draft(String accountId, String storeId, String key) async {
    if (failReads) throw StateError('Storage read failed');
    return super.draft(accountId, storeId, key);
  }

  @override
  Future<void> saveDraft(
    String accountId,
    String storeId,
    String key,
    Json value,
  ) async {
    writes++;
    await gate?.future;
    return super.saveDraft(accountId, storeId, key, value);
  }
}

class CommandServer implements HttpClientAdapter {
  final release = Completer<void>(), started = Completer<void>();
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    calls++;
    if (!started.isCompleted) started.complete();
    await release.future;
    final command = (options.data['operations'] as List).single;
    return fixtures.jsonBody({
      'results': [
        {
          'operationId': command['operationId'],
          'status': 'accepted',
          'committedCursor': '1',
          'affectedVersions': [],
          'data': {'id': command['operationId']},
        },
      ],
    });
  }

  @override
  void close({bool force = false}) {}
}

class ReviewWorkspace extends WorkspaceViewModel {
  ReviewWorkspace(super.user, super.repository, super.api);
  void publishSync() {
    state = state.copy(pending: 0, syncedAt: DateTime.now());
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
  });
  late AppDatabase db;
  late ApiClient api;
  late DraftStore local;
  late ReviewWorkspace workspace;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = ApiClient(baseUrl: 'http://test')
      ..authenticate('token', accountId: 'a');
    local = DraftStore(db, api);
    workspace = ReviewWorkspace(fixtures.user, local, api);
    workspace.state = WorkspaceState(
      stores: [fixtures.store],
      store: fixtures.store,
    );
  });
  tearDown(() async {
    workspace.dispose();
    api.http.close();
    await db.close();
  });

  test(
    'rapid typing coalesces writes and persists the newest edit before exit',
    () async {
      local.gate = Completer<void>();
      final draft = FormDraftController(workspace, fixtures.store, 'edit', {});
      final first = draft.change({'name': 'first'});
      await Future<void>.delayed(Duration.zero);
      final updates = [
        for (var i = 0; i < 100; i++) draft.change({'name': '$i'}),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(local.writes, 1);
      local.gate!.complete();
      await Future.wait([first, ...updates]);
      await workspace.flushDrafts();
      expect(local.writes, 2);
      expect(local.saved['a:store:edit']!['values']['name'], '99');
      draft.dispose();
    },
  );

  test(
    'failed draft read cannot be overwritten by an access or lifecycle flush',
    () async {
      local.saved['a:store:edit'] = {
        'values': {'name': 'existing'},
      };
      local.failReads = true;
      final draft = FormDraftController(workspace, fixtures.store, 'edit', {
        'name': '',
      });
      await expectLater(draft.restore(), throwsStateError);
      await expectLater(workspace.flushDrafts(), throwsStateError);
      expect(local.writes, 0);
      local.failReads = false;
      expect((await draft.restore())!['name'], 'existing');
      await workspace.flushDrafts();
      expect(local.writes, 0);
      draft.dispose();
    },
  );

  test('failed draft write retries the latest values without restoring stale edits', () async {
    final draft = FormDraftController(workspace, fixtures.store, 'edit', {});
    local.failWrites = true;
    await expectLater(
      draft.change({'name': 'keep'}),
      throwsA(isA<AppFailure>()),
    );
    local.failWrites = false;
    await draft.flush();
    expect(local.saved['a:store:edit']!['values']['name'], 'keep');
    draft.dispose();
  });

  testWidgets(
    'editor blocks editing after failed recovery and restores on retry',
    (t) async {
      local.saved['a:store:edit'] = {
        'values': {'name': 'Saved value'},
      };
      local.failReads = true;
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: EditorScreen(
            workspace: workspace,
            draftKey: 'edit',
            title: 'Test',
            fields: const [FieldSpec('name', 'Nom')],
            submit: (_) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t.widget<TextFormField>(find.byType(TextFormField)).enabled,
        false,
      );
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('editor.save')))
            .onPressed,
        isNull,
      );
      expect(local.writes, 0);
      local.failReads = false;
      await t.tap(find.text('Réessayer de récupérer le brouillon'));
      await t.pumpAndSettle();
      expect(
        t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
        'Saved value',
      );
      expect(t.widget<TextFormField>(find.byType(TextFormField)).enabled, true);
      await t.pumpWidget(const SizedBox());
    },
  );

  test(
    'training cannot save or change a draft before successful recovery',
    () async {
      local.failReads = true;
      final editor = TrainingEditorViewModel(workspace, null);
      expect(await editor.restore(), false);
      editor.change({'title': 'Overwrite'});
      expect(await editor.save(), false);
      expect(local.writes, 0);
      local.failReads = false;
      expect(await editor.restore(), true);
      editor.change({'title': 'Recovered'});
      await editor.draft.flush();
      expect(editor.state.value('title'), 'Recovered');
      editor.dispose();
    },
  );

  test('concurrent reward requests share one durable command', () async {
    final server = CommandServer();
    api.http.httpClientAdapter = server;
    final repo = OnlineOperationsRepository(
      RepositoryContext(api),
      local,
      fixtures.user,
    );
    final first = repo.submit(fixtures.store, {
      'type': 'reward.request',
      'rewardId': 'reward',
      'claimId': 'one',
    });
    await server.started.future;
    final second = repo.submit(fixtures.store, {
      'type': 'reward.request',
      'rewardId': 'reward',
      'claimId': 'two',
    });
    server.release.complete();
    await Future.wait([first, second]);
    expect(server.calls, 1);
    expect(local.saved['a:store:online:reward.request:reward'], isEmpty);
  });

  test(
    'logout failure preserves the account and reports failure to navigation',
    () async {
      fixtures.savedSession();
      final session = SessionViewModel(api, const FlutterSecureStorage());
      await session.restore();
      final unregister = session.registerExitGuard(
        () async => throw StateError('No space'),
      );
      expect(await session.logout(), false);
      expect(session.state.user!.id, 'a');
      expect(api.accountId, 'a');
      expect(
        await const FlutterSecureStorage().read(key: 'session'),
        isNotNull,
      );
      unregister();
      session.dispose();
    },
  );

  test('late logout cannot disconnect a newer successful login', () async {
    fixtures.savedSession();
    final server = fixtures.DeferredServer();
    api.http.httpClientAdapter = server;
    final session = SessionViewModel(api, const FlutterSecureStorage());
    await session.restore();
    final guard = Completer<void>();
    session.registerExitGuard(() => guard.future);
    final logout = session.logout();
    final login = session.login('b@example.test', 'password', '');
    await server.started.future;
    server.response.complete(
      fixtures.jsonBody({
        'token': 'new',
        'expiresAt': '2099-01-01T00:00:00Z',
        'user': {
          'id': 'b',
          'name': 'New',
          'email': 'b@example.test',
          'platformAdmin': false,
        },
      }),
    );
    expect(await login, true);
    guard.complete();
    expect(await logout, false);
    expect(api.accountId, 'b');
    expect(
      jsonDecode(
        (await const FlutterSecureStorage().read(key: 'session'))!,
      )['token'],
      'new',
    );
    session.dispose();
  });

  test('ranking refresh failure retains last data and dispose rejects late results', () async {
    final result = Completer<StoreRanking>();
    var call = 0;
    final vm = RankingViewModel(() async {
      if (++call == 1) {
        return StoreRanking('2026-09', [
          const RankingScore('a', 'Alice', 12, 1),
        ]);
      }
      if (call == 2) throw StateError('offline');
      return result.future;
    });
    await vm.refresh();
    await vm.refresh();
    expect(vm.state.value!.scores.single.points, 12);
    expect(vm.state.error, isNotNull);
    final pending = vm.refresh();
    vm.dispose();
    result.complete(StoreRanking('2026-09', []));
    await pending;
  });

  testWidgets(
    'reduced motion finishes navigation immediately and empty metrics are safe',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const PageEntrance(child: MetricStrip(metrics: [])),
          ),
        ),
      );
      expect(
        t
            .widget<FadeTransition>(find.byType(FadeTransition).last)
            .opacity
            .value,
        1,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  test(
    'real-network test origins reject credential-bearing URLs and remote HTTP',
    () {
      for (final url in [
        'http://example.com',
        'https://name:secret@example.com',
        'https://example.com/path',
        'https://example.com?token=secret',
      ]) {
        expect(() => testOptions(url), throwsFormatException);
      }
      expect(testOptions('http://127.0.0.1:3187').followRedirects, false);
      expect(testOptions('http://10.0.2.2:3187').maxRedirects, 0);
      expect(testOptions('https://example.test').followRedirects, false);
    },
  );
  testWidgets(
    'sync history builds lazily and reflects background acknowledgments',
    (t) async {
      local.operationsToShow = List.generate(
        500,
        (i) => OutboxRow(
          sequence: i,
          operationId: 'op-$i',
          accountId: 'a',
          storeId: 'store',
          payload: jsonEncode({
            'command': {'type': 'sale.create'},
          }),
          effect: '{}',
          dependencies: '[]',
          records: '[]',
          mayHaveBeenSent: false,
          status: 'pending',
          attempts: 0,
          createdAt: DateTime(2026, 9, 22),
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: SyncScreen(vm: workspace),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(CompactRow).evaluate().length, lessThan(20));
      local.operationsToShow = [];
      workspace.publishSync();
      await t.pumpAndSettle();
      expect(find.text('Tout est synchronisé'), findsOneWidget);
      expect(find.byType(CompactRow), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'three short dashboard metrics stay on one readable row at 360 dp',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: const Scaffold(
            body: SizedBox(
              width: 328,
              child: MetricStrip(
                metrics: [
                  (label: 'Ventes', value: '8'),
                  (label: 'Montant TND', value: '399,200'),
                  (label: 'Points', value: '200'),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        t.getTopLeft(find.text('200')).dy,
        t.getTopLeft(find.text('8')).dy,
      );
      expect(t.getSize(find.text('399,200')).height, lessThan(40));
      expect(t.takeException(), isNull);
    },
  );

  test('brand actions retain readable dark text contrast', () {
    final ratio =
        (brandGreen.computeLuminance() + .05) / (ink.computeLuminance() + .05);
    expect(ratio, greaterThanOrEqualTo(4.5));
  });
}
