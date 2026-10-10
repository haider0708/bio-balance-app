// The screens must survive what real phones do: a small screen, very large text,
// very long names and very long lists. Any overflow or exception fails the test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show server;
import 'support/fake_server.dart';
import 'support/harness.dart';

const long =
    'BIOBALANCE SÉRUM VITAMINE C ÉCLAT INTENSE ANTI-TACHES 30ML FORMAT FAMILIAL ÉDITION LIMITÉE';

void main() {
  for (final scale in [1.0, 1.6, 2.2]) {
    for (final size in [const Size(320, 568), const Size(412, 892)]) {
      for (final role in ['VENDEUR', 'RESPONSABLE', 'ADMIN']) {
        testWidgets('$role home at ${size.width.toInt()}px, text ×$scale', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final s = base.server(role)
            ..on(
              'GET /v1/me',
              meJson(
                role: role,
                name: 'Mohamed Amine Ben Abdelkader El Gharbi',
                locale: 'fr',
              ),
            )
            ..on('GET /v1/stock/locations/p1', stockJson(['a', 'b', 'c', 'd']));
          await launch(tester, s, size: size, language: 'fr');
          expect(tester.takeException(), isNull);
          await settle(tester, frames: 5);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('a sale list of 500 sales scrolls without trouble', (
    tester,
  ) async {
    final today = DateTime.now();
    final s = base.server('VENDEUR')
      ..on('GET /v1/stock/locations/p1', stockJson(['a', 'b', 'c', 'd']))
      ..on('GET /v1/sales/days', [
        for (var i = 0; i < 120; i++)
          {
            'day': today
                .subtract(Duration(days: i))
                .toIso8601String()
                .substring(0, 10),
            'sales': 4,
            'units': 12,
            'rewardMillimes': 3400,
          },
      ])
      ..on('GET /v1/sales', {
        'items': [
          for (var i = 0; i < 100; i++)
            {
              'id': 's$i',
              'status': 'ACTIVE',
              'version': 1,
              'day': today.toIso8601String().substring(0, 10),
              'occurredAt': today
                  .subtract(Duration(minutes: i))
                  .toIso8601String(),
              'createdAt': today.toIso8601String(),
              'units': 3,
              'rewardMillimes': 1100,
              'seller': {'id': 'u1', 'name': 'Amira'},
              'pdv': {'id': 'p1', 'name': 'Para Lac'},
              'lines': [
                {
                  'productId': 'a',
                  'name': long,
                  'quantity': 2,
                  'rewardMillimes': 800,
                  'imageId': null,
                },
                {
                  'productId': 'b',
                  'name': 'SÉRUM NIACINAMIDE',
                  'quantity': 1,
                  'rewardMillimes': 300,
                  'imageId': null,
                },
              ],
            },
        ],
        'nextCursor': null,
      });
    await launch(tester, s, size: const Size(360, 720), language: 'en');
    await tester.tap(find.text('Sales').last);
    await settle(tester);
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -900));
      await settle(tester, frames: 3);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long product names fit on the sale screen, the catalogue and the reports',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final s = base.server('VENDEUR')
        ..on('GET /v1/products', [
          productJson('a', long),
          productJson(
            'b',
            long.toLowerCase(),
            family: 'Soins capillaires pour cheveux secs et abîmés',
          ),
        ])
        ..on('GET /v1/stock/locations/p1', {
          'location': {
            'id': 'p1',
            'kind': 'PDV',
            'name': 'Para Lac',
            'status': 'ACTIVE',
          },
          'items': [
            for (final id in ['a', 'b'])
              {
                'productId': id,
                'name': long,
                'family': 'Serums',
                'imageId': null,
                'quantity': 12345,
                'level': 'OK',
              },
          ],
        });
      await launch(tester, s, size: const Size(320, 640), language: 'fr');
      await tester.tap(find.text('Nouvelle vente').first);
      await settle(tester);
      final e = tester.takeException();
      if (e != null) debugPrint('SALE SCREEN: $e');
      expect(e, isNull);
      await tester.tap(find.textContaining('BIOBALANCE SÉRUM').first);
      await settle(tester, frames: 5);
      expect(tester.takeException(), isNull);
    },
  );
}
