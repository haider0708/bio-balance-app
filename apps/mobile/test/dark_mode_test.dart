// The same screens in dark mode, for a visual check.
import 'dart:ui' show Brightness;

import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show loadFonts, server;
import 'support/fake_server.dart';
import 'support/harness.dart';

void main() {
  setUpAll(base.loadFonts);

  testWidgets('dark: admin home and rewards', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
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
      ]);
    await launch(tester, s, language: 'en');
    await screenshot(tester, '40-dark-admin-home');
    await tester.tap(find.text('More').last);
    await settle(tester);
    await tester.tap(find.text('Rewards'));
    await settle(tester);
    await screenshot(tester, '41-dark-rewards');
  });

  testWidgets('dark: team member', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final s = base.server('VENDEUR')
      ..on('GET /v1/stock/locations/p1', stockJson(['a', 'b', 'c', 'd']));
    await launch(tester, s, language: 'en');
    await screenshot(tester, '42-dark-vendeur-home');
    await tester.tap(find.text('New sale').first);
    await settle(tester);
    await screenshot(tester, '43-dark-sell');
  });
}
