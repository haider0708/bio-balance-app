// Transfers between paras of a group: a team member records one (with one photo), a responsable or
// the admin picks both sides, the admin approves, corrects or refuses it, the paras may change the
// quantities or cancel while it waits.
import 'dart:async';
import 'dart:convert';

import 'package:biobalance/app/router.dart';
import 'package:flutter/material.dart' show IconData, SizedBox, TextField;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, Object?> transferJson({
  String id = 't1',
  String status = 'PENDING',
  bool edit = false,
  bool decide = false,
  List<Map<String, Object?>>? lines,
  int revision = 0,
  List<Map<String, Object?>> changes = const [],
  String? photoId,
}) => {
  'id': id,
  'number': 'TR-2026-000001',
  'status': status,
  'direction': 'SEND',
  'group': {'id': 'g1', 'name': 'Groupe Tunis'},
  'from': {'id': 'p1', 'name': 'Para Lac', 'address': '1 rue', 'city': 'Tunis'},
  'to': {'id': 'p2', 'name': 'Para Marsa', 'address': '2 rue', 'city': 'Tunis'},
  'createdBy': {'id': 'u1', 'name': 'Lina Lac', 'role': 'VENDEUR'},
  'createdAt': DateTime.now().toUtc().toIso8601String(),
  'expiresAt': DateTime.now()
      .add(const Duration(days: 3))
      .toUtc()
      .toIso8601String(),
  'note': 'Called Mehdi',
  'photoId': photoId,
  'revision': revision,
  'decidedBy': null,
  'decidedAt': null,
  'decisionNote': null,
  'units': 5,
  'lines':
      lines ??
      [
        {
          'productId': 'a',
          'name': 'Serum C',
          'family': 'Serums',
          'quantity': 3,
          'requestedQuantity': 3,
        },
        {
          'productId': 'b',
          'name': 'Shampoo',
          'family': 'Hair',
          'quantity': 2,
          'requestedQuantity': 2,
        },
      ],
  'canEdit': edit,
  'canCancel': edit,
  'canDecide': decide,
  'changes': changes,
};

FakeServer server(
  String role, {
  Map<String, Object?>? transfer,
  List<Object?>? list,
}) => FakeServer()
  ..on('GET /v1/me', meJson(role: role))
  ..on('GET /v1/notifications/unread-count', {'unread': 0})
  ..on('GET /v1/dashboard', <String, Object?>{})
  ..on('GET /v1/transfers', list ?? [transfer ?? transferJson()])
  ..on('GET /v1/transfers/t1', transfer ?? transferJson())
  ..on('GET /v1/transfers/partners', {
    'group': {'id': 'g1', 'name': 'Groupe Tunis'},
    'partners': [
      {'id': 'p2', 'name': 'Para Marsa', 'address': '2 rue', 'city': 'Tunis'},
    ],
  })
  ..on('GET /v1/pdvs', [
    {
      'id': 'p1',
      'name': 'Para Lac',
      'status': 'ACTIVE',
      'address': '1 rue',
      'city': 'Tunis',
      'regionId': 'r1',
      'groupId': 'g1',
      'groupName': 'Groupe Tunis',
      'memberCount': 2,
      'initialStock': 'APPROVED',
    },
    {
      'id': 'p3',
      'name': 'Para Seul',
      'status': 'ACTIVE',
      'address': '3 rue',
      'city': 'Tunis',
      'regionId': 'r1',
      'memberCount': 1,
      'initialStock': 'APPROVED',
    },
  ])
  ..on('GET /v1/products', [
    productJson('a', 'Serum C'),
    productJson('b', 'Shampoo', family: 'Hair'),
  ]);

Map<String, Object?> sent(FakeServer s, String path) => jsonDecode(
  jsonEncode(
    s.calls.lastWhere((c) => c.method == 'POST' && c.path == path).data,
  ),
) as Map<String, Object?>;

Future<FakeServer> open(WidgetTester tester, FakeServer s, String path) async {
  final container = await launch(tester, s, language: 'en');
  unawaited(container.read(routerProvider).push(path));
  await settle(tester);
  return s;
}

