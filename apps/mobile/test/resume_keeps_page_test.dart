// Coming back from the camera, the gallery or the file chooser, the app asks who is signed in again. The page
// the person was on must stay (a delivery paper being added, a restock being shipped), not fall back to the
// order it came from.
import 'dart:async';

import 'package:biobalance/app/router.dart';
import 'package:biobalance/core/auth/session.dart';
import 'package:biobalance/features/restock/restock_models.dart';
import 'package:flutter/material.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, Object?> order() => {
  'id': 'o1',
  'number': 'RS-2026-000001',
  'status': 'SHIPPED',
  'regionId': 'r1',
  'destination': {'id': 'p1', 'kind': 'PDV', 'name': 'Para Lac'},
  'requestedBy': {'id': 'x', 'name': 'Nora'},
  'createdAt': DateTime.now().toIso8601String(),
  'lines': <Object>[],
};

void main() {
  testWidgets('a page waiting for its order stays when the app is resumed', (
    tester,
  ) async {
    final s = FakeServer()
      ..on('GET /v1/me', meJson(role: 'ADMIN'))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/restocks/o1', order());
    final container = await launch(tester, s, language: 'en');
    unawaited(
      container
          .read(routerProvider)
          .push('/restocks/o1/papers', extra: RestockOrder.fromJson(order())),
    );
    await settle(tester);
    expect(find.text('Add papers'), findsWidgets);
    expect(find.text('0 of 5 photos or documents'), findsOneWidget);

    // What the app does every time it comes back to the foreground.
    await tester.runAsync(container.read(sessionProvider.notifier).refresh);
    await settle(tester);

    expect(find.text('0 of 5 photos or documents'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
