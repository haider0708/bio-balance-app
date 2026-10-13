// The screenshots the App Store and Google Play ask for, at their exact sizes, in French and
// English, from the real screens with sample data. Not part of the normal run:
//
//   STORE_SHOTS=1 flutter test test/store_screenshots_test.dart
//
// Written to build/store/<device>/<language>/.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show BackButton, Size, SizedBox;
import 'package:biobalance/core/widgets/components.dart' show StatTile;
import 'package:flutter_test/flutter_test.dart';

import 'analytics_test.dart' as analytics show analyticsServer;
import 'screenshots_test.dart' as base show loadFonts, server;
import 'support/fake_server.dart';
import 'support/harness.dart';

/// Logical size and pixel ratio of each store format.
const devices = {
  // App Store: iPhone 6.9" (1290 × 2796) and iPad 13" (2064 × 2752).
  'iphone-6.9': (Size(430, 932), 3.0),
  'ipad-13': (Size(1032, 1376), 2.0),
  // Google Play phone (1080 × 1920, exactly 9:16: the Play Console form asks for 16:9 or 9:16).
  'android-phone': (Size(360, 640), 3.0),
};

/// A few products of the real catalogue (apps/api/catalog), with their photos.
const _shown = [
  '8697711600760', // Super Serum Pure Vitamine C
  '8697711602030', // Super Plump
  '8697711621819', // Hello Clean eau micellaire
  '8697711011269', // Lipojen Candy Crush
  '8697711700187', // Shampoing Aloe Vera
  '8697711600777', // Super Serum Hyaluronic 3D
];

FakeServer _catalog(FakeServer s) {
  final all = (jsonDecode(
    File('../api/catalog/products.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();
  final products = [
    for (final b in _shown) all.firstWhere((p) => p['barcode'] == b),
  ];
  for (final p in products) {
    s.files['/v1/media/${p['barcode']}'] = File('../api/catalog/${p['image']}')
        .readAsBytesSync();
  }
  return s
    ..on('GET /v1/products', [
      for (final p in products)
        {
          'id': p['barcode'],
          'reference': p['reference'],
          'name': p['name'],
          'family': p['family'],
          'barcode': p['barcode'],
          'imageId': p['barcode'],
          'active': true,
        },
    ])
    ..on('GET /v1/stock/locations/p1', {
      'location': {
        'id': 'p1',
        'kind': 'PDV',
        'name': 'Para Lac',
        'status': 'ACTIVE',
      },
      'items': [
        for (final p in products)
          {
            'productId': p['barcode'],
            'name': p['name'],
            'family': p['family'],
            'imageId': p['barcode'],
            'quantity': 24,
            'level': 'OK',
          },
      ],
    });
}

/// Lets the engine decode the product photos before a screenshot.
Future<void> _photos(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

FakeServer _seller() => _catalog(base.server('VENDEUR'))
  ..handle(
    'POST /v1/sales',
    (r) => (
      status: 201,
      body: {
        'id': (r.data as Map<String, dynamic>)['id'],
        'status': 'ACTIVE',
        'version': 1,
        'day': '2026-10-06',
        'occurredAt': DateTime.now().toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
        'units': 1,
        'rewardMillimes': 800,
        'seller': {'id': 'u1', 'name': 'Amira'},
        'pdv': {'id': 'p1', 'name': 'Para Lac'},
        'lines': [
          {
            'productId': '8697711600760',
            'name': 'SUPER SERUM PURE VITAMINE C 30ML',
            'quantity': 1,
            'rewardMillimes': 800,
          },
        ],
        'wallet': walletJson(balance: 49300, todayReward: 6000, todaySales: 4),
      },
    ),
  );

void main() {
  setUpAll(base.loadFonts);
  final skip = !Platform.environment.containsKey('STORE_SHOTS');

  for (final MapEntry(key: device, value: (size, ratio)) in devices.entries) {
    for (final lang in ['fr', 'en']) {
      final fr = lang == 'fr';
      Future<void> shot(WidgetTester tester, String name) =>
          screenshot(tester, '../store/$device/$lang/$name', pixelRatio: ratio);

      testWidgets('store: team member, $device, $lang', skip: skip, (
        tester,
      ) async {
        await launch(
          tester,
          _seller(),
          language: lang,
          size: size,
          pixelRatio: ratio,
        );
        await shot(tester, '01-home');
        await tester.tap(find.text(fr ? 'Nouvelle vente' : 'New sale').first);
        await settle(tester);
        await _photos(tester);
        await tester.tap(find.text('SUPER SERUM PURE VITAMINE C 30ML'));
        await settle(tester, frames: 5);
        await _photos(tester);
        await shot(tester, '02-new-sale');
        await tester.tap(
          find.textContaining(fr ? 'Vérifier la vente' : 'Review sale'),
        );
        await settle(tester);
        await tester.tap(
          find.text(fr ? 'Enregistrer la vente' : 'Record the sale'),
        );
        await settle(tester, frames: 14);
        await shot(tester, '03-reward');
        // Photos stay cached for five minutes after their screen closes: let that time pass.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 6));
      });

      testWidgets('store: admin, $device, $lang', skip: skip, (tester) async {
        await launch(
          tester,
          analytics.analyticsServer(),
          language: lang,
          size: size,
          pixelRatio: ratio,
        );
        await shot(tester, '04-network-home');
        await tester.tap(
          find.widgetWithText(StatTile, fr ? 'Aujourd’hui' : 'Today'),
        );
        await settle(tester);
        await shot(tester, '05-analytics');
        await tester.tap(find.byType(BackButton));
        await settle(tester);
        final stores = find.widgetWithText(
          StatTile,
          fr ? 'PDV actifs' : 'Active PDVs',
        );
        await tester.ensureVisible(stores);
        await settle(tester, frames: 5);
        await tester.tap(stores);
        await settle(tester);
        await shot(tester, '06-points-of-sale');
      });
    }
  }
}
