// A person opens as a full page: who they are, then what they do. A responsable shows their visits
// (with what each check-in said) and the orders they took part in. And from a para's page the
// admin adds a team member directly.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:biobalance/app/router.dart';
import 'package:flutter/material.dart' show SizedBox, TextFormField;
import 'package:flutter_test/flutter_test.dart';

import 'planning_test.dart' show event, visitJson;
import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, Object?> nora = {
  'id': 'u9',
  'name': 'Nora Nord',
  'email': 'nora@x.tn',
  'phone': '+21621345678',
  'role': 'RESPONSABLE',
  'status': 'ACTIVE',
  'regionId': 'r1',
  'pdvId': null,
  'activated': true,
};

Map<String, Object?> pdv = {
  'id': 'p1',
  'name': 'Para Lac',
  'address': '1 rue',
  'city': 'Tunis',
  'phone': null,
  'status': 'ACTIVE',
  'regionId': 'r1',
  'groupId': null,
  'groupName': null,
  'memberCount': 0,
  'initialStock': 'APPROVED',
};

FakeServer server() => FakeServer()
  ..on('GET /v1/me', meJson(role: 'ADMIN'))
  ..on('GET /v1/notifications/unread-count', {'unread': 0})
  ..on('GET /v1/dashboard', <String, Object?>{})
  ..on('GET /v1/regions', [
    {'id': 'r1', 'code': 'NORD', 'name': 'Nord'},
  ])
  ..on('GET /v1/users/u9', nora)
  ..on('GET /v1/users', <Object?>[])
  ..on('GET /v1/pdvs/p1', pdv)
  ..on('GET /v1/pdvs', [pdv])
  ..on('GET /v1/visits', [
    {
      ...visitJson(
        status: 'DONE',
        events: [event('CHECK_IN', 'VERIFIED', distance: 40)],
      ),
      'responsableName': 'Nora Nord',
    },
  ])
  ..on('GET /v1/restocks', [
    {
      'id': 'o1',
      'number': 'RS-2026-000007',
      'status': 'REQUESTED',
      'regionId': 'r1',
      'destination': {'id': 'p1', 'kind': 'PDV', 'name': 'Para Lac'},
      'requestedBy': {'id': 'u9', 'name': 'Nora Nord'},
      'createdAt': DateTime.now().toIso8601String(),
      'lines': <Object?>[],
    },
    {
      'id': 'o2',
      'number': 'RS-2026-000008',
      'status': 'REQUESTED',
      'regionId': 'r1',
      'destination': {'id': 'p1', 'kind': 'PDV', 'name': 'Para Lac'},
      'requestedBy': {'id': 'someone', 'name': 'Someone Else'},
      'createdAt': DateTime.now().toIso8601String(),
      'lines': <Object?>[],
    },
  ])
  ..on('POST /v1/users', {...nora, 'id': 'new'}, status: 201);

Future<void> close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 6));
}

void main() {
  testWidgets(
    'a responsable\'s page: the account, their visits and the orders they took part in',
    (tester) async {
      final s = server();
      final container = await launch(
        tester,
        s,
        language: 'en',
        size: const Size(412, 1800),
      );
      // Opened by its address alone (a link, a page restored): the page reads the person itself.
      unawaited(container.read(routerProvider).push('/people/u9'));
      await settle(tester);
      expect(find.text('Nora Nord'), findsWidgets);
      expect(find.text('nora@x.tn'), findsOneWidget);
      // Her visits, asked for her only, with what the check-in said.
      expect(find.text('Visits'), findsOneWidget);
      expect(find.text('Para Lac'), findsWidgets);
      final asked = s.calls.lastWhere((c) => c.path == '/v1/visits');
      expect(asked.queryParameters['responsableId'], 'u9');
      // Her orders, not someone else's.
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('RS-2026-000007'), findsOneWidget);
      expect(find.text('RS-2026-000008'), findsNothing);
      // No sales block: she does not sell.
      expect(find.text('Latest sales'), findsNothing);
      await screenshot(tester, 'person_responsable');
      await close(tester);
    },
  );

  testWidgets('from a para\'s page the admin adds a team member directly', (
    tester,
  ) async {
    final s = server();
    final container = await launch(
      tester,
      s,
      language: 'en',
      size: const Size(412, 1800),
    );
    unawaited(container.read(routerProvider).push('/pdvs/p1'));
    await settle(tester);
    expect(find.text('No team member yet.'), findsOneWidget);
    await tester.tap(find.text('Add a member'));
    await settle(tester);
    // The para is fixed: no kind of account and no para to choose.
    expect(find.text('Para Lac'), findsWidgets);
    expect(find.text('Order manager'), findsNothing);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Karim Ben Ali');
    await tester.enterText(fields.at(1), 'karim@x.tn');
    await tester.enterText(fields.at(2), '21345678');
    await tester.tap(find.text('Create and send invitation'));
    await settle(tester);
    await tester.tap(find.text('Confirm and send'));
    await settle(tester);
    final sent = jsonDecode(
      jsonEncode(
        s.calls
            .lastWhere((c) => c.method == 'POST' && c.path == '/v1/users')
            .data,
      ),
    ) as Map<String, Object?>;
    expect(sent['pdvId'], 'p1');
    expect(sent['role'], 'VENDEUR');
    await close(tester);
  });
}
