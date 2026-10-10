import 'package:biobalance/features/analytics/lens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show loadFonts, server;
import 'support/analytics_fixture.dart';
import 'support/fake_server.dart';
import 'support/harness.dart';

const tall = Size(412, 1600);

Map<String, Object?> sale(String id, {String status = 'ACTIVE'}) => {
  'id': id,
  'status': status,
  'version': 1,
  'occurredAt': '2026-09-30T15:20:00.000Z',
  'createdAt': '2026-09-30T15:20:05.000Z',
  'day': '2026-09-30',
  'units': 3,
  'rewardMillimes': 1500,
  'seller': {'id': 'u1', 'name': 'Amira Gharbi'},
  'pdv': {'id': 's1', 'name': 'Para Lac'},
  'lines': [
    {
      'productId': 'p1',
      'name': 'BIOBALANCE SÉRUM VITAMINE C 30ML',
      'imageId': null,
      'quantity': 3,
      'rewardMillimes': 1500,
    },
  ],
};

/// An admin server whose analytics answer follows the lens asked for.
FakeServer analyticsServer({String role = 'ADMIN'}) => base.server(role)
  ..handle('GET /v1/analytics/overview', (r) {
    final q = r.queryParameters;
    return (
      status: 200,
      body: overviewFixture(
        from: q['from'] as String,
        to: q['to'] as String,
        granularity: q['from'] == q['to'] ? 'hour' : 'day',
        withMoney: role == 'ADMIN',
        subject: {
          if (q['pdvId'] != null)
            'pdv': {
              'id': q['pdvId'],
              'name': 'Para Lac',
              'city': 'Tunis',
              'address': '1 rue du Lac',
              'phone': null,
              'status': 'ACTIVE',
              'createdAt': '2026-01-01T00:00:00.000Z',
              'regionId': 'r1',
              'region': 'Nord',
              'groupId': null,
              'group': null,
              'members': 2,
            },
          if (q['productId'] != null)
            'product': {
              'id': q['productId'],
              'name': 'BIOBALANCE SÉRUM VITAMINE C 30ML',
              'reference': 'P1',
              'family': 'Sérums',
              'range': '',
              'packageSize': '30 ml',
              'imageId': null,
              'active': true,
            },
        },
        stock: q['productId'] != null
            ? {
                'kind': 'product',
                'total': 54,
                'inGrossistes': 120,
                'rows': [
                  {
                    'locationId': 's1',
                    'kind': 'PDV',
                    'name': 'Para Lac',
                    'city': 'Tunis',
                    'region': 'Nord',
                    'quantity': 4,
                    'sold': 30,
                    'perDay': 1.1,
                    'daysLeft': 3,
                  },
                  {
                    'locationId': 'd1',
                    'kind': 'DEPOT',
                    'name': 'Dépôt Hedi',
                    'city': 'Tunis',
                    'region': 'Nord',
                    'quantity': 120,
                    'sold': 0,
                    'perDay': 0,
                    'daysLeft': null,
                  },
                ],
              }
            : null,
      ),
    );
  })
  ..on('GET /v1/analytics/stores', storesBoardFixture())
  ..handle(
    'GET /v1/sales',
    (r) => (
      status: 200,
      body: {
        'items': [
          if (r.queryParameters['status'] == 'VOIDED')
            sale('v1', status: 'VOIDED')
          else ...[
            sale('a1'),
            sale('a2'),
          ],
        ],
        'nextCursor': null,
      },
    ),
  );

/// The page's own vertical list (chip rows scroll sideways).
final page = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

Future<void> scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 300, scrollable: page.last);
  await settle(tester, frames: 5);
}

Map<String, dynamic> lastQuery(FakeServer s, String path) =>
    s.calls.lastWhere((c) => c.path == path).queryParameters;

