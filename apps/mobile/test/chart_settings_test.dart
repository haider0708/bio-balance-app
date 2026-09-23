import 'package:biobalance/domain/models/dashboard.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/sales_trend.dart';
import 'package:biobalance/domain/models/workspace_scope.dart';
import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/features/dashboard/sales_trend_chart.dart';
import 'package:biobalance/ui/features/stores/product_settings_screen.dart';
import 'package:biobalance/ui/features/workspace/more_page.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'group_navigation_test.dart' show ScopeFixture;
import 'ui_test.dart' show screenshot;

const period = DashboardPeriod('2026-08-31', '2026-09-03', 'Test');
final points = SalesTrendPoint.forPeriod([
  {
    'day': '2026-08-31',
    'netMillimes': '75001',
    'netUnits': '2',
    'saleCount': '1',
  },
  {
    'day': '2026-09-02',
    'netMillimes': '140500',
    'netUnits': '4',
    'saleCount': '3',
  },
  {
    'day': '2026-09-03',
    'netMillimes': '98100',
    'netUnits': '3',
    'saleCount': '2',
  },
], period);

Widget chartApp({
  required Widget chart,
  double scale = 1,
  GlobalKey? capture,
}) => MaterialApp(
  theme: appTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: RepaintBoundary(key: capture, child: child!),
  ),
  home: Scaffold(
    appBar: AppBar(title: const Text('Évolution des ventes')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: chart,
    ),
  ),
);

