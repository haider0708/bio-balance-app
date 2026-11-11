// The buyer: places and receives the orders of its own para, and nothing else. It is a role of its own
// (no sales, no wallet) or a switch on a seller; the responsable (or the admin) decides which.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:biobalance/app/router.dart';
import 'package:biobalance/features/network/network_models.dart';
import 'package:flutter/material.dart'
    show FilledButton, SizedBox, TextFormField;
import 'package:flutter_test/flutter_test.dart';

import 'restock_flow_test.dart' show line;
import 'screenshots_test.dart' show loadFonts;
import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, Object?> meBuyer({
  String role = 'ACHETEUR',
  bool canOrder = true,
}) => {...meJson(role: role, name: 'Aya Acheteuse'), 'canOrder': canOrder};

Map<String, Object?> orderJson({
  String status = 'REQUESTED',
  Object? receiver,
}) => {
  'id': 'o1',
  'number': 'RS-2026-000012',
  'status': status,
  'source': status == 'REQUESTED' ? null : 'BIOBALANCE',
  'regionId': 'r1',
  'destination': {'id': 'p1', 'kind': 'PDV', 'name': 'Para Lac'},
  'supplier': null,
  'requestedBy': {'id': 'u1', 'name': 'Aya Acheteuse'},
  'receiver': receiver,
  'createdAt': DateTime.now().toIso8601String(),
  'receiptPhotoIds': <String>[],
  'documentIds': <String>[],
  'lines': [line('a', 'Serum C', 10, shipped: 10)],
};

FakeServer server(Map<String, Object?> me, {Map<String, Object?>? order}) =>
    FakeServer()
      ..on('GET /v1/me', me)
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/stock/locations/p1', {
        'location': {
          'id': 'p1',
          'kind': 'PDV',
          'name': 'Para Lac',
          'status': 'ACTIVE',
        },
        'items': [
          for (final (id, name, q, level) in [
            ('a', 'Serum C', 3, 'LOW'),
            ('b', 'Niacinamide', 0, 'LOW'),
            ('c', 'Shampoo', 20, 'OK'),
          ])
            {
              'productId': id,
              'name': name,
              'family': 'Serums',
              'quantity': q,
              'level': level,
            },
        ],
      })
      ..on('GET /v1/restocks', [order ?? orderJson()])
      ..on('GET /v1/restocks/o1', order ?? orderJson())
      ..on('GET /v1/products', [
        productJson('a', 'Serum C'),
        productJson('b', 'Niacinamide'),
      ]);

/// Close the app inside the test, so the timers its screens left behind run out.
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Object? body(FakeServer s, String route) => jsonDecode(
  jsonEncode(s.calls.lastWhere((c) => '${c.method} ${c.path}' == route).data),
);

