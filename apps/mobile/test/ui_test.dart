import 'dart:io';
import 'dart:ui' as ui;

import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/api/generated/models.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/core/forms.dart';
import 'package:biobalance/ui/features/dashboard/home_screen.dart';
import 'package:biobalance/ui/features/catalog/catalog_screen.dart';
import 'package:biobalance/ui/features/team/team_screen.dart';
import 'package:biobalance/ui/features/replenishment/order_screens.dart';
import 'package:biobalance/ui/features/stores/product_settings_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class PreviewApi extends ApiClient {
  PreviewApi() : super(baseUrl: 'http://unused');
  @override
  Future<AdminOverviewResponseDto> adminOverview() async =>
      AdminOverviewDto(storeCount: 24, staffCount: 138, orders: [], alerts: []);
}

class PreviewWorkspace extends WorkspaceViewModel {
  PreviewWorkspace(super.user, super.repository, super.api);
  void replace(StoreData data) {
    state = state.copy(data: data);
    notifyListeners();
  }
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
    OfflineRepository(db, api),
    api,
  );
  final String role;
  RoleFixture(this.role) {
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
  Future<void> close() async {
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
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
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
              RepaintBoundary(key: boundary, child: const WorkspaceScreen()),
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
                ? 'Magasins'
                : role == 'manager'
                ? 'Stock'
                : 'Mes ventes',
          );
          expect(t.takeException(), isNull);
          await destination(
            t,
            role == 'salesperson' ? 2 : 4,
            role == 'salesperson' ? 'Récompenses' : 'Plus',
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await fixture.close();
        });
      }
    }
  }

  testWidgets(
    'manager can find and open product settings from a narrow phone',
    (t) async {
      viewport(t, const Size(360, 800));
      final f = RoleFixture('manager'), capture = GlobalKey();
      await t.pumpWidget(f.app(const WorkspaceScreen(), capture: capture));
      await t.pumpAndSettle();
      await destination(t, 4, 'Plus');
      final settings = find.text('Prix, points et seuils');
      await t.scrollUntilVisible(settings, 150);
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
      expect(find.text('collegue@example.test'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await f.close();
    },
  );

  testWidgets(
    'receive-only staff see reception without sale or order actions',
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
      await t.pumpWidget(f.app(Scaffold(body: HomePage(vm: f.vm))));
      await t.pumpAndSettle();
      expect(find.text('Nouvelle vente'), findsNothing);
      expect(find.text('Recevoir'), findsOneWidget);
      expect(find.text('Alertes de stock'), findsNothing);
      await t.tap(find.text('Recevoir'));
      await t.pumpAndSettle();
      expect(find.byType(OrdersPage), findsOneWidget);
      expect(find.text('Commander'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await f.close();
    },
  );

  testWidgets('store selector remains searchable with keyboard and 200% text', (
    t,
  ) async {
    viewport(t, const Size(800, 360));
    final f = RoleFixture('manager');
    await t.pumpWidget(f.app(const WorkspaceScreen(), scale: 2));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('workspace.storeSelector')));
    await t.pumpAndSettle();
    t.view.viewInsets = const FakeViewPadding(bottom: 120);
    addTearDown(t.view.resetViewInsets);
    await t.enterText(find.byType(TextField), 'introuvable');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.enterText(find.byType(TextField), 'Tunis');
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Partenaire Tunis'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await Scrollable.ensureVisible(
      t.element(find.text('Partenaire Tunis')),
      alignment: .5,
    );
    await t.pumpAndSettle();
    expect(find.text('Partenaire Tunis').hitTestable(), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await f.close();
  });
}
