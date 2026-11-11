// The restock cycle as each person sees it: the admin marks any order on its way delivered (with or
// without a paper) and changes quantities with a reason; everyone else sends the delivery paper,
// which puts the order in front of the admin to verify.
import 'package:flutter/material.dart'
    show FilledButton, Scrollable, SizedBox, TextField;
import 'package:flutter_test/flutter_test.dart';

import 'package:biobalance/app/router.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

const _paper = '11111111-1111-4111-8111-111111111111';

Map<String, Object?> order({
  String status = 'SHIPPED',
  bool delivered = false,
  List<String> papers = const [_paper],
  List<Map<String, Object?>> changes = const [],
}) => {
  'id': 'o1',
  'number': 'RS-2026-000001',
  'status': status,
  'regionId': 'r1',
  'destination': {'id': 'p1', 'kind': 'PDV', 'name': 'Para Lac'},
  'requestedBy': {'id': 'x', 'name': 'Nora'},
  'createdAt': DateTime.now().toIso8601String(),
  'deliveredAt': delivered ? DateTime.now().toIso8601String() : null,
  'documentIds': papers,
  'changes': changes,
  'lines': [
    {
      'productId': 'a',
      'name': 'Serum C',
      'family': 'Serums',
      'requested': 4,
      'shipped': status == 'REQUESTED' ? null : 4,
    },
  ],
};

FakeServer server(Map<String, Object?> o, {String role = 'ADMIN'}) =>
    FakeServer()
      ..on('GET /v1/me', meJson(role: role))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/products', <Object?>[])
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
      }, status: 201)
      ..on('POST /v1/restocks/o1/quantities', o, status: 201);

Future<void> open(WidgetTester tester, FakeServer s) async {
  final container = await launch(tester, s, language: 'en');
  container.read(routerProvider).go('/restocks/o1');
  await settle(tester);
}

Future<void> close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 6));
}

Future<void> reveal(WidgetTester tester, String text) =>
    tester.scrollUntilVisible(
      find.text(text),
      300,
      scrollable: find.byType(Scrollable).first,
    );

void main() {
  testWidgets('the same order in French', (tester) async {
    final container = await launch(tester, server(order()), language: 'fr');
    container.read(routerProvider).go('/restocks/o1');
    await settle(tester);
    await reveal(tester, 'Marquer comme livré');
    await screenshot(tester, 'restock_admin_on_its_way_fr');
    await close(tester);
  });

  testWidgets('the admin marks an order on its way delivered with its papers', (
    tester,
  ) async {
    final s = server(order());
    await open(tester, s);
    expect(find.text('On its way'), findsOneWidget);
    await reveal(tester, 'Mark as delivered');
    await screenshot(tester, 'restock_admin_on_its_way');
    await tester.tap(find.text('Mark as delivered'));
    await settle(tester);
    await screenshot(tester, 'restock_admin_mark_delivered');
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
    await close(tester);
  });

  testWidgets('the admin marks it delivered with no paper at all', (
    tester,
  ) async {
    final s = server(order(papers: const []));
    await open(tester, s);
    await reveal(tester, 'Mark as delivered');
    await tester.tap(find.text('Mark as delivered'));
    await settle(tester);
    final send = find.widgetWithText(FilledButton, 'Add to the stock');
    expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
    expect(find.text('Add a photo or a document to send.'), findsNothing);
    await tester.tap(send);
    await settle(tester);
    final call = s.calls.lastWhere((c) => c.path == '/v1/restocks/o1/receipt');
    expect((call.data as Map)['photoIds'], isEmpty);
    await close(tester);
  });

  testWidgets(
    'the old "mark as delivered" step is gone: one button for the admin',
    (tester) async {
      await open(tester, server(order(delivered: true)));
      expect(find.text('Delivered, to be confirmed'), findsOneWidget);
      await reveal(tester, 'Mark as delivered');
      expect(find.text('Mark as delivered'), findsOneWidget);
      await close(tester);
    },
  );

  for (final role in ['RESPONSABLE', 'ORDERS']) {
    testWidgets(
      'on its way, $role sends the delivery paper and cannot close the order',
      (tester) async {
        await open(tester, server(order(), role: role));
        await reveal(tester, 'Send the delivery paper');
        await screenshot(tester, 'restock_${role.toLowerCase()}_on_its_way');
        expect(find.text('Mark as delivered'), findsNothing);
        expect(find.text('Change quantities'), findsNothing);
        // The paper goes through the delivery step, not the plain papers.
        expect(find.text('Add papers'), findsNothing);
        await tester.tap(find.text('Send the delivery paper'));
        await settle(tester);
        // Without a paper there is nothing to send.
        final send = find.widgetWithText(FilledButton, 'Send to BioBalance');
        expect(tester.widget<FilledButton>(send).onPressed, isNull);
        await close(tester);
      },
    );
  }

  testWidgets('before it leaves, the responsable adds papers to the order', (
    tester,
  ) async {
    await open(tester, server(order(status: 'REQUESTED'), role: 'RESPONSABLE'));
    await reveal(tester, 'Add papers');
    expect(find.text('Send the delivery paper'), findsNothing);
    await close(tester);
  });

  testWidgets(
    'a paper was sent: the order says so and the admin marks it delivered',
    (tester) async {
      await open(tester, server(order(status: 'RECEIVED')));
      expect(find.text('Paper sent, to verify'), findsOneWidget);
      await reveal(tester, 'Mark as delivered');
      await screenshot(tester, 'restock_admin_paper_sent');
      expect(find.text('Ask for the paper again'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets(
    'the admin changes the quantities of a waiting order with a reason',
    (tester) async {
      final s = server(
        order(
          status: 'REQUESTED',
          changes: [
            {
              'at': DateTime.now().toIso8601String(),
              'by': 'Amel Admin',
              'delivered': false,
              'note': 'Six left at the grossiste',
              'lines': [
                {'productId': 'a', 'name': 'Serum C', 'before': 10, 'after': 4},
              ],
            },
          ],
        ),
      );
      await open(tester, s);
      // What was changed before, by whom and why, is on the order.
      await reveal(tester, 'Six left at the grossiste');
      expect(find.text('10 → 4'), findsOneWidget);
      await reveal(tester, 'Change quantities');
      await screenshot(tester, 'restock_admin_requested');
      await tester.tap(find.text('Change quantities'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await settle(tester);
      // No reason, no change.
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(find.byType(TextField).last, 'Asked by the para');
      await tester.pump();
      await tester.tap(save);
      await settle(tester);
      final call = s.calls.lastWhere(
        (c) => c.path == '/v1/restocks/o1/quantities',
      );
      expect(call.data, {
        'lines': [
          {'productId': 'a', 'quantity': 4},
        ],
        'note': 'Asked by the para',
      });
      await close(tester);
    },
  );
}
