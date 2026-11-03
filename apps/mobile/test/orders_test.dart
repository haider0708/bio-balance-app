// The order manager: sees every para's stock, asks a para what it needs, prepares an order for the
// admin to approve in one tap, and follows it to the delivery. It has no money and no accounts.
import 'dart:async';
import 'dart:convert';

import 'package:biobalance/app/router.dart';
import 'package:flutter/material.dart'
    show BottomSheet, FilledButton, TextField;
import 'package:flutter_test/flutter_test.dart';

import 'restock_flow_test.dart' show line;
import 'screenshots_test.dart' show loadFonts;
import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, Object?> paraJson({
  String id = 'p1',
  String name = 'Para Lac',
  int low = 1,
  int out = 1,
  int open = 0,
}) => {
  'id': id,
  'name': name,
  'address': '1 rue',
  'city': 'Tunis',
  'phone': null,
  'region': {'id': 'r1', 'name': 'Nord'},
  'group': {'id': 'g1', 'name': 'Groupe Nord'},
  'stock': {'products': 3, 'units': 33, 'low': low, 'out': out},
  'sold7Days': 12,
  'openOrders': open,
};

Map<String, Object?> detailJson() => {
  ...paraJson(open: 1),
  'stock': {
    'products': 3,
    'units': 33,
    'low': 1,
    'out': 1,
    'lines': [
      {
        'productId': 'a',
        'name': 'Serum C',
        'family': 'Serums',
        'quantity': 3,
        'level': 'LOW',
        'sold7Days': 7,
        'coverDays': 3,
      },
      {
        'productId': 'b',
        'name': 'Niacinamide',
        'family': 'Serums',
        'quantity': 0,
        'level': 'OUT',
        'sold7Days': 0,
        'coverDays': null,
      },
    ],
  },
  'orders': [
    {
      'id': 'o1',
      'number': 'RS-2026-000012',
      'status': 'REQUESTED',
      'units': 16,
      'proposed': false,
      'delivered': false,
      'createdAt': DateTime.now().toIso8601String(),
    },
  ],
  'contacts': [
    {
      'id': 'c1',
      'name': 'Nora Ben Salah',
      'role': 'RESPONSABLE',
      'phone': '+21612345678',
    },
  ],
  'lastAskedAt': null,
};

Map<String, Object?> orderJson({Map<String, Object?>? proposal}) => {
  'id': 'o1',
  'number': 'RS-2026-000012',
  'status': 'REQUESTED',
  'source': null,
  'regionId': 'r1',
  'destination': {'id': 'p1', 'kind': 'PDV', 'name': 'Para Lac'},
  'supplier': null,
  'requestedBy': {'id': 'x', 'name': 'Nora Ben Salah'},
  'createdAt': DateTime.now().toIso8601String(),
  'receiptPhotoIds': <String>[],
  'proposal': proposal,
  'documentIds': <String>[],
  'lines': [line('a', 'Serum C', 10), line('b', 'Niacinamide', 6)],
};

FakeServer server(String role, {Map<String, Object?>? order}) => FakeServer()
  ..on('GET /v1/me', meJson(role: role, name: 'Omar Orders'))
  ..on('GET /v1/notifications/unread-count', {'unread': 0})
  ..on('GET /v1/dashboard', <String, Object?>{})
  ..on('GET /v1/orders/overview', {
    'orders': {
      'requested': 2,
      'proposed': 1,
      'toShip': 0,
      'onTheRoad': 3,
      'delivered': 1,
      'toApprove': 0,
    },
    'paras': {'total': 3, 'low': 1, 'out': 1},
    'attention': [paraJson()],
  })
  ..on('GET /v1/orders/paras', [
    paraJson(),
    paraJson(id: 'p2', name: 'Para Marsa', low: 0, out: 0),
  ])
  ..on('GET /v1/orders/paras/p1', detailJson())
  ..on('GET /v1/restocks', [orderJson()])
  ..on('GET /v1/restocks/o1', order ?? orderJson())
  ..on('GET /v1/returns', <Object?>[])
  ..on('GET /v1/depots', <Object?>[]);

Object? body(FakeServer s, String route) => jsonDecode(
  jsonEncode(s.calls.lastWhere((c) => '${c.method} ${c.path}' == route).data),
);

