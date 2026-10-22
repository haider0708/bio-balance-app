// Creating an account: the WhatsApp number is required and read in every way people write it, and
// the name, email and number are shown for a last check before anything is sent.
import 'dart:async';
import 'dart:convert';

import 'package:biobalance/app/router.dart';

import 'dart:ui' show Size;

import 'package:flutter/material.dart' show TextFormField;
import 'package:flutter_test/flutter_test.dart';

import 'app_settings_test.dart' show settingsJson;
import 'support/fake_server.dart';
import 'support/harness.dart';

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

FakeServer server(String role) => FakeServer()
  ..on('GET /v1/me', meJson(role: role))
  ..on('GET /v1/notifications/unread-count', {'unread': 0})
  ..on('GET /v1/dashboard', <String, Object?>{})
  ..on('GET /v1/pdvs', [store()])
  ..on('GET /v1/regions', [
    {'id': 'r1', 'name': 'Nord', 'code': 'NORD'},
  ])
  ..on('POST /v1/pdvs/p1/members', {
    'id': 'u1',
    'name': 'Hanen',
    'email': 'h@x.tn',
    'role': 'VENDEUR',
    'status': 'PENDING',
  })
  ..on('GET /v1/approvals', {
    'counts': <String, Object?>{},
    'items': <Object?>[],
  });

Future<void> fill(WidgetTester tester, String phone) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'Hanen Smiri');
  await tester.enterText(fields.at(1), 'Hanen@Example.tn');
  await tester.enterText(fields.at(2), phone);
  await tester.pump();
}

void main() {
  testWidgets(
    'a responsable cannot send an invitation without a valid number',
    (tester) async {
      final s = server('RESPONSABLE');
      final container = await launch(
        tester,
        s,
        language: 'en',
        size: const Size(412, 1600),
      );
      unawaited(container.read(routerProvider).push('/pdvs/p1/members/new'));
      await settle(tester);
      await fill(tester, '');
      await tester.tap(find.text('Send for approval'));
      await settle(tester, frames: 3);
      expect(find.text('Enter the WhatsApp number'), findsOneWidget);
      await fill(tester, '12 345');
      await tester.tap(find.text('Send for approval'));
      await settle(tester, frames: 3);
      expect(
        find.text('Enter a Tunisian mobile number: 8 digits'),
        findsOneWidget,
      );
      expect(s.count('POST /v1/pdvs/p1/members'), 0);
    },
  );

  testWidgets(
    'the number is shown back for a last check, and sent in its canonical form',
    (tester) async {
      final s = server('RESPONSABLE');
      final container = await launch(
        tester,
        s,
        language: 'en',
        size: const Size(412, 1600),
      );
      unawaited(container.read(routerProvider).push('/pdvs/p1/members/new'));
      await settle(tester);
      await fill(tester, '00216 21345678');
      await tester.tap(find.text('Send for approval'));
      await settle(tester);
      // Nothing is sent yet: the person checks what they typed.
      expect(find.text('Check before sending'), findsOneWidget);
      expect(find.text('+216 21 345 678'), findsOneWidget);
      expect(find.text('hanen@example.tn'), findsOneWidget);
      expect(find.text('Para Lac'), findsOneWidget);
      expect(s.count('POST /v1/pdvs/p1/members'), 0);
      // Going back to edit sends nothing either.
      await tester.tap(find.text('Edit'));
      await settle(tester);
      expect(s.count('POST /v1/pdvs/p1/members'), 0);
      await tester.tap(find.text('Send for approval'));
      await settle(tester);
      await tester.tap(find.text('Confirm and send'));
      await settle(tester);
      final body = jsonDecode(
        jsonEncode(
          s.calls
              .lastWhere(
                (c) => c.method == 'POST' && c.path == '/v1/pdvs/p1/members',
              )
              .data,
        ),
      ) as Map;
      expect(body['phone'], '+21621345678');
      expect(body['email'], 'hanen@example.tn');
    },
  );

  testWidgets('the admin switches WhatsApp codes on once the server has it', (
    tester,
  ) async {
    final settings = settingsJson()
      ..['whatsapp'] = {'enabled': false, 'status': 'CONNECTED'};
    final s = FakeServer()
      ..on('GET /v1/me', meJson(role: 'ADMIN'))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/settings', settings)
      ..on('PUT /v1/settings', settings);
    final container = await launch(
      tester,
      s,
      language: 'en',
      size: const Size(412, 4200),
    );
    container.read(routerProvider).go('/app-settings');
    await settle(tester);
    expect(find.text('WhatsApp is connected'), findsOneWidget);
    await tester.tap(find.text('Send codes by WhatsApp'));
    await settle(tester);
    final put = jsonDecode(
      jsonEncode(s.calls.lastWhere((c) => c.method == 'PUT').data),
    ) as Map;
    expect(put['whatsapp'], {'enabled': true});
  });
}