void main() {
  setUpAll(base.loadFonts);

  testWidgets('every dashboard number opens what it is made of', (
    tester,
  ) async {
    final s = analyticsServer();
    await launch(tester, s, language: 'en', size: tall);

    await tester.tap(find.text('Today').first);
    await settle(tester);
    expect(tester.takeException(), isNull);
    final today = lastQuery(s, '/v1/analytics/overview');
    expect(today['from'], today['to']);
    expect(find.text('Hour by hour'), findsOneWidget);
    expect(find.text('Para Lac'), findsWidgets);

    // A store of the ranking opens the same question narrowed to it.
    await tester.ensureVisible(find.text('Pharma Marsa').first);
    await tester.tap(find.text('Pharma Marsa').first);
    await settle(tester);
    expect(lastQuery(s, '/v1/analytics/overview')['pdvId'], 's2');
    expect(find.text('Store page'), findsOneWidget);
    expect(find.text('Point of sale: Para Lac'), findsOneWidget);

    // The rewards decide the ranking when chosen.
    await tester.tap(find.text('Rewards').first);
    await settle(tester);
    expect(lastQuery(s, '/v1/analytics/overview')['sort'], 'reward');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the last 7 days and the rewards tiles carry their period', (
    tester,
  ) async {
    final s = analyticsServer();
    await launch(tester, s, language: 'en', size: tall);
    await tester.tap(find.text('Last 7 days').first);
    await settle(tester);
    final week = lastQuery(s, '/v1/analytics/overview');
    final lens = Lens.lastDays(7);
    expect([week['from'], week['to']], [lens.from, lens.to]);
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('Rewards, 30 days').first);
    await settle(tester);
    final month = lastQuery(s, '/v1/analytics/overview');
    expect(month['sort'], 'reward');
    expect(month['from'], Lens.lastDays(30).from);
  });

  testWidgets('reports: insights, stock health, money, and the sales ledger', (
    tester,
  ) async {
    final s = analyticsServer();
    await launch(tester, s, language: 'en', size: tall);
    await tester.tap(find.text('More').last);
    await settle(tester);
    await tester.tap(find.text('Reports'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('What the numbers say'), findsOneWidget);
    await scrollTo(tester, find.text('Rewards in money'));
    expect(find.text('Owed to team members'), findsOneWidget);
    await scrollTo(tester, find.text('Latest sales'));
    await tester.tap(find.text('See all'));
    await settle(tester);
    expect(find.textContaining('Amira Gharbi'), findsNWidgets(2));
    await tester.tap(find.text('Cancelled').first);
    await settle(tester);
    expect(lastQuery(s, '/v1/sales')['status'], 'VOIDED');
    expect(find.textContaining('Amira Gharbi'), findsOneWidget);
  });

  testWidgets('a filter narrows the question; removing it widens it again', (
    tester,
  ) async {
    final s = analyticsServer();
    await launch(tester, s, language: 'en', size: tall);
    await tester.tap(find.text('More').last);
    await settle(tester);
    await tester.tap(find.text('Reports'));
    await settle(tester);
    await tester.tap(find.text('Filter'));
    await settle(tester);
    await tester.tap(find.text('Product'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'vitamine');
    await settle(tester);
    await tester.tap(find.text('BIOBALANCE SÉRUM VITAMINE C 30ML').last);
    await settle(tester);
    expect(lastQuery(s, '/v1/analytics/overview')['productId'], 'a');
    await scrollTo(tester, find.text('Where the stock is'));
    expect(find.text('Dépôt Hedi'), findsOneWidget);
    await tester.drag(page.last, const Offset(0, 5000));
    await settle(tester, frames: 5);
    await tester.tap(find.byTooltip('Remove this filter'));
    await settle(tester);
    expect(lastQuery(s, '/v1/analytics/overview')['productId'], isNull);
  });

  testWidgets('the stores board shows the silent stores', (tester) async {
    final s = analyticsServer();
    await launch(tester, s, language: 'en', size: tall);
    await tester.ensureVisible(find.text('Active PDVs'));
    await tester.tap(find.text('Active PDVs'));
    await settle(tester);
    expect(find.text('Para Lac'), findsOneWidget);
    expect(find.text('Para Waiting'), findsOneWidget);
    await tester.ensureVisible(find.text('No sale · 1'));
    await settle(tester, frames: 5);
    await tester.tap(find.text('No sale · 1'));
    await settle(tester);
    expect(find.text('Pharma Quiet'), findsOneWidget);
    expect(find.text('Para Lac'), findsNothing);
    await tester.tap(find.text('Pharma Quiet'));
    await settle(tester);
    expect(lastQuery(s, '/v1/analytics/overview')['pdvId'], 's2');
  });

  testWidgets('a responsable gets the same answers without the money', (
    tester,
  ) async {
    final s = analyticsServer(role: 'RESPONSABLE');
    await launch(tester, s, language: 'en', size: tall);
    await tester.tap(find.text('Reports').last);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('What the numbers say'), findsOneWidget);
    expect(find.text('Rewards in money'), findsNothing);
  });

  testWidgets('on a wide screen the panels sit side by side', (tester) async {
    final s = analyticsServer();
    await launch(tester, s, language: 'en', size: const Size(1280, 2400));
    await tester.tap(find.text('Last 7 days').first);
    await settle(tester);
    expect(tester.takeException(), isNull);
    await screenshot(tester, '60-analytics-wide');
    await tester.tap(find.text('BIOBALANCE SÉRUM VITAMINE C 30ML').first);
    await settle(tester);
    expect(tester.takeException(), isNull);
    await screenshot(tester, '61-analytics-product-wide');
  });
}
