import 'dart:io';
import 'dart:ui' as ui;

import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/api/generated/models.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/synchronization/sync_summary.dart';
import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/core/forms.dart';
import 'package:biobalance/ui/features/workspace/scope_view_model.dart';
import 'package:biobalance/domain/models/workspace_scope.dart';
import 'package:biobalance/ui/features/catalog/catalog_screen.dart';
import 'package:biobalance/ui/features/team/team_screen.dart';
import 'package:biobalance/ui/features/stores/product_settings_screen.dart';
import 'package:biobalance/ui/features/workspace/scope_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class PreviewApi extends ApiClient {
  PreviewApi() : super(baseUrl: 'http://unused') {
    authenticate('preview', accountId: 'user');
  }
  @override
  Future<NotificationsInboxResponseDto> notificationsInbox({
    String? cursor,
  }) async => NotificationsInboxResponseDto.fromJson({
    'items': [],
    'unreadCount': 0,
    'nextCursor': null,
    'accessKey': 'preview',
  });
  Json Function()? team;
  @override
  Future<GroupTeamResponseDto> groupTeam({required String id}) async =>
      GroupTeamResponseDto.fromJson(
        team?.call() ?? {'members': [], 'invitations': []},
      );
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
    'generatedAt': '2026-09-23T10:00:00Z',
    'netMillimes': '498000',
    'netUnits': '12',
    'saleCount': '8',
    'recentSales': [],
    'ranking': null,
    'groupCount': 1,
    'storeCount': 1,
    'series': [],
    'comparisons': [],
    'products': [],
    'current': {
      'pendingOrders': 0,
      'pendingDeliveries': 0,
      'pendingClaims': 0,
      'expiredLots': 0,
      'expiringLots': 0,
      'lowStock': 1,
      'availablePoints': scope == 'personal' ? '120' : null,
      'reservedPoints': scope == 'personal' ? '20' : null,
    },
    'alerts': [],
  });
}

class PreviewWorkspace extends WorkspaceViewModel {
  PreviewWorkspace(super.user, super.repository, super.api);
  void replace(StoreData data) {
    state = state.copy(data: data);
    notifyListeners();
  }
}

/// Visual fixtures are static; live SQLite changes have their own recovery
/// tests. Do not start a background queue watcher for every screenshot.
class PreviewRepository extends OfflineRepository {
  PreviewRepository(super.db, super.api);
  @override
  Stream<SyncSummary> watchSyncSummary(String account) => const Stream.empty();
}

class RoleFixture {
  final db = AppDatabase(NativeDatabase.memory());
  final api = PreviewApi();
  late final vm = PreviewWorkspace(
    UserAccount(
      id: 'user',
      name: 'Amira',
      email: 'demo@example.test',
      admin: role == 'admin',
    ),
    PreviewRepository(db, api),
    api,
  );
  final String role;
  RoleFixture(this.role) {
    addTearDown(close);
    api.team = () => {
      'members': [],
      'invitations': [
        for (final item in vm.state.data?.list('invitations') ?? <Json>[])
          {
            ...item,
            'kind': 'salesperson',
            'storeIds': ['store'],
            'storeId': null,
            'expiresAt': '2027-01-01T00:00:00Z',
          },
      ],
    };
    final store = Store.fromJson({
      'id': 'store',
      'organizationId': 'org',
      'organizationName': 'Partenaire Tunis',
      'name': 'BioBalance · Tunis',
      'city': 'Tunis',
      'permissions': role == 'manager'
          ? ['manage', 'sell', 'receive']
          : ['sell'],
    });
    vm.state = WorkspaceState(
      stores: [store],
      store: store,
      syncedAt: DateTime.now(),
      data: StoreData({
        'store': {'onboardingStep': 5},
        'onboarding': {'complete': true},
        'summary': {'saleCount': 8, 'totalMillimes': '399200'},
        'points': {'balance': '240', 'reserved': '40'},
        'products': [
          {
            'id': 'p',
            'name': 'Sérum PDRN',
            'reference': 'BIO-PDRN',
            'barcode': '6191234567890',
            'active': true,
          },
          {
            'id': 'q',
            'name': 'Crème hydratante',
            'reference': 'BIO-HYDRA',
            'active': true,
          },
        ],
        'config': [
          {
            'productId': 'p',
            'priceMillimes': '49900',
            'threshold': 5,
            'pointsPerUnit': 10,
            'pointsConfigured': true,
          },
        ],
        'lots': [
          {
            'id': 'lot',
            'productId': 'p',
            'batch': 'A2026',
            'expiry': '2028-12-31',
            'sellable': 4,
            'version': 2,
          },
        ],
        'alerts': [
          {
            'id': 'alert',
            'productId': 'p',
            'kind': 'low',
            'message': '4 unités disponibles · seuil de 5',
          },
        ],
        'sales': [],
      }),
    );
  }
  Widget home({bool storeView = false}) {
    final model = ScopeViewModel(vm);
    const group = PartnerGroup(
      id: 'org',
      name: 'Partenaire Tunis',
      canManage: true,
      storeCount: 1,
    );
    model.groups = [group];
    model.loading = false;
    model.scope = storeView || role == 'salesperson'
        ? WorkspaceScope.store(group, vm.state.store!)
        : role == 'admin'
        ? const WorkspaceScope.network()
        : const WorkspaceScope.group(group);
    return ScopeScreen(model: model);
  }

