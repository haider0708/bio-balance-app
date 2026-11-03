// A reward that is probably a typo (3000 TND instead of 3) cannot be saved by mistake: above 10 TND per
// unit the admin confirms, above 100 TND the form refuses, and an ordinary rate saves straight away.
import 'dart:async';
import 'dart:convert';

import 'package:biobalance/app/router.dart';
import 'package:biobalance/features/rewards/rewards_screens.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

FakeServer server() => FakeServer()
  ..on('GET /v1/me', meJson(role: 'ADMIN'))
  ..on('GET /v1/notifications/unread-count', {'unread': 0})
  ..on('GET /v1/dashboard', <String, Object?>{})
  ..on('GET /v1/products', [productJson('a', 'Serum C')])
  ..on('GET /v1/reward-rules', <Object>[])
  ..on('GET /v1/reward-rules/effective', <Object>[])
  ..on('POST /v1/reward-rules', {'id': 'r1'}, status: 201);

Future<FakeServer> openForm(WidgetTester tester) async {
  final s = server();
  final container = await launch(tester, s, language: 'en');
  unawaited(
    container
        .read(routerProvider)
        .push('/rewards/new', extra: const RewardPreset.family('Serums')),
  );
  await settle(tester);
  return s;
}

Future<void> type(WidgetTester tester, String amount) async {
  await tester.enterText(find.byType(TextField).first, amount);
  await tester.pump();
}

Map<String, Object?> sent(FakeServer s) =>
    jsonDecode(jsonEncode(s.calls.lastWhere((c) => c.method == 'POST').data))
        as Map<String, Object?>;

void main() {
  testWidgets('an ordinary rate is saved straight away', (tester) async {
    final s = await openForm(tester);
    await type(tester, '0.500');
    await tester.tap(find.text('Save the reward'));
    await settle(tester);
    expect(s.count('POST /v1/reward-rules'), 1);
    expect(sent(s)['amountMillimes'], 500);
    expect(sent(s).containsKey('confirmHigh'), isFalse);
  });

  testWidgets(
    '3000 TND per unit asks for a confirmation and sends nothing until it is given',
    (tester) async {
      final s = await openForm(tester);
      await type(tester, '3000');
      // The field already warns, and the amount is above the ceiling: it cannot be sent at all.
      expect(
        find.text('The most a reward can be is 100 TND per unit.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save the reward'));
      await settle(tester);
      expect(s.count('POST /v1/reward-rules'), 0);
    },
  );

  testWidgets('12 TND per unit is saved only after the admin confirms it', (
    tester,
  ) async {
    final s = await openForm(tester);
    await type(tester, '12');
    expect(find.textContaining('Check the amount'), findsOneWidget);
    await tester.tap(find.text('Save the reward'));
    await settle(tester);
    expect(find.text('Is this reward correct?'), findsOneWidget);
    expect(s.count('POST /v1/reward-rules'), 0);
    await tester.tap(find.text('Yes, save it'));
    await settle(tester);
    expect(s.count('POST /v1/reward-rules'), 1);
    expect(sent(s)['amountMillimes'], 12000);
    expect(sent(s)['confirmHigh'], isTrue);
  });

  testWidgets('cancelling the confirmation saves nothing', (tester) async {
    final s = await openForm(tester);
    await type(tester, '12');
    await tester.tap(find.text('Save the reward'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(s.count('POST /v1/reward-rules'), 0);
  });
}
