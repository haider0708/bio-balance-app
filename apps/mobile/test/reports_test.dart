import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as shots show server;
import 'support/harness.dart';

void main() {
  testWidgets('reports opens, and every grouping renders', (tester) async {
    final s = shots.server('ADMIN')
      ..on('GET /v1/reports/sales', {
        'rows': [
          {'key': 'k', 'label': 'Parahouse Marsa', 'sales': 2, 'units': 210, 'rewardMillimes': 0},
        ],
        'totals': {'sales': 2, 'units': 210, 'rewardMillimes': 0},
      });
    await launch(tester, s, language: 'en');
    await tester.tap(find.text('More').last);
    await settle(tester);
    await tester.tap(find.text('Reports'));
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
