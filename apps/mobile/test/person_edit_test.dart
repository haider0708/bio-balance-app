// The admin edits a person in full: name, email, WhatsApp number and store; only what changed is sent.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:biobalance/app/router.dart';
import 'package:biobalance/features/network/network_models.dart';
import 'package:flutter/material.dart' show TextFormField;
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, Object?> store(String id, String name) => {
  'id': id,
  'name': name,
  'status': 'ACTIVE',
  'address': 'x',
  'city': 'Tunis',
  'regionId': 'r1',
  'memberCount': 2,
  'initialStock': 'APPROVED',
};

void main() {
  testWidgets(
    'the admin changes the email and the number, and only those are sent',
    (tester) async {
      final s = FakeServer()
        ..on('GET /v1/me', meJson(role: 'ADMIN'))
        ..on('GET /v1/notifications/unread-count', {'unread': 0})
        ..on('GET /v1/dashboard', <String, Object?>{})
        ..on('GET /v1/pdvs', [
          store('p1', 'Para Lac'),
          store('p2', 'Para Marsa'),
        ])
        ..on('PATCH /v1/users/u1', {
          'id': 'u1',
          'name': 'Hanen Smiri',
          'email': 'new@x.tn',
          'role': 'VENDEUR',
          'status': 'ACTIVE',
        });
      final container = await launch(
        tester,
        s,
        language: 'en',
        size: const Size(412, 1600),
      );
      final person = Person.fromJson({
        'id': 'u1',
        'name': 'Hanen Smiri',
        'email': 'hanen@x.tn',
        'phone': '+21621345678',
        'role': 'VENDEUR',
        'status': 'ACTIVE',
        'regionId': 'r1',
        'pdvId': 'p1',
        'activated': false,
      });
      unawaited(
        container.read(routerProvider).push('/people/u1', extra: person),
      );
      await settle(tester);
      // The number is shown readably.
      expect(find.text('+216 21 345 678'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await settle(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), 'New@X.tn');
      await tester.enterText(fields.at(2), '00216 22 333 444');
      await tester.tap(find.text('Save').last);
      await settle(tester);
      final body = jsonDecode(
        jsonEncode(s.calls.lastWhere((c) => c.method == 'PATCH').data),
      ) as Map;
      // The name and the store did not change: they are not sent.
      expect(body, {'email': 'new@x.tn', 'phone': '+21622333444'});
    },
  );

  testWidgets('a wrong number or email stops the save', (tester) async {
    final s = FakeServer()
      ..on('GET /v1/me', meJson(role: 'ADMIN'))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/pdvs', [store('p1', 'Para Lac')]);
    final container = await launch(
      tester,
      s,
      language: 'en',
      size: const Size(412, 1600),
    );
    final person = Person.fromJson({
      'id': 'u1',
      'name': 'Hanen Smiri',
      'email': 'hanen@x.tn',
      'phone': '+21621345678',
      'role': 'VENDEUR',
      'status': 'ACTIVE',
      'regionId': 'r1',
      'pdvId': 'p1',
      'activated': true,
    });
    unawaited(container.read(routerProvider).push('/people/u1', extra: person));
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(2), '12 345');
    await tester.tap(find.text('Save').last);
    await settle(tester, frames: 3);
    expect(
      find.text('Enter a Tunisian mobile number: 8 digits'),
      findsOneWidget,
    );
    expect(s.count('PATCH /v1/users/u1'), 0);
  });
}
