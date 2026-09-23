import 'package:biobalance/domain/models/dashboard.dart';
import 'package:biobalance/domain/models/sales_trend.dart';
import 'package:biobalance/ui/features/dashboard/sales_trend_chart.dart';
import 'package:biobalance/ui/features/reporting/scoped_sales_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chart_settings_test.dart' show chartApp, points;
import 'ui_test.dart' show screenshot;
import 'group_navigation_test.dart' show ScopeFixture;

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

  testWidgets(
    'metric switches preserve the day, use real counts and include zero days in the average',
    (t) async {
      await t.pumpWidget(
        chartApp(
          chart: SalesTrendChart(points: points, onOpenDay: (_) {}),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('≈ 78,400 TND'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('sales-trend-metric:units')));
      await t.pumpAndSettle();
      expect(find.text('3 unités'), findsOneWidget);
      expect(find.text('03/09/2026'), findsOneWidget);
      expect(find.textContaining('2,25 unités'), findsOneWidget);
      var chart = t.widget<LineChart>(find.byType(LineChart)).data;
      expect(chart.lineBarsData.single.spots.map((s) => s.y), [2, 0, 4, 3]);
      expect(chart.extraLinesData.horizontalLines.single.y, 2.25);
      expect(chart.gridData.horizontalInterval! >= 1, true);
      await t.tap(find.byKey(const ValueKey('sales-trend-metric:sales')));
      await t.pumpAndSettle();
      expect(find.text('2 ventes'), findsOneWidget);
      chart = t.widget<LineChart>(find.byType(LineChart)).data;
      expect(chart.lineBarsData.single.spots.map((s) => s.y), [1, 0, 3, 2]);
      await t.ensureVisible(find.byKey(const ValueKey('sales-trend-peak')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sales-trend-peak')));
      await t.pumpAndSettle();
      expect(find.text('02/09/2026'), findsOneWidget);
      expect(find.text('3 ventes'), findsOneWidget);
      chart = t.widget<LineChart>(find.byType(LineChart)).data;
      final tooltip = chart.lineTouchData.touchTooltipData
          .getTooltipItems(chart.showingTooltipIndicators.single.showingSpots)
          .single!;
      expect(tooltip.text, '02/09/2026\n');
      expect(tooltip.children!.single.text, '3 ventes');
      expect(chart.lineTouchData.touchTooltipData.fitInsideHorizontally, true);
      expect(chart.lineTouchData.touchTooltipData.fitInsideVertically, true);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'expanded exploration retains scope, metric and selected day on return and drill-down',
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
            scopeLabel: 'Parahouse · Magasin Tunis',
            onOpenDay: (point) => opened = point,
          ),
        ),
      );
      await t.pumpAndSettle();
      final expand = t
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Agrandir le graphique',
            ),
          )
          .onPressed!;
      expand();
      expand();
      await t.pumpAndSettle();
      expect(find.text('Parahouse · Magasin Tunis'), findsOneWidget);
      expect(find.text('31/08/2026 – 03/09/2026'), findsOneWidget);
      expect(find.byType(SalesTrendChart), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('sales-trend-metric:units')));
      await t.tap(find.byTooltip('Jour précédent'));
      await t.pumpAndSettle();
      expect(find.text('4 unités'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('02/09/2026'), findsOneWidget);
      expect(find.text('4 unités'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('sales-trend-open-day')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sales-trend-open-day')));
      expect(opened?.period.from, '2026-09-02');
      expect(opened?.period.to, '2026-09-02');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'expanded daily history stays attached to its original store when the underlying workspace changes',
    (t) async {
      final f = ScopeFixture();
      addTearDown(f.close);
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      await f.scope.selectGroup(f.scope.groups.firstWhere((g) => g.id == 'g1'));
      await f.scope.selectStore(
        f.scope.storesFor('g1').firstWhere((s) => s.id == 's1'),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byTooltip('Agrandir le graphique'),
        200,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Agrandir le graphique'));
      await t.pumpAndSettle();
      final originalDay = t
          .widget<Text>(find.byKey(const ValueKey('sales-trend-date')))
          .data!;
      await f.scope.selectStore(
        f.scope.storesFor('g1').firstWhere((s) => s.id == 's2'),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('sales-trend-open-day')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sales-trend-open-day')));
      await t.pumpAndSettle();
      final history = t.widget<ScopedSalesScreen>(
        find.byType(ScopedSalesScreen),
      );
      expect(history.storeId, 's1');
      expect(history.groupId, 'g1');
      expect(history.title, 'Magasin Tunis');
      expect(history.period.label, originalDay);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a refreshed dataset retains exploration and renders updated exact values without animation',
    (t) async {
      Widget app(List<SalesTrendPoint> rows) => chartApp(
        chart: SalesTrendChart(points: rows, onOpenDay: (_) {}),
      );
      await t.pumpWidget(app(points));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Jour précédent'));
      await t.pumpAndSettle();
      final updated = [...points];
      updated[2] = const SalesTrendPoint(
        day: '2026-09-02',
        netMillimes: 999001,
        netUnits: 5,
        saleCount: 3,
      );
      await t.pumpWidget(app(updated));
      await t.pumpAndSettle();
      expect(find.text('02/09/2026'), findsOneWidget);
      expect(find.text('999,001 TND'), findsOneWidget);
      expect(
        t.widget<LineChart>(find.byType(LineChart)).duration,
        Duration.zero,
      );
    },
  );

  for (final range in [
    const DashboardPeriod('2026-09-23', '2026-09-23', 'Jour vide'),
    const DashboardPeriod('2024-01-01', '2024-12-31', 'Année'),
  ]) {
    testWidgets(
      'narrow expanded chart handles ${range.label} and 200 percent text',
      (t) async {
        t.view.physicalSize = const Size(320, 740);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final rows = SalesTrendPoint.forPeriod([], range);
        SalesTrendPoint? opened;
        await t.pumpWidget(
          chartApp(
            scale: 2,
            chart: SalesTrendChart(
              points: rows,
              onOpenDay: (point) => opened = point,
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('Agrandir le graphique'));
        await t.pumpAndSettle();
        final chart = t.widget<LineChart>(find.byType(LineChart)).data;
        expect(chart.lineBarsData.single.spots.length, rows.length);
        expect(chart.maxY.isFinite, true);
        expect(chart.maxY, greaterThan(0));
        expect(chart.extraLinesData.horizontalLines, isEmpty);
        await t.ensureVisible(
          find.byKey(const ValueKey('sales-trend-open-day')),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('sales-trend-open-day')));
        expect(opened?.day, range.to);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'large text uses the accessible readout and honors reduced motion',
    (t) async {
      await t.pumpWidget(
        chartApp(
          chart: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
            child: SalesTrendChart(points: points, onOpenDay: (_) {}),
          ),
        ),
      );
      await t.pumpAndSettle();
      final chip = t.widget<ChoiceChip>(
        find.byKey(const ValueKey('sales-trend-metric:units')),
      );
      expect(chip.chipAnimationStyle?.selectAnimation?.duration, Duration.zero);
      await t.tap(find.byKey(const ValueKey('sales-trend-metric:units')));
      await t.pump();
      expect(find.text('3 unités'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('sales-trend-peak')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sales-trend-peak')));
      await t.pumpAndSettle();
      expect(find.text('4 unités'), findsOneWidget);
      expect(
        t
            .widget<LineChart>(find.byType(LineChart))
            .data
            .showingTooltipIndicators,
        isEmpty,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'monthly chart preview shows a selected point and the expanded landscape view',
    (t) async {
      const amounts = [
        320100,
        475200,
        398500,
        0,
        522000,
        640300,
        489700,
        715000,
        580500,
        432200,
        820400,
        655100,
        734800,
        905500,
        0,
        618600,
        840300,
        765000,
        945500,
        1124500,
        856000,
        1032700,
        967500,
      ];
      final rows = [
        for (var i = 0; i < amounts.length; i++)
          SalesTrendPoint(
            day: '2026-09-${(i + 1).toString().padLeft(2, '0')}',
            netMillimes: amounts[i],
            netUnits: amounts[i] == 0 ? 0 : 5 + i,
            saleCount: amounts[i] == 0 ? 0 : 2 + i % 9,
          ),
      ];
      t.view.physicalSize = const Size(390, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      await t.pumpWidget(
        chartApp(
          capture: capture,
          chart: SalesTrendChart(
            points: rows,
            scopeLabel: 'Parahouse · Magasin Tunis',
            onOpenDay: (_) {},
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('sales-trend-peak')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sales-trend-peak')));
      await t.pumpAndSettle();
      await screenshot(t, capture, 'interactive-sales-chart');
      await t.ensureVisible(find.byTooltip('Agrandir le graphique'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Agrandir le graphique'));
      await t.pumpAndSettle();
      t.view.physicalSize = const Size(950, 500);
      await t.pumpAndSettle();
      await screenshot(t, capture, 'interactive-sales-chart-expanded');
      expect(t.takeException(), isNull);
    },
  );
}
