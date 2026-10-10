// The screenshots the App Store and Google Play ask for, at their exact sizes, in French and
// English, from the real screens with sample data. Not part of the normal run:
//
//   STORE_SHOTS=1 flutter test test/store_screenshots_test.dart
//
// Written to build/store/<device>/<language>/.
import 'dart:io';

import 'package:flutter/material.dart' show BackButton, Size;
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
  // Google Play phone (1080 × 2160; the long side may be at most twice the short one).
  'android-phone': (Size(360, 720), 3.0),
};

FakeServer _seller() => base.server('VENDEUR')
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
            'productId': 'a',
            'name': 'SÉRUM VITAMINE C',
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
        await tester.tap(find.text('BIOBALANCE SÉRUM VITAMINE C 30ML'));
        await settle(tester, frames: 5);
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
