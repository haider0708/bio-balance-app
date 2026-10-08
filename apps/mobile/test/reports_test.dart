import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as shots show server;
import 'support/harness.dart';

void main() {
  testWidgets('reports opens, and every grouping renders', (tester) async {
    final s = shots.server('ADMIN')
      ..on('GET /v1/reports/insights', {
        'totals': {
          'sales': 0,
          'units': 0,
          'rewardMillimes': 0,
          'activeStores': 0,
          'activeSellers': 0,
          'unitsPerSale': 0,
          'previousUnits': 0,
        },
        'weekdays': [
          for (var d = 0; d < 7; d++) {'weekday': d, 'units': 0},
        ],
        'families': <Object>[],
        'stores': <Object>[],
        'products': <Object>[],
        'sellers': <Object>[],
        'stock': {
          'runningOut': <Object>[],
          'dead': {'count': 0, 'items': <Object>[]},
        },
        'insights': <Object>[],
      })
      ..on('GET /v1/reports/sales', {
        'rows': [
          {
            'key': 'k',
            'label': 'Parahouse Marsa',
            'sales': 2,
            'units': 210,
            'rewardMillimes': 0,
          },
        ],
        'totals': {'sales': 2, 'units': 210, 'rewardMillimes': 0},
      });
    await launch(tester, s, language: 'en');
    await openAdminNav(tester);
    await tester.tap(find.text('Reports').last);
    await settle(tester);
    await tester.ensureVisible(find.text('Details'));
    await settle(tester, frames: 3);
    await tester.tap(find.text('Details'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Parahouse Marsa'), findsOneWidget);
    for (final label in ['Last 7 days', 'Last month']) {
      await tester.tap(find.text(label));
      await settle(tester);
      expect(tester.takeException(), isNull);
    }
  });
}
