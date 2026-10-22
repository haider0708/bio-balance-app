// The admin orders for any store: delivered now (with the proof) or left to the responsable, and a
// pasted list is matched to the catalogue before it is added.
import 'dart:async';
import 'dart:convert';

import 'package:biobalance/app/router.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

Object? sent(FakeServer s, String method, String path) => jsonDecode(
  jsonEncode(
    s.calls.lastWhere((c) => c.method == method && c.path == path).data,
  ),
);

Map<String, Object?> store() => {
  'id': 'p1',
  'name': 'Para Lac',
  'status': 'ACTIVE',
  'address': 'x',
  'city': 'Tunis',
  'regionId': 'r1',
  'memberCount': 2,
  'initialStock': 'APPROVED',
};

Map<String, Object?> created(String status) => {
  'id': 'o1',
  'number': 'RS-2026-000001',
  'status': status,
  'regionId': 'r1',
  'destination': {'id': 'p1', 'kind': 'PDV', 'name': 'Para Lac'},
  'requestedBy': {'id': 'x', 'name': 'Admin'},
  'createdAt': DateTime.now().toIso8601String(),
  'lines': <Object>[],
};

FakeServer server() => FakeServer()
  ..on('GET /v1/me', meJson(role: 'ADMIN'))
  ..on('GET /v1/notifications/unread-count', {'unread': 0})
  ..on('GET /v1/dashboard', <String, Object?>{})
  ..on('GET /v1/pdvs', [store()])
  ..on('GET /v1/depots', <Object>[])
  ..on('GET /v1/products', [
    productJson('a', 'Serum C'),
    productJson('b', 'Shampoo'),
  ])
  ..on('POST /v1/products/match', {
    'lines': [
      {
        'raw': '5 serum c',
        'quantity': 5,
        'status': 'MATCHED',
        'product': {'id': 'a', 'name': 'Serum C', 'family': 'Serums'},
        'candidates': <Object>[],
      },
      {
        'raw': '2 shampoo',
        'quantity': 2,
        'status': 'UNSURE',
        'product': null,
        'candidates': [
          {'id': 'b', 'name': 'Shampoo', 'family': 'Hair'},
        ],
      },
      {
        'raw': '9 banana split',
        'quantity': 9,
        'status': 'MISSING',
        'product': null,
        'candidates': <Object>[],
      },
    ],
  });

Future<void> openAndPaste(WidgetTester tester, FakeServer s) async {
  final container = await launch(tester, s, language: 'en');
  unawaited(container.read(routerProvider).push('/restocks/new', extra: 'p1'));
  await settle(tester);
  await tester.tap(find.text('Paste a list'));
  await settle(tester);
  await tester.enterText(find.byType(TextField).last, '5 serum c\n2 shampoo');
  await tester.pump();
  await tester.tap(find.text('Check the list'));
  await settle(tester);
}

void main() {
  testWidgets(
    'a pasted list shows what matched, what to check and what is missing',
    (tester) async {
      final s = server()..on('POST /v1/restocks', created('SHIPPED'));
      await openAndPaste(tester, s);
      expect(find.text('1 found, 1 to check, 1 not found'), findsOneWidget);
      expect(find.textContaining('Not found in the catalogue'), findsOneWidget);
      // Only the sure line is ready until the unsure one is chosen.
      expect(find.text('Add 1 products'), findsOneWidget);
      await tester.tap(find.text('Shampoo').last);
      await tester.pump();
      expect(find.text('Add 2 products'), findsOneWidget);
      await tester.tap(find.text('Add 2 products'));
      await settle(tester);
      expect(find.text('Serum C'), findsOneWidget);
      expect(find.text('Shampoo'), findsOneWidget);
    },
  );

  testWidgets(
    'the admin sends an order for a store and leaves the receipt to the responsable',
    (tester) async {
      final s = server()..on('POST /v1/restocks', created('SHIPPED'));
      await openAndPaste(tester, s);
      await tester.tap(find.text('Add 1 products'));
      await settle(tester);
      await tester.tap(find.text('Send it'));
      await tester.pump();
      await tester.tap(find.text('Send the order'));
      await settle(tester);
      final body = sent(s, 'POST', '/v1/restocks') as Map;
      expect(body['deliver'], 'later');
      expect(body['destId'], 'p1');
      expect((body['lines'] as List).single, {'productId': 'a', 'quantity': 5});
      expect(body.containsKey('photoIds'), isFalse);
    },
  );

  testWidgets(
    'delivered now needs the delivery note photo before it can be sent',
    (tester) async {
      final s = server();
      await openAndPaste(tester, s);
      await tester.tap(find.text('Add 1 products'));
      await settle(tester);
      // "Delivered" is the default: the button is the recording one, and stays off without a photo.
      expect(find.text('Add to the stock'), findsOneWidget);
      await tester.tap(find.text('Add to the stock'));
      await settle(tester, frames: 3);
      expect(s.count('POST /v1/restocks'), 0);
    },
  );
}