  Widget app(Widget child, {double scale = 1, GlobalKey? capture}) =>
      ChangeNotifierProvider<WorkspaceViewModel>.value(
        value: vm,
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
          home: child,
        ),
      );
  bool closed = false;
  Future<void> close() async {
    if (closed) return;
    closed = true;
    vm.dispose();
    api.http.close();
    await db.close();
  }
}

void viewport(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> destination(WidgetTester t, int index, String label) async {
  final menu = find.byKey(const ValueKey('workspace.navigationMenu'));
  if (menu.evaluate().isNotEmpty) {
    await t.tap(menu);
    await t.pumpAndSettle();
    final item = find.byKey(ValueKey('workspace.menuDestination.$index'));
    await t.scrollUntilVisible(
      item,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await t.pumpAndSettle();
    await t.ensureVisible(item);
    await t.pumpAndSettle();
    await t.tap(item);
  } else if (find.byType(NavigationRail).evaluate().isNotEmpty) {
    await t.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text(label),
      ),
    );
  } else {
    await t.tap(find.byKey(ValueKey('workspace.destination.$index')));
  }
  await t.pumpAndSettle();
}

Future<void> screenshot(WidgetTester t, GlobalKey boundary, String name) async {
  await t.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('../../docs/screenshots/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
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
  for (final role in ['manager', 'salesperson', 'admin']) {
    for (final size in [
      const Size(360, 800),
      const Size(800, 360),
      const Size(1024, 768),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$role navigation at $size / text $scale', (t) async {
          viewport(t, size);
          final fixture = RoleFixture(role), boundary = GlobalKey();
          await t.pumpWidget(
            fixture.app(
              RepaintBoundary(key: boundary, child: fixture.home()),
              scale: scale,
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.byType(Card), findsNothing);
          if (size == const Size(360, 800) && scale == 1) {
            await screenshot(t, boundary, '$role-home');
          }
          await destination(
            t,
            1,
            role == 'admin'
                ? 'Groupes'
                : role == 'manager'
                ? 'Magasins'
                : 'Ventes',
          );
          expect(t.takeException(), isNull);
          await destination(
            t,
            role == 'salesperson' ? 2 : 3,
            role == 'salesperson'
                ? 'Récompenses'
                : role == 'admin'
                ? 'Catalogue'
                : 'Commandes',
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await fixture.close();
        });
      }
    }
  }

  for (final role in ['manager', 'salesperson', 'admin']) {
    testWidgets(
      '$role offline error remains usable in landscape with large text',
      (t) async {
        viewport(t, const Size(800, 360));
        final f = RoleFixture(role);
        f.vm.state = f.vm.state.copy(
          offline: true,
          pending: 3,
          error: 'Connexion indisponible. Vos données et brouillons sont conservés.',
        );
        await t.pumpWidget(f.app(f.home(storeView: true), scale: 2));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('workspace.navigationMenu')).hitTestable(),
          findsOneWidget,
        );
        await t.pumpWidget(const SizedBox());
        await f.close();
      },
    );
  }

  testWidgets(
    'manager can find and open product settings from a narrow phone',
    (t) async {
      viewport(t, const Size(360, 800));
      final f = RoleFixture('manager'), capture = GlobalKey();
      await t.pumpWidget(f.app(f.home(storeView: true), capture: capture));
      await t.pumpAndSettle();
      await destination(t, 3, 'Plus');
      final settings = find.text('Prix, points et seuils');
      await t.scrollUntilVisible(
        settings,
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(settings);
      await t.pumpAndSettle();
      expect(find.byType(ProductSettingsPage), findsOneWidget);
      await screenshot(t, capture, 'manager-product-settings');
      expect(find.byType(AppBar), findsOneWidget);
      await t.enterText(find.byType(TextField), 'bio-pdrn');
      await t.pumpAndSettle();
      expect(find.text('Crème hydratante'), findsNothing);
      await t.tap(find.text('Sérum PDRN'));
      await t.pumpAndSettle();
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('field.threshold')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor.save')).hitTestable(),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      await f.close();
    },
  );

  testWidgets(
    'catalogue and team subpages refresh after synchronized changes',
    (t) async {
      final f = RoleFixture('admin');
      await t.pumpWidget(f.app(Scaffold(body: CatalogPage(vm: f.vm))));
      await t.pumpAndSettle();
      f.vm.replace(
        StoreData({
          ...f.vm.state.data!.raw,
          'products': [
            ...f.vm.state.data!.list('products'),
            {
              'id': 'new',
              'name': 'Nouveau produit',
              'reference': 'NEW',
              'active': true,
            },
          ],
        }),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Nouveau produit'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Nouveau produit'), findsOneWidget);
      await t.pumpWidget(f.app(Scaffold(body: TeamPage(vm: f.vm))));
      await t.pumpAndSettle();
      f.vm.replace(
        StoreData({
          ...f.vm.state.data!.raw,
          'invitations': [
            {'id': 'invite', 'email': 'collegue@example.test'},
          ],
        }),
      );
      await t.pumpAndSettle();
      expect(
        find.text('1 en attente · voir tout l’historique'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      await f.close();
    },
  );

  testWidgets(
    'legacy receive-only staff cannot access reception or management',
    (t) async {
      final f = RoleFixture('salesperson');
      final store = Store.fromJson({
        ...f.vm.state.store!.toJson(),
        'permissions': ['receive'],
      });
      f.vm.state = WorkspaceState(
        store: store,
        stores: [store],
        data: f.vm.state.data,
      );
      await t.pumpWidget(f.app(f.home(storeView: true)));
      await t.pumpAndSettle();
      expect(find.text('Nouvelle vente'), findsNothing);
      expect(find.text('Livraisons à réceptionner'), findsNothing);
      expect(find.text('Alertes de stock'), findsNothing);
      expect(find.text('Commander'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await f.close();
    },
  );

  testWidgets('group selector remains searchable with keyboard and 200% text', (
    t,
  ) async {
    viewport(t, const Size(800, 360));
    final f = RoleFixture('manager');
    await t.pumpWidget(f.app(f.home(storeView: true), scale: 2));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('scope.group')));
    await t.pumpAndSettle();
    t.view.viewInsets = const FakeViewPadding(bottom: 120);
    addTearDown(t.view.resetViewInsets);
    await t.enterText(find.byType(TextField), 'introuvable');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.enterText(find.byType(TextField), 'Tunis');
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Partenaire Tunis'),
      ),
      100,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      t.element(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Partenaire Tunis'),
        ),
      ),
      alignment: .5,
    );
    await t.pumpAndSettle();
    expect(find.text('Partenaire Tunis').hitTestable(), findsWidgets);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await f.close();
  });
}
