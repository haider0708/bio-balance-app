// The screens added in the second round: region page, rewards, reports, history, quick restock.
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show loadFonts, server;
import 'support/fake_server.dart';
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
          'regionId': 'r1',
          'region': {'id': 'r1', 'name': 'Nord'},
          'grossiste': {
            'name': 'Hedi',
            'email': 'h@x.tn',
            'phone': '20 111 222',
          },
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
      ..on('GET /v1/reports/sales', {
        'rows': [
          {
            'key': 'a',
            'label': 'BIOBALANCE SÉRUM VITAMINE C 30ML',
            'sales': 140,
            'units': 380,
            'rewardMillimes': 190000,
            'imageId': null,
          },
          {
            'key': 'b',
            'label': 'BIOBALANCE SÉRUM NIACINAMIDE 10%',
            'sales': 90,
            'units': 250,
            'rewardMillimes': 120000,
            'imageId': null,
          },
        ],
        'totals': {'sales': 230, 'units': 630, 'rewardMillimes': 310000},
        'previous': {'sales': 200, 'units': 700, 'rewardMillimes': 250000},
        'trend': [
          for (var i = 1; i <= 30; i++)
            {
              'day': '2026-09-${i.toString().padLeft(2, '0')}',
              'units': (i * 7) % 23,
              'sales': i % 5,
            },
        ],
      })
      ..on('GET /v1/reports/insights', {
        'totals': {
          'sales': 230,
          'units': 630,
          'rewardMillimes': 310000,
          'activeStores': 7,
          'activeSellers': 12,
          'unitsChange': -10,
          'salesChange': 15,
          'rewardChange': 24,
          'unitsPerSale': 2.7,
          'previousUnits': 700,
        },
        'weekdays': [
          for (var d = 0; d < 7; d++)
            {
              'weekday': d,
              'units': [40, 90, 110, 100, 85, 130, 75][d],
            },
        ],
        'bestDay': {'day': '2026-09-19', 'units': 48, 'weekday': 6},
        'slowDay': {'day': '2026-09-03', 'units': 4, 'weekday': 4},
        'families': [
          {'name': 'Sérums', 'units': 300, 'before': 250, 'change': 20},
          {
            'name': 'Soins capillaires',
            'units': 180,
            'before': 260,
            'change': -31,
          },
          {'name': 'Crèmes visage', 'units': 150, 'before': 150, 'change': 0},
        ],
        'stores': [
          {
            'id': 's1',
            'name': 'Para Lac',
            'city': 'Tunis',
            'units': 260,
            'before': 300,
            'rewardMillimes': 120000,
            'share': 41,
            'change': -13,
          },
          {
            'id': 's2',
            'name': 'Pharma Marsa',
            'city': 'La Marsa',
            'units': 210,
            'before': 150,
            'rewardMillimes': 90000,
            'share': 33,
            'change': 40,
          },
        ],
        'products': [
          {
            'id': 'a',
            'name': 'BIOBALANCE SÉRUM VITAMINE C 30ML',
            'family': 'Sérums',
            'imageId': null,
            'units': 120,
            'before': 90,
            'change': 33,
          },
        ],
        'sellers': [
          {
            'id': 'u1',
            'name': 'Amira Gharbi',
            'store': 'Para Lac',
            'units': 140,
            'sales': 61,
          },
          {
            'id': 'u2',
            'name': 'Karim Mejri',
            'store': 'Pharma Marsa',
            'units': 95,
            'sales': 40,
          },
        ],
        'stock': {
          'runningOut': [
            {
              'id': 'a',
              'name': 'BIOBALANCE SÉRUM VITAMINE C 30ML',
              'imageId': null,
              'stock': 6,
              'perDay': 2.1,
              'days': 2,
            },
            {
              'id': 'b',
              'name': 'BIOBALANCE SÉRUM NIACINAMIDE 10%',
              'imageId': null,
              'stock': 0,
              'perDay': 1.4,
              'days': 0,
            },
          ],
          'dead': {
            'count': 3,
            'items': [
              {
                'id': 'z',
                'name': 'BIOBALANCE MASQUE ARGILE',
                'imageId': null,
                'stock': 24,
              },
            ],
          },
        },
        'insights': [
          {
            'key': 'TOP_FAMILY',
            'params': {'family': 'Sérums', 'share': 48, 'change': 20},
          },
          {
            'key': 'STORE_DOWN',
            'params': {'store': 'Para Lac', 'change': -13},
          },
          {
            'key': 'RUNNING_OUT',
            'params': {'count': 2, 'days': 7},
          },
          {
            'key': 'BEST_WEEKDAY',
            'params': {'weekday': 5, 'share': 21},
          },
          {
            'key': 'TOP_SELLER',
            'params': {'name': 'Amira Gharbi', 'units': 140},
          },
          {
            'key': 'REWARD_PER_UNIT',
            'params': {'amountMillimes': 492},
          },
        ],
      });
    await launch(tester, s, language: 'en', size: tall);
    await openAdminNav(tester);
    await tester.tap(find.text('Rewards').last);
    await settle(tester);
    await screenshot(tester, '34-rewards-v3');
    await openAdminNav(tester);
    await tester.tap(find.text('Reports').last);
    await settle(tester);
    await screenshot(tester, '35-reports-v3');
    await tester.tap(find.text('Stores').last);
    await settle(tester);
    await screenshot(tester, '35b-reports-stores');
    await tester.tap(find.text('Stock').last);
    await settle(tester);
    await screenshot(tester, '35c-reports-stock');
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
