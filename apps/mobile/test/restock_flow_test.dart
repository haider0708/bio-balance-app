// A store's restock: the admin sees what each grossiste holds before choosing one, the receiver
// confirms the delivery with its paper only, and the admin enters what arrived when approving.
import 'dart:async';
import 'dart:convert';

import 'package:biobalance/app/router.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'screenshots_test.dart' show loadFonts;
import 'support/harness.dart';

Map<String, Object?> line(
  String id,
  String name,
  int requested, {
  int? shipped,
}) => {
  'productId': id,
  'name': name,
  'family': 'Serums',
  'requested': requested,
  'shipped': shipped,
  'received': null,
  'approved': null,
};

Map<String, Object?> order(
  String status, {
  List<Map<String, Object?>>? lines,
}) => {
  'id': 'o1',
  'number': 'RS-2026-000012',
  'status': status,
  'source': status == 'REQUESTED' ? null : 'GROSSISTE',
  'regionId': 'r1',
  'destination': {'id': 'p1', 'kind': 'PDV', 'name': 'Para Lac'},
  'supplier': status == 'REQUESTED'
      ? null
      : {'id': 'd1', 'name': 'Dépôt Hedi', 'regionId': 'r1'},
  'requestedBy': {'id': 'x', 'name': 'Nora Ben Salah'},
  'createdAt': DateTime.now().toIso8601String(),
  'receiptPhotoIds': <String>[],
  'receiptNote': status == 'RECEIVED' ? 'One box was opened' : null,
  'lines':
      lines ??
      [
        line('a', 'Serum C', 10, shipped: 10),
        line('b', 'Niacinamide', 6, shipped: 2),
      ],
};

FakeServer server(String role, Map<String, Object?> o) => FakeServer()
  ..on('GET /v1/me', meJson(role: role))
  ..on('GET /v1/notifications/unread-count', {'unread': 0})
  ..on('GET /v1/dashboard', <String, Object?>{})
  ..on('GET /v1/restocks/o1', o);

Object? body(FakeServer s, String route) => jsonDecode(
  jsonEncode(s.calls.lastWhere((c) => '${c.method} ${c.path}' == route).data),
);

void main() {
  setUpAll(loadFonts);

  testWidgets(
    'the admin sees which grossiste holds the order before choosing',
    (tester) async {
      final s =
          server(
              'ADMIN',
              order(
                'REQUESTED',
                lines: [line('a', 'Serum C', 10), line('b', 'Niacinamide', 6)],
              ),
            )
            ..on('GET /v1/restocks/o1/suppliers', [
              {
                'id': 'd2',
                'name': 'Dépôt Sfax',
                'city': 'Sfax',
                'regionId': 'r3',
                'regionName': 'Sud',
                'missing': 0,
                'lines': [
                  {'productId': 'a', 'requested': 10, 'held': 40},
                  {'productId': 'b', 'requested': 6, 'held': 9},
                ],
              },
              {
                'id': 'd1',
                'name': 'Dépôt Hedi',
                'city': 'Tunis',
                'regionId': 'r1',
                'regionName': 'Nord',
                'missing': 1,
                'lines': [
                  {'productId': 'a', 'requested': 10, 'held': 50},
                  {'productId': 'b', 'requested': 6, 'held': 2},
                ],
              },
            ])
            ..on('POST /v1/restocks/o1/assign', <String, Object?>{});
      final container = await launch(tester, s, language: 'en');
      unawaited(container.read(routerProvider).push('/restocks/o1'));
      await settle(tester);
      await tester.tap(find.text('Assign to a grossiste'));
      await settle(tester);
      expect(find.text('Has everything'), findsOneWidget);
      expect(find.text('Short of 1 product'), findsOneWidget);
      expect(find.text('Niacinamide 2/6'), findsOneWidget);
      await screenshot(tester, '80-choose-grossiste');
      await tester.tap(find.text('Dépôt Sfax'));
      await settle(tester);
      expect(body(s, 'POST /v1/restocks/o1/assign'), {'depotId': 'd2'});
    },
  );

  testWidgets('the receiver confirms with the paper only, no counting', (
    tester,
  ) async {
    final s = server('RESPONSABLE', order('SHIPPED'));
    final container = await launch(tester, s, language: 'en');
    unawaited(container.read(routerProvider).push('/restocks/o1'));
    await settle(tester);
    await tester.tap(find.text('Confirm the delivery').first);
    await settle(tester);
    expect(find.text('What was sent'), findsOneWidget);
    expect(find.text('Quantities received'), findsNothing);
    await screenshot(tester, '81-receive-paper-only');
  });

  testWidgets('the admin enters what arrived, starting from what was sent', (
    tester,
  ) async {
    final s = server('ADMIN', order('RECEIVED'))
      ..on('POST /v1/restocks/o1/approve', <String, Object?>{});
    final container = await launch(tester, s, language: 'en');
    unawaited(container.read(routerProvider).push('/restocks/o1'));
    await settle(tester);
    expect(find.text('One box was opened'), findsOneWidget);
    await tester.tap(find.text('Approve the delivery'));
    await settle(tester);
    expect(find.text('Sent: 10'), findsOneWidget);
    expect(find.text('Sent: 2'), findsOneWidget);
    await screenshot(tester, '82-approve-delivery');
    await tester.tap(find.text('Confirm'));
    await settle(tester);
    expect(body(s, 'POST /v1/restocks/o1/approve'), {
      'lines': [
        {'productId': 'a', 'quantity': 10},
        {'productId': 'b', 'quantity': 2},
      ],
    });
  });
}
