import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/api/generated/models.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/workspace_scope.dart';
import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/features/workspace/scope_screen.dart';
import 'package:biobalance/ui/features/workspace/scope_view_model.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_test.dart' show MemoryDraftRepository;

import 'package:biobalance/data/repositories/offline_repository.dart';

import 'ui_test.dart' show screenshot;

class ScopeApi extends ApiClient {
  bool offlineGroups = false;
  @override
  Future<GroupListResponseDto> groupList({String? after, String? search}) {
    if (offlineGroups) {
      throw DioException(
        requestOptions: RequestOptions(path: '/v1/groups'),
        type: DioExceptionType.connectionError,
      );
    }
    return super.groupList(after: after, search: search);
  }

  ScopeApi() : super(baseUrl: 'http://unused') {
    authenticate('preview', accountId: 'preview');
  }
  @override
  Future<DashboardGetResponseDto> dashboardGet({
    required String scope,
    required String from,
    required String to,
    String? organizationId,
    String? storeId,
  }) async => DashboardGetResponseDto.fromJson({
    'scope': scope,
    'organizationId': organizationId,
    'storeId': storeId,
    'from': from,
    'to': to,
    'generatedAt': '2026-09-23T10:45:00Z',
    'netMillimes': '1842350',
    'netUnits': '42',
    'saleCount': '27',
    'recentSales': [],
    'ranking': null,
    'groupCount': 2,
    'storeCount': 3,
    'series': [
      {
        'day': from,
        'netMillimes': '542300',
        'netUnits': '12',
        'saleCount': '8',
      },
      {
        'day': to,
        'netMillimes': '1300050',
        'netUnits': '30',
        'saleCount': '19',
      },
    ],
    'comparisons': scope == 'network'
        ? [
            {
              'id': 'g1',
              'name': 'Parahouse',
              'netMillimes': '1442350',
              'netUnits': '32',
              'saleCount': '20',
            },
            {
              'id': 'g2',
              'name': 'Santé Verte',
              'netMillimes': '400000',
              'netUnits': '10',
              'saleCount': '7',
            },
          ]
        : [],
    'products': [
      {
        'id': 'p',
        'name': 'Sérum PDRN 30 ml',
        'imageId': null,
        'netUnits': '18',
        'netMillimes': '1098000',
      },
    ],
    'current': {
      'pendingOrders': 3,
      'pendingDeliveries': 2,
      'pendingClaims': 1,
      'expiredLots': 0,
      'expiringLots': 2,
      'lowStock': 4,
      'availablePoints': scope == 'personal' ? '240' : null,
      'reservedPoints': scope == 'personal' ? '40' : null,
    },
    'alerts': [],
  });
}

class ScopeWorkspace extends WorkspaceViewModel {
  ScopeWorkspace(super.user, super.repository, super.api);
  @override
  Future<void> initialize({bool autoSelect = true}) async {}
  @override
  Future<void> select(Store store, {bool refresh = true}) async {
    state = state.copy(
      store: store,
      loading: false,
      data: StoreData({
        'store': store.toJson(),
        'onboarding': {'complete': true},
        'products': [],
        'lots': [],
        'config': [],
      }),
    );
    notifyListeners();
  }
}

