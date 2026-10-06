import 'package:flutter/material.dart' show TextFormField;
import 'package:biobalance/core/auth/session.dart';
import 'package:biobalance/features/sales/sales_outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

FakeServer vendeurServer() {
  final server = FakeServer()
    ..on('GET /v1/me', meJson())
    ..on('GET /v1/products', <Object>[productJson('a', 'Serum Vitamin C'), productJson('b', 'Shampoo Argan', family: 'Hair')])
    ..on('GET /v1/notifications/unread-count', {'unread': 0})
    ..on('GET /v1/dashboard', {
      'role': 'VENDEUR',
      'pdv': {'id': 'p1', 'name': 'Para Lac', 'status': 'ACTIVE'},
      'wallet': walletJson(balance: 5000, todayReward: 1200, todaySales: 2),
      'week': {'sales': 2, 'units': 6, 'rewardMillimes': 1200},
      'latest': <Object>[],
    });
  return server;
}

void main() {
  testWidgets('a team member records a sale and sees what it earned', (tester) async {
    final server = vendeurServer()
      ..handle('POST /v1/sales', (r) {
        final body = r.data as Map<String, dynamic>;
        return (
          status: 201,
          body: {
            'id': body['id'], 'status': 'ACTIVE', 'version': 1, 'day': '2026-10-06',
            'occurredAt': '2026-10-06T09:00:00.000Z', 'createdAt': '2026-10-06T09:00:00.000Z',
            'units': 3, 'rewardMillimes': 2100, 'replay': false,
            'seller': {'id': 'u1', 'name': 'Karim'}, 'pdv': {'id': 'p1', 'name': 'Para Lac'},
            'lines': [{'productId': 'a', 'name': 'Serum Vitamin C', 'quantity': 3, 'rewardMillimes': 2100}],
            'wallet': walletJson(balance: 7100, todayReward: 3300, todaySales: 3),
          },
        );
      });
    await launch(tester, server, language: 'en');

    expect(find.text('Hello, Karim'), findsOneWidget);
    expect(find.text('Para Lac'), findsOneWidget);

    await tester.tap(find.text('New sale').first);
    await settle(tester);
    expect(find.text('Serum Vitamin C'), findsOneWidget);

    await tester.tap(find.text('Serum Vitamin C'));
    await settle(tester, frames: 5);
    expect(find.textContaining('Review sale · 1 unit'), findsOneWidget);
    await tester.tap(find.textContaining('Review sale'));
    await settle(tester);

    await tester.tap(find.text('Record the sale'));
    await settle(tester, frames: 40);

    expect(find.text('Great sale!'), findsOneWidget);
    expect(find.textContaining('2.100 TND'), findsWidgets);
    expect(server.count('POST /v1/sales'), 1);
  });

  testWidgets('a sale made without a connection is kept and sent later, once', (tester) async {
    final server = vendeurServer();
    final container = await launch(tester, server, language: 'en');
    server.offline = true;

    await tester.tap(find.text('New sale').first);
    await settle(tester);
    await tester.tap(find.text('Shampoo Argan'));
    await settle(tester, frames: 5);
    await tester.tap(find.textContaining('Review sale'));
    await settle(tester);
    await tester.tap(find.text('Record the sale'));
    await settle(tester, frames: 40);

    expect(find.text('Saved on your phone'), findsOneWidget);
    expect(container.read(salesOutboxProvider), hasLength(1));

    // The connection comes back: the outbox sends the sale with the id it already has.
    server.offline = false;
    server.handle('POST /v1/sales', (r) => (status: 201, body: {'id': (r.data as Map<String, dynamic>)['id']}));
    final id = container.read(salesOutboxProvider).single.id;
    final sending = container.read(salesOutboxProvider.notifier).flush();
    await settle(tester, frames: 10);
    await sending;
    expect(container.read(salesOutboxProvider), isEmpty);
    expect(server.calls.where((c) => c.method == 'POST' && c.path == '/v1/sales').last.data['id'], id);
  });

  testWidgets('the interface speaks French when asked', (tester) async {
    await launch(tester, vendeurServer(), language: 'fr');
    expect(find.text('Bonjour, Karim'), findsOneWidget);
    expect(find.text('Nouvelle vente'), findsWidgets);
    expect(find.text('Gagné aujourd’hui'), findsOneWidget);
  });

  testWidgets('signed out, the app shows the sign-in screen and explains a wrong password', (tester) async {
    final server = FakeServer()
      ..on('POST /v1/auth/login', {'code': 'INVALID_CREDENTIALS', 'message': 'Incorrect email or password.'}, status: 401);
    await launch(tester, server, signedIn: false, language: 'en');
    expect(find.text('Welcome back'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'karim@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong-password');
    await tester.tap(find.text('Sign in').last);
    await settle(tester, frames: 10);
    expect(find.text('Incorrect email or password.'), findsOneWidget);
  });

  testWidgets('signing in lands on the home screen of the person’s role', (tester) async {
    final server = vendeurServer()
      ..on('POST /v1/auth/login', {'token': 'a-valid-token-of-sufficient-length-123456', 'expiresAt': '2027-01-01T00:00:00Z', 'me': meJson()}, status: 201);
    final container = await launch(tester, server, signedIn: false, language: 'en');
    await tester.enterText(find.byType(TextFormField).at(0), 'karim@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'a-long-password');
    await tester.tap(find.text('Sign in').last);
    await settle(tester, frames: 20);
    expect(find.text('Hello, Karim'), findsOneWidget);
    expect(container.read(sessionProvider).value?.me.name, 'Karim Ben Ali');
  });
}