void main() {
  testWidgets('the list shows what waits and what was decided', (tester) async {
    final s = server(
      'ADMIN',
      list: [
        transferJson(decide: true),
        transferJson(id: 't2', status: 'APPROVED'),
      ],
    );
    await open(tester, s, '/transfers');
    expect(find.text('Para Lac → Para Marsa'), findsOneWidget);
    expect(find.text('Waiting for the admin'), findsOneWidget);
    expect(find.text('Approved'), findsNothing);
    await tester.tap(find.text('Decided'));
    await tester.pump();
    expect(find.text('Approved'), findsOneWidget);
  });

  testWidgets('an empty list explains how it works', (tester) async {
    final s = server('VENDEUR', list: <Object?>[]);
    await open(tester, s, '/transfers');
    expect(find.text('No transfer here'), findsOneWidget);
  });

  testWidgets(
    'the seller\'s home offers the exchange when the para has partners',
    (tester) async {
      final s = server('VENDEUR')
        ..on('GET /v1/wallet', <String, Object?>{})
        ..on('GET /v1/sales', {'items': <Object>[], 'nextCursor': null});
      await launch(tester, s, language: 'en');
      expect(find.text('Exchange with a para'), findsOneWidget);
    },
  );

  testWidgets('the seller\'s home hides it when the para is alone', (
    tester,
  ) async {
    final s = server('VENDEUR')
      ..on('GET /v1/transfers/partners', {
        'group': null,
        'partners': <Object>[],
      })
      ..on('GET /v1/wallet', <String, Object?>{})
      ..on('GET /v1/sales', {'items': <Object>[], 'nextCursor': null});
    await launch(tester, s, language: 'en');
    expect(find.text('Exchange with a para'), findsNothing);
  });

  testWidgets(
    'the admin picks both paras of a group, the products, and the stock moves at once',
    (tester) async {
      final s = server('ADMIN')
        ..on(
          'POST /v1/transfers',
          transferJson(status: 'APPROVED'),
          status: 201,
        );
      await open(tester, s, '/transfers/new');
      // No photo for the admin, and nothing can be sent before the paras and products are chosen.
      expect(find.text('Photo as proof'), findsNothing);
      await tester.tap(find.text('Choose a para').first);
      await settle(tester);
      // A para without a group is not offered.
      expect(find.text('Para Seul'), findsNothing);
      await tester.tap(find.text('Para Lac'));
      await settle(tester);
      await tester.tap(find.text('Choose a para'));
      await settle(tester);
      await tester.tap(find.text('Para Marsa'));
      await settle(tester);
      await tester.tap(find.text('Add a product'));
      await settle(tester);
      await tester.tap(find.text('Serum C'));
      await tester.pump();
      await tester.tap(find.text('Add 1 product'));
      await settle(tester);
      await tester.tap(find.text('Move the stock now'));
      await settle(tester);
      final body = sent(s, '/v1/transfers');
      expect(body['fromPdvId'], 'p1');
      expect(body['toPdvId'], 'p2');
      expect(body['direction'], 'SEND');
      expect((body['lines'] as List).single, {'productId': 'a', 'quantity': 1});
      expect(body.containsKey('photoId'), isFalse);
    },
  );

  testWidgets(
    'a team member speaks for their own para and cannot send without a photo',
    (tester) async {
      final s = server('VENDEUR');
      await open(tester, s, '/transfers/new');
      expect(find.text('My para sends'), findsOneWidget);
      expect(
        find.text('Para Lac'),
        findsOneWidget,
      ); // their own para (from /v1/me)
      expect(find.text('Photo as proof'), findsOneWidget);
      // Their para is on the "from" side; the partner is chosen among the group.
      await tester.tap(find.text('Choose a para'));
      await settle(tester);
      await tester.tap(find.text('Para Marsa'));
      await settle(tester);
      expect(find.text('Para Marsa'), findsOneWidget);
      // Without a photo (and products) the button stays off.
      await tester.tap(find.text('Send for approval'), warnIfMissed: false);
      await settle(tester);
      expect(s.calls.where((c) => c.method == 'POST'), isEmpty);
      // Receiving flips the sides.
      await tester.tap(find.text('My para receives'));
      await tester.pump();
      expect(find.text('Choose a para'), findsOneWidget);
    },
  );

  testWidgets('the admin approves in one tap', (tester) async {
    final s = server('ADMIN', transfer: transferJson(decide: true))
      ..on(
        'POST /v1/transfers/t1/approve',
        transferJson(status: 'APPROVED'),
        status: 201,
      );
    await open(tester, s, '/transfers/t1');
    expect(find.text('TR-2026-000001'), findsOneWidget);
    expect(find.text('Called Mehdi'), findsOneWidget);
    expect(find.text('× 3'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await settle(tester);
    expect(s.count('POST /v1/transfers/t1/approve'), 1);
    expect(sent(s, '/v1/transfers/t1/approve').containsKey('lines'), isFalse);
  });

  testWidgets('the admin can correct the quantities while approving', (
    tester,
  ) async {
    final s = server('ADMIN', transfer: transferJson(decide: true))
      ..on(
        'POST /v1/transfers/t1/approve',
        transferJson(status: 'APPROVED'),
        status: 201,
      );
    await open(tester, s, '/transfers/t1');
    await tester.tap(find.text('Change and approve'));
    await settle(tester);
    await tester.tap(find.byIcon(const IconDataFinder().minus).first);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester);
    final lines = sent(s, '/v1/transfers/t1/approve')['lines'] as List;
    expect(lines, [
      {'productId': 'a', 'quantity': 2},
      {'productId': 'b', 'quantity': 2},
    ]);
  });

  testWidgets('a refusal needs a reason', (tester) async {
    final s = server('ADMIN', transfer: transferJson(decide: true))
      ..on(
        'POST /v1/transfers/t1/reject',
        transferJson(status: 'REJECTED'),
        status: 201,
      );
    await open(tester, s, '/transfers/t1');
    await tester.tap(find.text('Refuse'));
    await settle(tester);
    expect(find.text('Why is it refused?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Not needed');
    await tester.pump();
    await tester.tap(find.text('Refuse').last);
    await settle(tester);
    expect(sent(s, '/v1/transfers/t1/reject')['note'], 'Not needed');
  });

  testWidgets('a para can change the quantities or cancel, but not decide', (
    tester,
  ) async {
    final s = server('RESPONSABLE', transfer: transferJson(edit: true))
      ..on(
        'POST /v1/transfers/t1/cancel',
        transferJson(status: 'CANCELLED'),
        status: 201,
      );
    await open(tester, s, '/transfers/t1');
    expect(find.text('Change the quantities'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Refuse'), findsNothing);
    await tester.tap(find.text('Cancel this transfer'));
    await settle(tester);
    await tester.tap(find.text('Cancel this transfer').last);
    await settle(tester);
    expect(s.count('POST /v1/transfers/t1/cancel'), 1);
  });

  testWidgets('a decided transfer has no buttons, and shows what changed', (
    tester,
  ) async {
    final s = server(
      'ADMIN',
      transfer: transferJson(
        status: 'APPROVED',
        revision: 1,
        lines: [
          {
            'productId': 'a',
            'name': 'Serum C',
            'family': 'Serums',
            'quantity': 2,
            'requestedQuantity': 3,
          },
        ],
        changes: [
          {
            'version': 1,
            'at': DateTime.now().toUtc().toIso8601String(),
            'by': {'id': 'u2', 'name': 'Mehdi Marsa', 'role': 'VENDEUR'},
            'before': [
              {'name': 'Serum C', 'quantity': 3},
            ],
            'after': [
              {'name': 'Serum C', 'quantity': 2},
            ],
          },
        ],
      ),
    );
    await open(tester, s, '/transfers/t1');
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Asked 3'), findsOneWidget);
    expect(find.text('Mehdi Marsa changed the quantities'), findsOneWidget);
  });

  testWidgets('the approvals inbox lists a transfer and opens it', (
    tester,
  ) async {
    final s = server('ADMIN', transfer: transferJson(decide: true))
      ..on('GET /v1/approvals', {
        'counts': {'TRANSFER': 1},
        'items': [
          {
            'type': 'TRANSFER',
            'id': 't1',
            'name': 'Para Lac → Para Marsa',
            'by': 'Lina Lac',
            'regionId': 'r1',
            'region': 'Nord',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'meta': {'number': 'TR-2026-000001', 'units': 5, 'changed': false},
          },
        ],
      });
    await open(tester, s, '/approvals');
    expect(find.text('Para Lac → Para Marsa'), findsOneWidget);
    expect(find.text('Transfer'), findsWidgets);
    await tester.tap(find.text('Para Lac → Para Marsa'));
    await settle(tester);
    expect(find.text('Approve'), findsOneWidget);
  });

  testWidgets('the proof photo is shown on the transfer', (tester) async {
    final s = server(
      'ADMIN',
      transfer: transferJson(decide: true, photoId: 'ph1'),
    );
    await open(tester, s, '/transfers/t1');
    expect(find.text('Photo'), findsOneWidget);
    // Product photos stay cached for five minutes after their screen closes: let that time pass.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  });
}

/// The icon the quantity stepper uses for "less".
class IconDataFinder {
  const IconDataFinder();
  IconData get minus => LucideIcons.minus;
}
