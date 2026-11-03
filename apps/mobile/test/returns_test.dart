// Returns: a responsable asks for quantities to be taken out of a para; the admin decides (approves,
// corrects, moves them to another para instead, or refuses) and can also act directly: take out, move,
// or only add.
import 'dart:async';
import 'dart:convert';

import 'package:biobalance/app/router.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, Object?> returnJson({
  String id = 'r1',
  String status = 'PENDING',
  String action = 'REMOVE',
  bool edit = false,
  bool decide = false,
}) => {
  'id': id,
  'number': 'RT-2026-000001',
  'status': status,
  'action': action,
  'region': 'Nord',
  'para': {'id': 'p1', 'name': 'Para Lac', 'address': '1 rue', 'city': 'Tunis'},
  'to': action == 'MOVE'
      ? {'id': 'p2', 'name': 'Para Marsa', 'address': '2 rue', 'city': 'Tunis'}
      : null,
  'createdBy': {'id': 'u1', 'name': 'Nora Nord', 'role': 'RESPONSABLE'},
  'createdAt': DateTime.now().toUtc().toIso8601String(),
  'expiresAt': DateTime.now()
      .add(const Duration(days: 3))
      .toUtc()
      .toIso8601String(),
  'note': 'Expired box',
  'revision': 0,
  'decidedBy': null,
  'decidedAt': null,
  'decisionNote': null,
  'units': 5,
  'lines': [
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
  'changes': <Object>[],
};

FakeServer server(
  String role, {
  Map<String, Object?>? item,
  List<Object?>? list,
}) => FakeServer()
  ..on('GET /v1/me', meJson(role: role))
  ..on('GET /v1/notifications/unread-count', {'unread': 0})
  ..on('GET /v1/dashboard', <String, Object?>{})
  ..on('GET /v1/returns', list ?? [item ?? returnJson()])
  ..on('GET /v1/returns/r1', item ?? returnJson())
  ..on('GET /v1/pdvs', [
    for (final (id, name) in [('p1', 'Para Lac'), ('p2', 'Para Marsa')])
      {
        'id': id,
        'name': name,
        'status': 'ACTIVE',
        'address': '1 rue',
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

Future<void> open(WidgetTester tester, FakeServer s, String path) async {
  final container = await launch(tester, s, language: 'en');
  unawaited(container.read(routerProvider).push(path));
  await settle(tester);
}

Future<void> pickPara(WidgetTester tester, String row, String name) async {
  await tester.tap(find.text(row).first);
  await settle(tester);
  await tester.tap(find.text(name).last);
  await settle(tester);
}

void main() {
  testWidgets('the list shows what waits and what was decided', (tester) async {
    final s = server(
      'ADMIN',
      list: [
        returnJson(decide: true),
        returnJson(id: 'r2', status: 'APPROVED', action: 'MOVE'),
      ],
    );
    await open(tester, s, '/returns');
    expect(find.text('Para Lac'), findsOneWidget);
    expect(find.text('Waiting for the admin'), findsOneWidget);
    await tester.tap(find.text('Decided'));
    await tester.pump();
    expect(find.text('Para Lac → Para Marsa'), findsOneWidget);
    expect(find.text('Moved to Para Marsa'), findsOneWidget);
  });

  testWidgets(
    'a responsable asks to take quantities out: no choice of action',
    (tester) async {
      final s = server('RESPONSABLE')
        ..on('POST /v1/returns', returnJson(), status: 201);
      await open(tester, s, '/returns/new');
      expect(find.text('Move to another para'), findsNothing);
      await pickPara(tester, 'Choose a para', 'Para Lac');
      await tester.tap(find.text('Add a product'));
      await settle(tester);
      await tester.tap(find.text('Serum C'));
      await tester.pump();
      await tester.tap(find.text('Add 1 product'));
      await settle(tester);
      await tester.tap(find.text('Send to the admin'));
      await settle(tester);
      final body = sent(s, '/v1/returns');
      expect(body['pdvId'], 'p1');
      expect(body['action'], 'REMOVE');
      expect(body.containsKey('toPdvId'), isFalse);
      expect((body['lines'] as List).single, {'productId': 'a', 'quantity': 1});
    },
  );

  testWidgets(
    'the admin can move to another para directly, which needs the receiving para',
    (tester) async {
      final s = server('ADMIN')
        ..on(
          'POST /v1/returns',
          returnJson(status: 'APPROVED', action: 'MOVE'),
          status: 201,
        );
      await open(tester, s, '/returns/new');
      await tester.tap(find.text('Move to another para'));
      await tester.pump();
      await pickPara(tester, 'Choose a para', 'Para Lac');
      await tester.tap(find.text('Add a product'));
      await settle(tester);
      await tester.tap(find.text('Serum C'));
      await tester.pump();
      await tester.tap(find.text('Add 1 product'));
      await settle(tester);
      // Without the receiving para the button stays off.
      await tester.tap(find.text('Apply now'), warnIfMissed: false);
      await settle(tester);
      expect(s.calls.where((c) => c.method == 'POST'), isEmpty);
      await pickPara(tester, 'Choose a para', 'Para Marsa');
      await tester.tap(find.text('Apply now'));
      await settle(tester);
      final body = sent(s, '/v1/returns');
      expect(body['action'], 'MOVE');
      expect(body['pdvId'], 'p1');
      expect(body['toPdvId'], 'p2');
    },
  );

  testWidgets('the admin can only add', (tester) async {
    final s = server('ADMIN')
      ..on(
        'POST /v1/returns',
        returnJson(status: 'APPROVED', action: 'ADD'),
        status: 201,
      );
    await open(tester, s, '/returns/new');
    await tester.tap(find.text('Add only'));
    await tester.pump();
    await pickPara(tester, 'Choose a para', 'Para Marsa');
    await tester.tap(find.text('Add a product'));
    await settle(tester);
    await tester.tap(find.text('Shampoo'));
    await tester.pump();
    await tester.tap(find.text('Add 1 product'));
    await settle(tester);
    await tester.tap(find.text('Apply now'));
    await settle(tester);
    final body = sent(s, '/v1/returns');
    expect(body['action'], 'ADD');
    expect(body['pdvId'], 'p2');
    expect(body.containsKey('toPdvId'), isFalse);
  });

  testWidgets(
    'the admin approves in one tap, or moves it to another para instead',
    (tester) async {
      final s = server('ADMIN', item: returnJson(decide: true))
        ..on(
          'POST /v1/returns/r1/approve',
          returnJson(status: 'APPROVED'),
          status: 201,
        );
      await open(tester, s, '/returns/r1');
      expect(find.text('RT-2026-000001'), findsOneWidget);
      expect(find.text('Expired box'), findsOneWidget);
      await tester.tap(find.text('Approve and move to another para'));
      await settle(tester);
      // The para it comes from is not offered as the destination.
      expect(find.text('Para Lac'), findsNWidgets(1));
      await tester.tap(find.text('Para Marsa').last);
      await settle(tester);
      expect(sent(s, '/v1/returns/r1/approve')['toPdvId'], 'p2');
      await tester.tap(find.text('Approve'));
      await settle(tester);
      expect(s.count('POST /v1/returns/r1/approve'), 2);
      expect(sent(s, '/v1/returns/r1/approve').containsKey('toPdvId'), isFalse);
    },
  );

  testWidgets('a refusal needs a reason', (tester) async {
    final s = server('ADMIN', item: returnJson(decide: true))
      ..on(
        'POST /v1/returns/r1/reject',
        returnJson(status: 'REJECTED'),
        status: 201,
      );
    await open(tester, s, '/returns/r1');
    await tester.tap(find.text('Refuse'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Keep it');
    await tester.pump();
    await tester.tap(find.text('Refuse').last);
    await settle(tester);
    expect(sent(s, '/v1/returns/r1/reject')['note'], 'Keep it');
  });

  testWidgets(
    'the responsable can change or cancel while it waits, not decide',
    (tester) async {
      final s = server('RESPONSABLE', item: returnJson(edit: true))
        ..on(
          'POST /v1/returns/r1/cancel',
          returnJson(status: 'CANCELLED'),
          status: 201,
        );
      await open(tester, s, '/returns/r1');
      expect(find.text('Change the quantities'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      await tester.tap(find.text('Cancel this return'));
      await settle(tester);
      await tester.tap(find.text('Cancel this return').last);
      await settle(tester);
      expect(s.count('POST /v1/returns/r1/cancel'), 1);
    },
  );

  testWidgets('the approvals inbox lists a return and opens it', (
    tester,
  ) async {
    final s = server('ADMIN', item: returnJson(decide: true))
      ..on('GET /v1/approvals', {
        'counts': {'RETURN': 1},
        'items': [
          {
            'type': 'RETURN',
            'id': 'r1',
            'name': 'Para Lac',
            'by': 'Nora Nord',
            'regionId': 'r1',
            'region': 'Nord',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'meta': {'number': 'RT-2026-000001', 'units': 5, 'changed': false},
          },
        ],
      });
    await open(tester, s, '/approvals');
    expect(find.text('Return'), findsWidgets);
    await tester.tap(find.text('Para Lac'));
    await settle(tester);
    expect(find.text('Approve'), findsOneWidget);
  });
}
