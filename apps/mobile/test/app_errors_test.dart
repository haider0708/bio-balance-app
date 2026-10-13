// The admin sees the errors the app met, grouped by kind, with how often and where.
import 'package:biobalance/app/router.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

void main() {
  testWidgets('the admin reads the app errors, newest first', (tester) async {
    final server = FakeServer()
      ..on('GET /v1/me', meJson(role: 'ADMIN'))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/client-errors', [
        {
          'platform': 'android',
          'appVersion': '3.3.1 (41)',
          'message': 'Null check operator used on a null value',
          'stack': '#0 SaleScreen.build',
          'count': 3,
          'firstSeen': '2026-10-12T08:00:00.000Z',
          'lastSeen': '2026-10-13T09:00:00.000Z',
        },
      ]);
    final container = await launch(tester, server, language: 'en');
    container.read(routerProvider).go('/app-errors');
    await settle(tester);
    expect(find.text('App errors'), findsOneWidget);
    expect(
      find.text('Null check operator used on a null value'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Android · 3.3.1 (41) · 3 times'),
      findsOneWidget,
    );
  });

  testWidgets('no errors says so', (tester) async {
    final server = FakeServer()
      ..on('GET /v1/me', meJson(role: 'ADMIN'))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/client-errors', <Object>[]);
    final container = await launch(tester, server, language: 'fr');
    container.read(routerProvider).go('/app-errors');
    await settle(tester);
    expect(find.text('Aucune erreur'), findsOneWidget);
  });
}
