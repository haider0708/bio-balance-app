// A payout is asked with + and - only, in whole steps of 5 TND, from one step up to what is available.
import 'dart:async';

import 'package:biobalance/app/router.dart';
import 'package:flutter/material.dart'
    show FilledButton, IconButton, Key, Size, Text, TextField, VoidCallback;
import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show loadFonts;
import 'support/fake_server.dart';
import 'support/harness.dart';

FakeServer server({required int available}) => FakeServer()
  ..on('GET /v1/me', meJson())
  ..on('GET /v1/notifications/unread-count', {'unread': 0})
  ..on('GET /v1/dashboard', <String, Object?>{})
  ..on('GET /v1/wallet', walletJson(balance: available))
  ..on('GET /v1/wallet/entries', {'items': <Object?>[], 'nextCursor': null})
  ..on('GET /v1/payouts', <Object?>[])
  ..on('POST /v1/payouts', {'id': 'p1', 'status': 'PENDING'}, status: 201);

Future<void> openWallet(WidgetTester tester, FakeServer s) async {
  final container = await launch(
    tester,
    s,
    language: 'en',
    size: const Size(412, 900),
  );
  unawaited(container.read(routerProvider).push('/wallet'));
  await settle(tester);
}

/// The button's own `onPressed` (null when it is switched off).
VoidCallback? pressable(WidgetTester tester, String tooltip) => tester
    .widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    )
    .onPressed;

void main() {
  setUpAll(base.loadFonts);

  testWidgets(
    'the amount moves by 5 TND with + and -, never below one step or above the balance',
    (tester) async {
      final s = server(available: 18000);
      await openWallet(tester, s);
      await tester.tap(find.text('Request a payout'));
      await settle(tester);
      // No typing: there is no field, only the two buttons.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('5.000 TND'), findsOneWidget);
      // Down from the first step goes nowhere.
      expect(pressable(tester, 'Decrease the amount'), isNull);
      await tester.tap(find.byTooltip('Increase the amount'));
      await tester.pump();
      expect(find.text('10.000 TND'), findsOneWidget);
      await screenshot(tester, '90-payout-step');
      await tester.tap(find.byTooltip('Increase the amount'));
      await tester.pump();
      expect(find.text('15.000 TND'), findsOneWidget);
      // 18 TND is available: the most that can be asked is 15.
      expect(pressable(tester, 'Increase the amount'), isNull);
      expect(find.text('Up to 15.000 TND'), findsOneWidget);
      await tester.tap(find.byTooltip('Decrease the amount'));
      await tester.pump();
      expect(find.text('10.000 TND'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Request a payout').last,
      );
      await settle(tester);
      expect(
        s.calls
            .where((c) => c.path == '/v1/payouts' && c.method == 'POST')
            .single
            .data,
        {'amountMillimes': 10000},
      );
    },
  );

  testWidgets('holding + keeps going, up to the most that can be asked', (
    tester,
  ) async {
    final s = server(available: 100000);
    await openWallet(tester, s);
    await tester.tap(find.text('Request a payout'));
    await settle(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Increase the amount')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 550));
    await gesture.up();
    await tester.pump();
    // About five repeats, then released: well above one step, and the release added nothing.
    expect(find.text('5.000 TND'), findsNothing);
    final shown = tester
        .widget<Text>(find.byKey(const Key('payout-amount')))
        .data!;
    expect(shown, matches(RegExp(r'^\d+\.000 TND$')));
    expect(int.parse(shown.split('.').first) % 5, 0);
  });

  testWidgets('under 5 TND there is nothing to ask, and it says why', (
    tester,
  ) async {
    final s = server(available: 3000);
    await openWallet(tester, s);
    expect(find.text('A payout starts at 5.000 TND.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Request a payout'),
          )
          .onPressed,
      isNull,
    );
    expect(s.count('POST /v1/payouts'), 0);
  });
}
