// The admin controls every order: on its way, she completes the delivery herself, starting from the
// papers already on the order, and the order shows "Delivered, to be confirmed" once it was marked.
import 'package:flutter/material.dart' show FilledButton, Scrollable, SizedBox;
import 'package:flutter_test/flutter_test.dart';

import 'package:biobalance/app/router.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

const _paper = '11111111-1111-4111-8111-111111111111';

Map<String, Object?> order({required bool delivered, List<String>? papers}) => {
  'id': 'o1',
  'number': 'RS-2026-000001',
  'status': 'SHIPPED',
  'regionId': 'r1',
  'destination': {'id': 'p1', 'kind': 'PDV', 'name': 'Para Lac'},
  'requestedBy': {'id': 'x', 'name': 'Nora'},
  'createdAt': DateTime.now().toIso8601String(),
  'deliveredAt': delivered ? DateTime.now().toIso8601String() : null,
  'documentIds': papers ?? [_paper],
  'lines': [
    {
      'productId': 'a',
      'name': 'Serum C',
      'family': 'Serums',
      'requested': 4,
      'shipped': 4,
    },
  ],
};

FakeServer server(Map<String, Object?> o) => FakeServer()
  ..on('GET /v1/me', meJson(role: 'ADMIN'))
  ..on('GET /v1/notifications/unread-count', {'unread': 0})
  ..on('GET /v1/dashboard', <String, Object?>{})
  ..on('GET /v1/restocks', [o])
  ..on('GET /v1/restocks/o1', o)
  ..on('GET /v1/media/$_paper/info', {
    'id': _paper,
    'mime': 'application/pdf',
    'fileName': 'bon.pdf',
    'size': 10,
  })
  ..on('POST /v1/restocks/o1/receipt', {
    ...o,
    'status': 'COMPLETED',
  }, status: 201);

void main() {
  testWidgets('on its way, the admin completes a store order with its papers', (
    tester,
  ) async {
    final s = server(order(delivered: false));
    final container = await launch(tester, s, language: 'en');
    container.read(routerProvider).go('/restocks/o1');
    await settle(tester);
    expect(find.text('On its way'), findsOneWidget);
    expect(find.text('Complete the delivery'), findsOneWidget);
    await tester.tap(find.text('Complete the delivery'));
    await settle(tester);
    // The paper already on the order is there, and the order can be sent as it is.
    expect(find.text('1 of 5 photos or documents'), findsOneWidget);
    final send = find.widgetWithText(FilledButton, 'Add to the stock');
    expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await settle(tester);
    final call = s.calls.lastWhere((c) => c.path == '/v1/restocks/o1/receipt');
    expect((call.data as Map)['photoIds'], [_paper]);
    expect((call.data as Map)['lines'], [
      {'productId': 'a', 'quantity': 4},
    ]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  });

  testWidgets('an order marked delivered says so while it waits', (
    tester,
  ) async {
    final s = server(order(delivered: true));
    final container = await launch(tester, s, language: 'en');
    container.read(routerProvider).go('/restocks/o1');
    await settle(tester);
    expect(find.text('Delivered, to be confirmed'), findsOneWidget);
    expect(find.text('On its way'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Complete the delivery'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Complete the delivery'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  });
}
