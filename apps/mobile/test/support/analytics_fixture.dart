/// What the server answers for analytics, in the shapes of `/v1/analytics/*` (checked against the
/// real API by the contract test).
Map<String, Object?> overviewFixture({
  String from = '2026-09-01',
  String to = '2026-09-30',
  String granularity = 'day',
  Map<String, Object?> subject = const {},
  Map<String, Object?>? stock,
  bool withMoney = true,
}) => {
  'period': {'from': from, 'to': to},
  'previous': {'from': '2026-08-02', 'to': '2026-08-31'},
  'today': to,
  'granularity': granularity,
  'sort': 'units',
  'subject': {
    'region': null,
    'group': null,
    'pdv': null,
    'seller': null,
    'product': null,
    'family': null,
    ...subject,
  },
  'totals': {
    'sales': 230,
    'units': 630,
    'rewardMillimes': 310000,
    'stores': 7,
    'sellers': 12,
    'products': 18,
    'unitsPerSale': 2.7,
    'silentStores': 2,
    'voided': 1,
    'corrected': 3,
    'late': 4,
  },
  'previousTotals': {'sales': 200, 'units': 700, 'rewardMillimes': 250000},
  'change': {'units': -10, 'sales': 15, 'reward': 24},
  'series': granularity == 'hour'
      ? [
          for (var h = 0; h < 24; h++)
            {
              'key': h.toString().padLeft(2, '0'),
              'units': h > 8 && h < 20 ? (h * 3) % 17 : 0,
              'sales': h > 8 && h < 20 ? h % 5 : 0,
              'rewardMillimes': 0,
            },
        ]
      : [
          for (var i = 1; i <= 30; i++)
            {
              'key': '2026-09-${i.toString().padLeft(2, '0')}',
              'units': (i * 7) % 23,
              'sales': i % 5,
              'rewardMillimes': i * 1000,
            },
        ],
  'hours': [
    for (var h = 0; h < 24; h++)
      {
        'hour': h,
        'units': h > 8 && h < 20 ? (h * 3) % 17 : 0,
        'sales': h % 3,
        'rewardMillimes': 0,
      },
  ],
  'weekdays': [
    for (var d = 0; d < 7; d++)
      {
        'weekday': d,
        'units': [40, 90, 110, 100, 85, 130, 75][d],
      },
  ],
  'breakdowns': {
    if (subject['pdv'] == null && subject['seller'] == null)
      'stores': [
        row('s1', 'Para Lac', 'Tunis', 260, 300),
        row('s2', 'Pharma Marsa', 'La Marsa', 210, 150),
      ],
    if (subject['seller'] == null)
      'sellers': [
        row('u1', 'Amira Gharbi', 'Para Lac', 140, 120),
        row('u2', 'Karim Mejri', 'Pharma Marsa', 95, 100),
      ],
    if (subject['product'] == null)
      'products': [
        row('p1', 'BIOBALANCE SÉRUM VITAMINE C 30ML', 'Sérums', 120, 90),
        row('p2', 'BIOBALANCE SHAMPOING ARGAN', 'Soins capillaires', 80, 95),
      ],
    if (subject['product'] == null)
      'families': [
        row('Sérums', 'Sérums', null, 300, 250),
        row('Soins capillaires', 'Soins capillaires', null, 180, 260),
      ],
  },
  'stock':
      stock ??
      {
        'kind': 'network',
        'total': 940,
        'runningOut': [
          {
            'id': 'p1',
            'name': 'BIOBALANCE SÉRUM VITAMINE C 30ML',
            'family': 'Sérums',
            'imageId': null,
            'quantity': 6,
            'sold': 59,
            'perDay': 2.1,
            'daysLeft': 2,
          },
        ],
        'dead': {
          'count': 1,
          'items': [
            {
              'id': 'p9',
              'name': 'BIOBALANCE MASQUE ARGILE',
              'family': 'Masques',
              'imageId': null,
              'quantity': 24,
              'sold': 0,
              'perDay': 0,
              'daysLeft': null,
            },
          ],
        },
      },
  'money': withMoney
      ? {
          'owedMillimes': 184500,
          'pending': {'count': 2, 'amountMillimes': 60000},
          'paid': {'count': 5, 'amountMillimes': 210000},
        }
      : null,
  'insights': [
    {
      'key': 'TOP_FAMILY',
      'params': {'family': 'Sérums', 'share': 48, 'change': 20},
    },
    {
      'key': 'SILENT_STORES',
      'params': {'count': 2},
    },
    {
      'key': 'BEST_HOUR',
      'params': {'hour': 17, 'share': 18},
    },
  ],
};

Map<String, Object?> row(
  String id,
  String name,
  String? sub,
  int units,
  int before,
) => {
  'id': id,
  'name': name,
  'sub': sub,
  'imageId': null,
  'units': units,
  'sales': units ~/ 3,
  'rewardMillimes': units * 500,
  'beforeUnits': before,
  'beforeSales': before ~/ 3,
  'beforeRewardMillimes': before * 500,
  'lastAt': '2026-09-30T15:20:00.000Z',
};

Map<String, Object?> storesBoardFixture() => {
  'period': {'from': '2026-09-01', 'to': '2026-09-30'},
  'previous': {'from': '2026-08-02', 'to': '2026-08-31'},
  'today': '2026-09-30',
  'summary': {
    'total': 3,
    'active': 2,
    'pending': 1,
    'suspended': 0,
    'selling': 1,
    'silent': 1,
    'lowStock': 1,
  },
  'rows': [
    {
      'id': 's1',
      'name': 'Para Lac',
      'city': 'Tunis',
      'status': 'ACTIVE',
      'regionId': 'r1',
      'region': 'Nord',
      'groupId': null,
      'group': null,
      'members': 2,
      'units': 260,
      'sales': 90,
      'rewardMillimes': 120000,
      'beforeUnits': 300,
      'sellers': 2,
      'lastSaleAt': '2026-09-30T15:20:00.000Z',
      'low': 2,
      'out': 1,
      'change': -13,
    },
    {
      'id': 's2',
      'name': 'Pharma Quiet',
      'city': 'Sfax',
      'status': 'ACTIVE',
      'regionId': 'r2',
      'region': 'Sud',
      'groupId': 'g1',
      'group': 'Groupe Sfax',
      'members': 1,
      'units': 0,
      'sales': 0,
      'rewardMillimes': 0,
      'beforeUnits': 12,
      'sellers': 0,
      'lastSaleAt': '2026-08-20T10:00:00.000Z',
      'low': 0,
      'out': 0,
      'change': -100,
    },
    {
      'id': 's3',
      'name': 'Para Waiting',
      'city': 'Bizerte',
      'status': 'PENDING',
      'regionId': 'r1',
      'region': 'Nord',
      'groupId': null,
      'group': null,
      'members': 0,
      'units': 0,
      'sales': 0,
      'rewardMillimes': 0,
      'beforeUnits': 0,
      'sellers': 0,
      'lastSaleAt': null,
      'low': 0,
      'out': 0,
      'change': null,
    },
  ],
};
