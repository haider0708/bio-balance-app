// The screens added in the second round: region page, rewards, reports, history, quick restock.
import 'package:flutter/widgets.dart' show AxisDirection, Scrollable, Size;

import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show loadFonts, server;
import 'support/fake_server.dart';
import 'support/analytics_fixture.dart';
import 'support/harness.dart';

const tall = Size(412, 2000);

void main() {
  setUpAll(base.loadFonts);

  testWidgets('admin home and the region page', (tester) async {
    final s = base.server('ADMIN')
      ..on('GET /v1/depots', [
        {
          'id': 'd1',
          'name': 'Dépôt Hedi',
          'address': 'ZI',
          'city': 'Tunis',
          'phone': '20 111 222',
          'status': 'ACTIVE',
          'region': {'id': 'r1', 'name': 'Nord'},
          'photoIds': <String>[],
          'units': 120,
          'products': 6,
          'counted': true,
          'countPending': false,
        },
      ])
      ..on('GET /v1/groups', [
        {
          'id': 'g1',
          'name': 'Groupe Lac',
          'status': 'ACTIVE',
          'regionId': 'r1',
          'pdvCount': 3,
        },
      ])
      ..on('GET /v1/pdvs', [
        {
          'id': 'p1',
          'name': 'Para Lac',
          'address': '12 rue du Lac',
          'city': 'Tunis',
          'phone': '71 000 000',
          'status': 'ACTIVE',
          'regionId': 'r1',
          'groupId': 'g1',
          'groupName': 'Groupe Lac',
          'memberCount': 2,
          'initialStock': 'APPROVED',
        },
      ]);
    final dash =
        (s.routes['GET /v1/dashboard']!)(RequestOptions0.none).body!
            as Map<String, Object?>;
    dash['topProducts'] = [
      {
        'name': 'BIOBALANCE SÉRUM VITAMINE C 30ML',
        'family': 'Sérums',
        'imageId': null,
        'units': 64,
      },
      {
        'name': 'BIOBALANCE SÉRUM NIACINAMIDE 10%',
        'family': 'Sérums',
        'imageId': null,
        'units': 51,
      },
      {
        'name': 'BIOBALANCE NETTOYANT DOUX',
        'family': 'Nettoyants',
        'imageId': null,
        'units': 22,
      },
    ];
    dash['topPdvs'] = [
      {'name': 'Para Lac', 'city': 'Tunis', 'units': 120},
      {'name': 'Pharma Marsa', 'city': 'La Marsa', 'units': 84},
    ];
    dash['region'] = {
      'id': 'r1',
      'name': 'Nord',
      'groups': 2,
      'pdvs': 4,
      'members': 9,
      'grossistes': 1,
      'responsable': {
        'name': 'Nora Ben Salah',
        'phone': '20 555 666',
        'email': 'n@x.tn',
      },
    };
    s.on('GET /v1/dashboard', dash);
    await launch(tester, s, language: 'en', size: tall);
    await screenshot(tester, '30-admin-home-v3');
    await tester.tap(find.text('Nord').first);
    await settle(tester);
    await screenshot(tester, '31-region-page');
  });

  testWidgets('responsable home with quick restock', (tester) async {
    final s = base.server('RESPONSABLE');
    final dash =
        (s.routes['GET /v1/dashboard']!)(RequestOptions0.none).body!
            as Map<String, Object?>;
    dash['lowByPlace'] = [
      {'pdvId': 'p1', 'place': 'Para Lac', 'low': 2, 'out': 1},
    ];
    s.on('GET /v1/reports/stock/attention', [
      {
        'locationId': 'p1',
        'place': 'Para Lac',
        'kind': 'PDV',
        'productId': 'a',
        'product': 'BIOBALANCE SÉRUM VITAMINE C 30ML',
        'family': 'Sérums',
        'quantity': 2,
      },
      {
        'locationId': 'p1',
        'place': 'Para Lac',
        'kind': 'PDV',
        'productId': 'b',
        'product': 'BIOBALANCE SÉRUM NIACINAMIDE 10%',
        'family': 'Sérums',
        'quantity': 0,
      },
    ]);
    dash['topGroups'] = [
      {'groupId': 'g1', 'name': 'Groupe Lac', 'units': 190},
    ];
    dash['topPdvs'] = [
      {'name': 'Para Lac', 'city': 'Tunis', 'units': 120},
      {'name': 'Pharma Marsa', 'city': 'La Marsa', 'units': 84},
    ];
    dash['payouts'] = null;
    s.on('GET /v1/dashboard', dash);
    s.handle(
      'POST /v1/restocks',
      (_) => (
        status: 201,
        body: {
          'id': 'o9',
          'number': 'RS-2026-000009',
          'status': 'REQUESTED',
          'lines': <Object>[],
        },
      ),
    );
    await launch(tester, s, language: 'en', size: tall);
    await screenshot(tester, '32-responsable-home-v3');
    await tester.tap(find.text('Para Lac').first);
    await settle(tester);
    await screenshot(tester, '33-store-low-sheet');
    await tester.tap(find.text('Order').first);
    await settle(tester);
    await screenshot(tester, '33b-order-sheet');
  });

  testWidgets('rewards and reports', (tester) async {
    final s = base.server('ADMIN')
      ..on('GET /v1/reward-rules/effective', [
        {
          'productId': 'a',
          'name': 'BIOBALANCE SÉRUM VITAMINE C 30ML',
          'family': 'Sérums',
          'imageId': null,
          'amountMillimes': 800,
          'source': 'PRODUCT',
        },
        {
          'productId': 'b',
          'name': 'BIOBALANCE SÉRUM NIACINAMIDE 10%',
          'family': 'Sérums',
          'imageId': null,
          'amountMillimes': 500,
          'source': 'FAMILY',
        },
        {
          'productId': 'c',
          'name': 'BIOBALANCE SHAMPOING ARGAN',
          'family': 'Soins capillaires',
          'imageId': null,
          'amountMillimes': 0,
          'source': 'NONE',
        },
      ])
      ..on('GET /v1/analytics/overview', overviewFixture())
      ..on('GET /v1/analytics/stores', storesBoardFixture())
      ..on('GET /v1/sales', {'items': <Object>[], 'nextCursor': null});
    await launch(tester, s, language: 'en', size: tall);
    await tester.tap(find.text('More').last);
    await settle(tester);
    await tester.tap(find.text('Rewards'));
    await settle(tester);
    await screenshot(tester, '34-rewards-v3');
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('Reports'));
    await settle(tester);
    await screenshot(tester, '35-reports-v3');
    await tester.scrollUntilVisible(
      find.text('All points of sale'),
      400,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
    await settle(tester, frames: 5);
    await screenshot(tester, '35b-reports-bottom');
    await tester.tap(find.text('All points of sale'));
    await settle(tester);
    await screenshot(tester, '35c-stores-board');
  });

  testWidgets('the team member reads a long history', (tester) async {
    final s = base.server('VENDEUR');
    final today = DateTime.now();
    String d(int back) =>
        today.subtract(Duration(days: back)).toIso8601String().substring(0, 10);
    s.on('GET /v1/sales/days', [
      {'day': d(0), 'sales': 3, 'units': 8, 'rewardMillimes': 3400},
      {
        'day': d(0) == d(1) ? d(2) : d(1),
        'sales': 5,
        'units': 12,
        'rewardMillimes': 5200,
      },
    ]);
    s.on('GET /v1/sales', {
      'items': [
        for (var i = 0; i < 3; i++)
          {
            'id': 's$i',
            'status': 'ACTIVE',
            'version': 1,
            'day': d(0),
            'occurredAt': today
                .subtract(Duration(hours: i * 2))
                .toIso8601String(),
            'createdAt': today.toIso8601String(),
            'units': 3,
            'rewardMillimes': 1100,
            'seller': {'id': 'u1', 'name': 'Amira'},
            'pdv': {'id': 'p1', 'name': 'Para Lac'},
            'lines': [
              {
                'productId': 'a',
                'name': 'SÉRUM VITAMINE C 30ML',
                'quantity': 2,
                'rewardMillimes': 800,
                'imageId': null,
              },
              {
                'productId': 'b',
                'name': 'SÉRUM NIACINAMIDE',
                'quantity': 1,
                'rewardMillimes': 500,
                'imageId': null,
              },
            ],
          },
      ],
      'nextCursor': null,
    });
    await launch(tester, s, language: 'en');
    await tester.tap(find.text('Sales').last);
    await settle(tester);
    await screenshot(tester, '36-history-v3');
  });
}