class ScopeFixture {
  final db = AppDatabase(NativeDatabase.memory());
  final api = ScopeApi();
  late final local = MemoryDraftRepository(db, api);
  late final workspace = ScopeWorkspace(
    UserAccount(
      id: 'preview',
      name: 'Haydar',
      email: 'preview@example.test',
      admin: admin,
    ),
    local,
    api,
  );
  late final scope = ScopeViewModel(workspace);
  final bool admin;
  ScopeFixture({this.admin = true}) {
    scope.groups = const [
      PartnerGroup(id: 'g1', name: 'Parahouse', canManage: true, storeCount: 3),
      PartnerGroup(
        id: 'g2',
        name: 'Santé Verte',
        canManage: true,
        storeCount: 1,
      ),
    ];
    workspace.state = WorkspaceState(
      stores: [
        for (final entry in [
          ('s1', 'g1', 'Parahouse', 'Magasin Tunis'),
          ('s2', 'g1', 'Parahouse', 'Magasin Sousse'),
          ('s3', 'g1', 'Parahouse', 'Magasin Sfax'),
          ('s4', 'g2', 'Santé Verte', 'Magasin Bizerte'),
        ])
          Store.fromJson({
            'id': entry.$1,
            'organizationId': entry.$2,
            'organizationName': entry.$3,
            'name': entry.$4,
            'permissions': ['manage', 'sell', 'receive'],
            'city': 'Tunisie',
            'onboardingStep': 5,
          }),
      ],
    );
    scope.loading = false;
  }
  Widget app({double scale = 1, GlobalKey? capture}) =>
      ChangeNotifierProvider<WorkspaceViewModel>.value(
        value: workspace,
        child: MaterialApp(
          theme: appTheme(),
          locale: const Locale('fr', 'TN'),
          supportedLocales: const [Locale('fr', 'TN')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: capture, child: child!),
          ),
          home: ScopeScreen(model: scope),
        ),
      );
  Future<void> close() async {
    workspace.dispose();
    await db.close();
  }
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await loader.load();
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
  });
  test(
    'dashboard cache eviction preserves other accounts and business drafts',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final api = ScopeApi();
      final repo = OfflineRepository(db, api);
      await repo.saveDraft('a', 'store', 'sale', {'quantity': 3});
      await repo.saveDraft('b', '', 'dashboard:old', {
        'generatedAt': '2020-01-01',
      });
      for (var i = 0; i < 60; i++) {
        await repo.saveDashboard('a', 'dashboard:$i', {
          'generatedAt': DateTime.utc(
            2026,
            1,
            1,
          ).add(Duration(minutes: i)).toIso8601String(),
        });
      }
      expect(
        (await db.select(db.draftRows).get())
            .where((r) => r.accountId == 'a' && r.key.startsWith('dashboard:'))
            .length,
        48,
      );
      expect(await repo.draft('a', 'store', 'sale'), {'quantity': 3});
      expect(await repo.draft('b', '', 'dashboard:old'), isNotNull);
      expect(await repo.draft('a', '', 'dashboard:59'), isNotNull);
      expect(await repo.draft('a', '', 'dashboard:0'), isNull);
    },
  );
  test(
    'group/store switching preserves drafts and forbids cross-group stores',
    () async {
      final f = ScopeFixture();
      addTearDown(f.close);
      await f.scope.selectGroup(f.scope.groups.first);
      await f.scope.selectStore(f.workspace.state.stores.first);
      final saved = f.workspace.registerDraft(() async {
        throw const AppFailure('STORAGE_FULL', 'Libérez de l’espace.');
      });
      await expectLater(
        f.scope.selectGroup(f.scope.groups.last),
        throwsA(isA<AppFailure>()),
      );
      expect(f.scope.scope.store?.id, 's1');
      expect(f.workspace.state.store?.id, 's1');
      saved();
      await expectLater(
        f.scope.selectStore(f.workspace.state.stores.last),
        throwsA(isA<AppFailure>()),
      );
      await f.scope.selectGroup(f.scope.groups.last);
      expect(f.scope.scope.store, isNull);
      expect(f.workspace.state.store, isNull);
      expect(f.scope.stores.single.id, 's4');
      f.scope.dispose();
    },
  );
  test('old offline store cache preserves access without inventing group authority', () async {
    final f = ScopeFixture();
    addTearDown(f.close);
    f.api.offlineGroups = true;
    final cachedWorkspace = ScopeWorkspace(
      const UserAccount(
        id: 'preview',
        name: 'Test',
        email: 'test@example.test',
        admin: false,
      ),
      f.local,
      f.api,
    )..state = f.workspace.state;
    final vm = ScopeViewModel(cachedWorkspace);
    await vm.initialize();
    expect(vm.groups.map((g) => g.id).toSet(), {'g1', 'g2'});
    expect(vm.groups.every((g) => !g.canManage), isTrue);
    await vm.selectGroup(vm.groups.first);
    expect(vm.scope.store?.id, 's1');
    await vm.revoke('g2');
    await vm.refresh();
    expect(vm.groups.any((g) => g.id == 'g2'), isFalse);
    vm.dispose();
    cachedWorkspace.dispose();
    f.scope.dispose();
  });
  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('scoped navigation at $size / text $scale', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final f = ScopeFixture(), capture = GlobalKey();
        addTearDown(f.close);
        await t.pumpWidget(f.app(scale: scale, capture: capture));
        await t.pumpAndSettle();
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await t.pumpAndSettle();
        expect(find.textContaining('Tous les groupes'), findsWidgets);
        expect(f.workspace.state.store, isNull);
        expect(t.takeException(), isNull);
        if (size.width == 360 && scale == 1) {
          await screenshot(t, capture, 'redesign-network');
        }
        await t.tap(find.byKey(const ValueKey('scope.group')));
        await t.pumpAndSettle();
        await selectFromSheet(t, 'Parahouse');
        await t.pumpAndSettle();
        expect(f.scope.scope.group?.id, 'g1');
        expect(f.workspace.state.store, isNull);
        if (size.width == 360 && scale == 1) {
          await screenshot(t, capture, 'redesign-group');
        }
        await t.tap(find.byKey(const ValueKey('scope.store')));
        await t.pumpAndSettle();
        expect(find.text('Magasin Bizerte'), findsNothing);
        await selectFromSheet(t, 'Magasin Tunis');
        await t.pumpAndSettle();
        expect(f.workspace.state.store?.id, 's1');
        expect(t.takeException(), isNull);
        if (size.width == 360 && scale == 1) {
          await screenshot(t, capture, 'redesign-store');
        }
        await t.tap(find.byKey(const ValueKey('scope.group')));
        await t.pumpAndSettle();
        await selectFromSheet(t, 'Santé Verte');
        await t.pumpAndSettle();
        expect(f.workspace.state.store, isNull);
        expect(f.scope.scope.group?.id, 'g2');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}

Future<void> selectFromSheet(WidgetTester t, String label) async {
  final sheet = find.byType(BottomSheet);
  final target = find.descendant(of: sheet, matching: find.text(label));
  await t.scrollUntilVisible(
    target,
    120,
    scrollable: find
        .descendant(of: sheet, matching: find.byType(Scrollable))
        .first,
  );
  await t.pumpAndSettle();
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
}
