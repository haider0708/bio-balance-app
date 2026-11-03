// A team member signs in with the password that was sent: the app asks for their own before anything
// else, the request carries no current password, and then the app opens.
import 'dart:async';
import 'dart:convert';

import 'package:biobalance/app/router.dart';
import 'package:biobalance/features/network/network_models.dart';
import 'package:flutter/material.dart' show FilledButton, TextFormField;
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

FakeServer server({bool must = true}) {
  var changed = !must;
  return FakeServer()
    ..handle(
      'GET /v1/me',
      (_) => (
        status: 200,
        body: {
          ...meJson(name: 'Amira Gharbi'),
          'mustChangePassword': !changed,
        },
      ),
    )
    ..handle('POST /v1/me/password', (_) {
      changed = true;
      return (status: 201, body: <String, Object?>{'ok': true});
    })
    ..on('GET /v1/notifications/unread-count', {'unread': 0})
    ..on('GET /v1/dashboard', <String, Object?>{});
}

void main() {
  testWidgets('the first sign-in goes to choosing a password, nothing else', (
    tester,
  ) async {
    final s = server();
    await launch(
      tester,
      s,
      language: 'en',
      cachedMe: jsonEncode({
        ...meJson(name: 'Amira Gharbi'),
        'mustChangePassword': true,
      }),
    );
    expect(find.text('Welcome, Amira'), findsOneWidget);
    expect(find.text('Save and continue'), findsOneWidget);
    expect(find.text('New sale'), findsNothing);
    // Not the app: no dashboard was even asked for.
    expect(s.count('GET /v1/dashboard'), 0);
  });

  testWidgets('a short or different password is stopped, then the app opens', (
    tester,
  ) async {
    final s = server();
    await launch(
      tester,
      s,
      language: 'en',
      cachedMe: jsonEncode({
        ...meJson(name: 'Amira Gharbi'),
        'mustChangePassword': true,
      }),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'short');
    await tester.enterText(fields.at(1), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Save and continue'));
    await settle(tester, frames: 3);
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(s.count('POST /v1/me/password'), 0);

    await tester.enterText(fields.at(0), 'My-own-password-42');
    await tester.enterText(fields.at(1), 'Another-one-123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Save and continue'));
    await settle(tester, frames: 3);
    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(s.count('POST /v1/me/password'), 0);

    await tester.enterText(fields.at(1), 'My-own-password-42');
    await tester.tap(find.widgetWithText(FilledButton, 'Save and continue'));
    await settle(tester);
    final sent = jsonDecode(
      jsonEncode(s.calls.lastWhere((c) => c.path == '/v1/me/password').data),
    ) as Map;
    // No current password: the session itself proves the temporary one.
    expect(sent, {'next': 'My-own-password-42'});
    expect(find.text('Welcome, Amira'), findsNothing);
    expect(find.text('New sale'), findsWidgets);
  });

  testWidgets('someone with their own password goes straight in', (
    tester,
  ) async {
    final s = server(must: false);
    await launch(tester, s, language: 'en');
    expect(find.text('Save and continue'), findsNothing);
    expect(find.text('New sale'), findsWidgets);
  });

  testWidgets('a manager sees the password is waiting, and sends a new one', (
    tester,
  ) async {
    final s = FakeServer()
      ..on('GET /v1/me', meJson(role: 'ADMIN'))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/pdvs', <Object?>[])
      ..on('GET /v1/approvals', {
        'counts': <String, Object?>{},
        'items': <Object?>[],
      })
      ..on('POST /v1/users/u3/resend-invite', <String, Object?>{'ok': true});
    final container = await launch(tester, s, language: 'en');
    final person = Person.fromJson({
      'id': 'u3',
      'name': 'Hanen Smiri',
      'email': 'hanen@x.tn',
      'phone': '+21621345678',
      'role': 'VENDEUR',
      'status': 'ACTIVE',
      'regionId': 'r1',
      'pdvId': 'p1',
      'activated': false,
      'mustChangePassword': true,
      'passwordExpiresAt': DateTime.now()
          .add(const Duration(days: 5))
          .toUtc()
          .toIso8601String(),
    });
    unawaited(container.read(routerProvider).push('/people/u3', extra: person));
    await settle(tester);
    expect(find.text('Has not signed in yet'), findsOneWidget);
    expect(
      find.textContaining('Temporary password valid until'),
      findsOneWidget,
    );
    await tester.tap(find.text('Send a new password'));
    await settle(tester);
    expect(s.count('POST /v1/users/u3/resend-invite'), 1);
  });
}