Future<void> open(WidgetTester tester, FakeServer s, String path) async {
  final container = await launch(tester, s, language: 'en');
  unawaited(container.read(routerProvider).push(path));
  await settle(tester);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('the home shows what waits and the paras to watch', (
    tester,
  ) async {
    final s = server('ORDERS');
    await launch(tester, s, language: 'en');
    expect(find.text('Hello, Omar'), findsOneWidget);
    expect(find.text('Order manager'), findsOneWidget);
    expect(find.text('To prepare'), findsOneWidget);
    expect(find.text('Paras to watch'), findsOneWidget);
    expect(find.text('Para Lac'), findsOneWidget);
    expect(find.text('1 out'), findsOneWidget);
    expect(find.text('1 low'), findsOneWidget);
    await screenshot(tester, 'orders-home');
  });

  testWidgets('the paras board lists every para and can keep the low ones', (
    tester,
  ) async {
    final s = server('ORDERS');
    await launch(tester, s, language: 'en');
    await tester.tap(find.text('Paras').last);
    await settle(tester);
    expect(find.text('Para Lac'), findsOneWidget);
    expect(find.text('Para Marsa'), findsOneWidget);
    await screenshot(tester, 'orders-paras');
    await tester.tap(find.text('Low or out'));
    await settle(tester);
    final asked = s.calls.lastWhere((c) => c.path == '/v1/orders/paras');
    expect(asked.queryParameters['low'], 'true');
  });

  testWidgets('a para shows its stock, who to call, and asks what it needs', (
    tester,
  ) async {
    final s = server('ORDERS')
      ..on('POST /v1/orders/paras/p1/ask', {'ok': true});
    await open(tester, s, '/paras/p1');
    expect(find.text('Serum C'), findsOneWidget);
    expect(find.text('Niacinamide'), findsOneWidget);
    expect(find.textContaining('about 3 days left'), findsOneWidget);
    expect(find.text('Nora Ben Salah'), findsOneWidget);
    await screenshot(tester, 'orders-para');
    await tester.tap(find.text('Ask what they need'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Anything for May?');
    await tester.tap(find.text('Send'));
    await settle(tester);
    expect(body(s, 'POST /v1/orders/paras/p1/ask'), {
      'message': 'Anything for May?',
    });
  });

  testWidgets('the order manager proposes a direct shipment with a note', (
    tester,
  ) async {
    final s = server('ORDERS')
      ..on('POST /v1/restocks/o1/propose', <String, Object?>{});
    await open(tester, s, '/restocks/o1');
    await tester.tap(find.text('Propose to send from BioBalance'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Truck on Monday');
    await tester.tap(find.text('Send the proposal'));
    await settle(tester);
    expect(body(s, 'POST /v1/restocks/o1/propose'), {
      'source': 'BIOBALANCE',
      'note': 'Truck on Monday',
    });
  });

  testWidgets(
    'once proposed, it waits for the admin and cannot propose again',
    (tester) async {
      final s = server(
        'ORDERS',
        order: orderJson(
          proposal: {
            'source': 'BIOBALANCE',
            'supplier': null,
            'by': {'id': 'u1', 'name': 'Omar Orders'},
            'at': DateTime.now().toIso8601String(),
            'note': null,
          },
        ),
      );
      await open(tester, s, '/restocks/o1');
      expect(find.text('Proposal sent: waiting for the admin'), findsOneWidget);
      expect(find.text('Propose to send from BioBalance'), findsNothing);
    },
  );

  testWidgets('the admin approves a proposal in one tap', (tester) async {
    final s = server(
      'ADMIN',
      order: orderJson(
        proposal: {
          'source': 'BIOBALANCE',
          'supplier': null,
          'by': {'id': 'u9', 'name': 'Omar Orders'},
          'at': DateTime.now().toIso8601String(),
          'note': 'Truck on Monday',
        },
      ),
    )..on('POST /v1/restocks/o1/approve-proposal', <String, Object?>{});
    await open(tester, s, '/restocks/o1');
    expect(find.text('Proposed by'), findsOneWidget);
    expect(find.text('Truck on Monday'), findsOneWidget);
    await tester.tap(find.text('Approve the proposal'));
    await settle(tester);
    expect(
      s.calls.any((c) => c.path == '/v1/restocks/o1/approve-proposal'),
      isTrue,
    );
  });

  testWidgets('the admin refuses a proposal with a reason', (tester) async {
    final s = server(
      'ADMIN',
      order: orderJson(
        proposal: {
          'source': 'BIOBALANCE',
          'supplier': null,
          'by': {'id': 'u9', 'name': 'Omar Orders'},
          'at': DateTime.now().toIso8601String(),
          'note': null,
        },
      ),
    )..on('POST /v1/restocks/o1/reject-proposal', <String, Object?>{});
    await open(tester, s, '/restocks/o1');
    await tester.ensureVisible(find.text('Refuse the proposal'));
    await tester.tap(find.text('Refuse the proposal'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Too early');
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(FilledButton),
      ),
    );
    await settle(tester);
    expect(body(s, 'POST /v1/restocks/o1/reject-proposal'), {
      'note': 'Too early',
    });
  });

  testWidgets('transfers and returns are read only for the order manager', (
    tester,
  ) async {
    final s = server('ORDERS')..on('GET /v1/transfers', <Object?>[]);
    await open(tester, s, '/returns');
    expect(find.text('New return'), findsNothing);
  });
}
