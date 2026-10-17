// The admin can change a decision for a few hours: put it back to waiting.
import 'package:biobalance/app/router.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

void main() {
  testWidgets('a recent decision can be put back to waiting', (tester) async {
    final until = DateTime.now()
        .add(const Duration(hours: 3))
        .toIso8601String();
    final server = FakeServer()
      ..on('GET /v1/me', meJson(role: 'ADMIN'))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/approvals', {
        'counts': <String, Object?>{},
        'items': <Object?>[],
      })
      ..on('GET /v1/approvals/history', {
        'items': [
          {
            'type': 'PDV',
            'id': 'p1',
            'name': 'Pharmacie Centre',
            'outcome': 'APPROVED',
            'decidedAt': DateTime.now().toIso8601String(),
            'change': {
              'options': ['reopen'],
              'until': until,
            },
          },
          {
            'type': 'PAYOUT',
            'id': 'x1',
            'name': 'Payout',
            'outcome': 'APPROVED',
            'decidedAt': DateTime.now().toIso8601String(),
            'change': null,
          },
        ],
        'nextBefore': null,
      })
      ..on('POST /v1/pdvs/p1/reopen', <String, Object?>{});
    final container = await launch(tester, server, language: 'en');
    container.read(routerProvider).go('/approvals');
    await settle(tester);
    await tester.tap(find.text('History'));
    await settle(tester);
    // Only the store can still be changed, not the payout.
    expect(find.text('Change'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await settle(tester);
    await tester.tap(find.text('Put back to waiting'));
    await settle(tester);
    expect(
      server.calls.any(
        (c) => c.method == 'POST' && c.path == '/v1/pdvs/p1/reopen',
      ),
      isTrue,
    );
  });
}