void main() {
  setUpAll(loadFonts);

  testWidgets(
    'a buyer lands on its para: stock, what runs low, the orders, no sales',
    (tester) async {
      final s = server(meBuyer());
      await launch(tester, s, language: 'en');
      expect(find.text('Hello, Aya'), findsOneWidget);
      expect(find.text('Para Lac'), findsWidgets);
      expect(find.text('Order for my para'), findsOneWidget);
      expect(find.text('Running low'), findsOneWidget);
      expect(find.text('Serum C'), findsOneWidget);
      expect(find.text('Niacinamide'), findsOneWidget);
      expect(find.text('Shampoo'), findsNothing);
      expect(find.text('RS-2026-000012'), findsOneWidget);
      // Tabs: Home, Restocks, More. Nothing about sales or the wallet.
      expect(find.text('Sales'), findsNothing);
      expect(find.text('Wallet'), findsNothing);
      expect(find.text('Restocks'), findsOneWidget);
      expect(s.count('GET /v1/depots'), 0);
      await screenshot(tester, 'buyer-home');
    },
  );

  testWidgets(
    'a buyer orders for its own para: no place to choose, no grossiste',
    (tester) async {
      final s = server(meBuyer())..on('POST /v1/restocks', orderJson());
      await launch(tester, s, language: 'en');
      await tester.tap(find.text('Order for my para'));
      await settle(tester);
      expect(find.text('Your order is for this para'), findsOneWidget);
      expect(find.text('Deliver to'), findsNothing);
      expect(s.count('GET /v1/pdvs'), 0);
      expect(s.count('GET /v1/depots'), 0);
      await screenshot(tester, 'buyer-order');
    },
  );

  testWidgets(
    'a seller who may order has an Orders tab and the para panel; a plain seller has neither',
    (tester) async {
      final both = server(meBuyer(role: 'VENDEUR'));
      await launch(tester, both, language: 'en');
      expect(find.text('Restocks'), findsOneWidget);
      expect(find.text('Wallet'), findsOneWidget);
      expect(find.text('Order for my para'), findsOneWidget);
      expect(find.text('New sale'), findsWidgets);
    },
  );

  testWidgets('a plain seller has no Orders tab and no panel', (tester) async {
    final plain = server(meBuyer(role: 'VENDEUR', canOrder: false));
    await launch(tester, plain, language: 'en');
    expect(find.text('Restocks'), findsNothing);
    expect(find.text('Order for my para'), findsNothing);
  });

  testWidgets('the buyer confirms the delivery of its para', (tester) async {
    final s = server(meBuyer(), order: orderJson(status: 'SHIPPED'));
    final container = await launch(tester, s, language: 'en');
    unawaited(container.read(routerProvider).push('/restocks/o1'));
    await settle(tester);
    expect(find.text('Send the delivery paper'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('and steps aside when the responsable named someone else', (
    tester,
  ) async {
    final s = server(
      meBuyer(),
      order: orderJson(
        status: 'SHIPPED',
        receiver: {'id': 'u9', 'name': 'Sam Seller'},
      ),
    );
    final container = await launch(tester, s, language: 'en');
    unawaited(container.read(routerProvider).push('/restocks/o1'));
    await settle(tester);
    expect(find.text('Send the delivery paper'), findsNothing);
    await finish(tester);
  });

  testWidgets('the buyer cancels its own order while it waits', (tester) async {
    final s = server(meBuyer())
      ..on('POST /v1/restocks/o1/cancel', <String, Object?>{});
    final container = await launch(tester, s, language: 'en');
    unawaited(container.read(routerProvider).push('/restocks/o1'));
    await settle(tester);
    expect(find.text('Cancel the restock'), findsWidgets);
  });

  testWidgets('a responsable adds a buyer: the duty goes with the request', (
    tester,
  ) async {
    final s = server(meJson(role: 'RESPONSABLE'))
      ..on('GET /v1/pdvs', [
        {
          'id': 'p1',
          'name': 'Para Lac',
          'status': 'ACTIVE',
          'address': 'x',
          'city': 'Tunis',
          'regionId': 'r1',
          'memberCount': 2,
          'initialStock': 'APPROVED',
        },
      ])
      ..on('GET /v1/approvals', {
        'counts': <String, Object?>{},
        'items': <Object?>[],
      })
      ..on('POST /v1/pdvs/p1/members', {
        'id': 'u2',
        'name': 'Ines Achats',
        'email': 'ines@x.tn',
        'role': 'ACHETEUR',
        'status': 'PENDING',
      });
    final container = await launch(
      tester,
      s,
      language: 'en',
      size: const Size(412, 1800),
    );
    unawaited(container.read(routerProvider).push('/pdvs/p1/members/new'));
    await settle(tester);
    expect(find.text('What this person does'), findsOneWidget);
    expect(find.text('Seller and buyer'), findsOneWidget);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ines Achats');
    await tester.enterText(fields.at(1), 'ines@x.tn');
    await tester.enterText(fields.at(2), '21 345 678');
    await tester.tap(find.text('Buyer').first);
    await tester.pump();
    await screenshot(tester, 'buyer-add');
    await tester.tap(find.text('Send for approval'));
    await settle(tester);
    await tester.tap(find.text('Confirm and send'));
    await settle(tester);
    expect((body(s, 'POST /v1/pdvs/p1/members') as Map)['duties'], {
      'sells': false,
      'buys': true,
    });
  });

  testWidgets('the admin changes what a seller does', (tester) async {
    final s = server(meJson(role: 'ADMIN'))
      ..on('GET /v1/pdvs', <Object?>[])
      ..on('GET /v1/approvals', {
        'counts': <String, Object?>{},
        'items': <Object?>[],
      })
      ..on('POST /v1/users/u3/duties', {
        'id': 'u3',
        'name': 'Hanen Smiri',
        'email': 'h@x.tn',
        'role': 'VENDEUR',
        'status': 'ACTIVE',
        'canOrder': true,
      });
    final container = await launch(tester, s, language: 'en');
    final person = Person.fromJson({
      'id': 'u3',
      'name': 'Hanen Smiri',
      'email': 'hanen@x.tn',
      'phone': '+21621345678',
      'role': 'VENDEUR',
      'status': 'ACTIVE',
      'regionId': 'r1',
      'pdvId': 'p1',
      'activated': true,
    });
    unawaited(container.read(routerProvider).push('/people/u3', extra: person));
    await settle(tester);
    await tester.tap(find.text('Change what they do'));
    await settle(tester);
    await tester.tap(find.text('Seller and buyer').last);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    expect(body(s, 'POST /v1/users/u3/duties'), {'sells': true, 'buys': true});
  });
}