Future<void> seek(WidgetTester t, String label) async {
  final target = find.text(label);
  await t.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 35,
  );
  await t.ensureVisible(target);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });

  test('daily reporting fills calendar gaps without losing exact millimes', () {
    expect(points.map((p) => p.day), [
      '2026-08-31',
      '2026-09-01',
      '2026-09-02',
      '2026-09-03',
    ]);
    expect(points.first.netMillimes, 75001);
    expect(points[1].netMillimes, 0);
    expect(points[1].saleCount, 0);
    expect(points[2].netUnits, 4);
    expect(points[2].period.from, '2026-09-02');
    expect(points[2].period.to, '2026-09-02');
    expect(
      SalesTrendPoint.forPeriod(
        [],
        const DashboardPeriod('2024-01-01', '2024-12-31', 'Année'),
      ).length,
      366,
    );
    expect(
      () => SalesTrendPoint.forPeriod(
        [],
        const DashboardPeriod('2024-01-01', '2025-01-01', 'Trop long'),
      ),
      throwsFormatException,
    );
  });

  testWidgets(
    'touch and dragging select a real date and open its daily sales',
    (t) async {
      t.view.physicalSize = const Size(430, 950);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      SalesTrendPoint? opened;
      await t.pumpWidget(
        chartApp(
          chart: SalesTrendChart(
            points: points,
            onOpenDay: (point) => opened = point,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('03/09/2026'), findsOneWidget);
      final bounds = t.getRect(find.byKey(const ValueKey('sales-trend-plot')));
      await t.tapAt(Offset(bounds.left + 50, bounds.center.dy));
      await t.pumpAndSettle();
      expect(find.text('31/08/2026'), findsOneWidget);
      expect(find.text('75,001 TND'), findsOneWidget);
      await t.dragFrom(
        Offset(bounds.left + 52, bounds.center.dy),
        Offset(bounds.width - 60, 0),
      );
      await t.pumpAndSettle();
      expect(find.text('03/09/2026'), findsOneWidget);
      await t.tap(find.byTooltip('Jour précédent'));
      await t.pumpAndSettle();
      expect(find.text('02/09/2026'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('sales-trend-open-day')));
      expect(opened?.day, '2026-09-02');
      final data = t.widget<LineChart>(find.byType(LineChart)).data;
      expect(data.lineTouchData.enabled, true);
      expect(data.lineBarsData.single.dotData.show, true);
      expect(data.titlesData.bottomTitles.sideTitles.showTitles, true);
      expect(t.takeException(), isNull);
    },
  );

  for (final size in [const Size(360, 850), const Size(800, 360)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('interactive chart remains usable at $size / text $scale', (
        t,
      ) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final capture = GlobalKey();
        await t.pumpWidget(
          chartApp(
            scale: scale,
            capture: capture,
            chart: SalesTrendChart(points: points, onOpenDay: (_) {}),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byTooltip('Jour précédent'));
        await t.tap(find.byTooltip('Jour précédent'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        if (size.width == 360 && scale == 1) {
          await screenshot(t, capture, 'interactive-sales-chart');
        }
        await t.ensureVisible(find.text('Voir toutes les données'));
        await t.tap(find.text('Voir toutes les données'));
        await t.pumpAndSettle();
        expect(find.text('Données du graphique'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'single-day zero and full-year periods have finite chart bounds',
    (t) async {
      for (final range in [
        const DashboardPeriod('2026-09-23', '2026-09-23', 'Jour'),
        const DashboardPeriod('2024-01-01', '2024-12-31', 'Année'),
      ]) {
        await t.pumpWidget(
          chartApp(
            chart: SalesTrendChart(
              key: ValueKey(range.key),
              points: SalesTrendPoint.forPeriod([], range),
              onOpenDay: (_) {},
            ),
          ),
        );
        await t.pumpAndSettle();
        final data = t.widget<LineChart>(find.byType(LineChart)).data;
        expect(data.maxY, greaterThan(data.minY));
        expect(data.maxX, greaterThan(data.minX));
        expect(data.maxY.isFinite, true);
        expect(t.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'top settings selects a store and exposes the same configuration controls',
    (t) async {
      t.view.physicalSize = const Size(360, 850);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = ScopeFixture();
      final capture = GlobalKey();
      addTearDown(f.close);
      await t.pumpWidget(f.app(capture: capture));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Paramètres et gestion'));
      await t.pumpAndSettle();
      expect(find.text('Paramètres et gestion'), findsOneWidget);
      await screenshot(t, capture, 'settings-network');
      await seek(t, 'Choisir un magasin');
      await t.tap(find.text('Choisir un magasin'));
      await t.pumpAndSettle();
      await seek(t, 'Magasin Tunis');
      await t.tap(find.text('Magasin Tunis'));
      await t.pumpAndSettle();
      expect(f.scope.scope.store?.id, 's1');
      expect(find.byType(MorePage), findsOneWidget);
      await seek(t, 'Prix, points et seuils');
      await screenshot(t, capture, 'settings-store');
      await t.tap(find.text('Prix, points et seuils'));
      await t.pumpAndSettle();
      expect(find.byType(ProductSettingsPage), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      await seek(t, 'Journal d’audit');
      expect(find.text('Journal d’audit'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final selectedStore in [false, true]) {
    testWidgets(
      'settings remain reachable with 200 percent text, store $selectedStore',
      (t) async {
        t.view.physicalSize = const Size(360, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final f = ScopeFixture();
        addTearDown(f.close);
        await t.pumpWidget(f.app(scale: 2));
        await t.pumpAndSettle();
        if (selectedStore) {
          await f.scope.selectGroup(f.scope.groups.first);
          await f.scope.selectStore(f.workspace.state.stores.first);
          await t.pumpAndSettle();
        }
        await t.tap(find.byTooltip('Paramètres et gestion'));
        await t.pumpAndSettle();
        if (selectedStore) {
          await seek(t, 'Prix, points et seuils');
          expect(t.takeException(), isNull);
        }
        await seek(t, 'Mon compte et notifications');
        expect(find.text('Mon compte et notifications'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('salesperson settings do not expose management or other groups', (
    t,
  ) async {
    final f = ScopeFixture(admin: false);
    addTearDown(f.close);
    final store = Store.fromJson({
      ...f.workspace.state.stores.first.toJson(),
      'permissions': ['sell', 'receive'],
    });
    const group = PartnerGroup(
      id: 'g1',
      name: 'Parahouse',
      canManage: false,
      storeCount: 1,
    );
    f.scope.groups = [group];
    f.scope.scope = WorkspaceScope.store(group, store);
    await f.workspace.select(store);
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: MorePage(vm: f.workspace, scope: f.scope),
        ),
      ),
    );
    await t.pumpAndSettle();
    final children = t.widget<Content>(find.byType(Content)).children;
    final labels = children
        .whereType<CompactRow>()
        .map((row) => row.title)
        .toList();
    expect(
      labels,
      containsAll([
        'Ventes & corrections',
        'Récompenses & classement',
        'Formation',
        'Mon compte et notifications',
      ]),
    );
    expect(labels, isNot(contains('Prix, points et seuils')));
    expect(labels, isNot(contains('Équipe du groupe et invitations')));
    expect(labels, isNot(contains('Inviter un responsable')));
    expect(labels, isNot(contains('Journal d’audit')));
    f.scope.dispose();
    await t.pumpWidget(const SizedBox());
  });
}
