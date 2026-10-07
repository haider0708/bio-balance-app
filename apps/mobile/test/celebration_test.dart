// Every sale is celebrated: with a reward, without one, and when it is kept on the phone.
import 'package:biobalance/core/theme/app_theme.dart';
import 'package:biobalance/features/sales/celebration_screen.dart';
import 'package:biobalance/features/sales/sales_models.dart';
import 'package:biobalance/features/sales/sales_repository.dart';
import 'package:biobalance/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show loadFonts;
import 'support/harness.dart';

Widget app(Widget home) => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: RepaintBoundary(key: appBoundary, child: home),
);

Sale sale({required int reward}) => Sale.fromJson({
  'id': 's1',
  'status': 'ACTIVE',
  'version': 1,
  'day': '2026-10-07',
  'occurredAt': DateTime.now().toIso8601String(),
  'createdAt': DateTime.now().toIso8601String(),
  'units': 3,
  'rewardMillimes': reward,
  'seller': {'id': 'u', 'name': 'Amira'},
  'pdv': {'id': 'p', 'name': 'Para Lac'},
  'lines': [
    {
      'productId': 'a',
      'name': 'SÉRUM VITAMINE C 30ML',
      'quantity': 2,
      'rewardMillimes': reward == 0 ? 0 : reward - 500,
    },
    {
      'productId': 'b',
      'name': 'SÉRUM NIACINAMIDE',
      'quantity': 1,
      'rewardMillimes': reward == 0 ? 0 : 500,
    },
  ],
});

void main() {
  setUpAll(base.loadFonts);

  testWidgets('a sale without a reward still gets the show', (tester) async {
    await tester.pumpWidget(
      app(CelebrationScreen(outcome: SaleRecorded(sale(reward: 0)))),
    );
    await settle(tester, frames: 8);
    expect(find.text('Great sale!'), findsOneWidget);
    expect(find.textContaining('3 units'), findsWidgets);
    await screenshot(tester, '60-celebration-no-reward');
  });

  testWidgets('a sale kept on the phone gets confetti too', (tester) async {
    final pending = PendingSale(
      id: 'x',
      occurredAt: DateTime.now(),
      lines: const [PendingLine(productId: 'a', name: 'A', quantity: 2)],
    );
    await tester.pumpWidget(
      app(CelebrationScreen(outcome: SaleQueued(pending))),
    );
    await settle(tester, frames: 8);
    await screenshot(tester, '61-celebration-queued');
  });
}
