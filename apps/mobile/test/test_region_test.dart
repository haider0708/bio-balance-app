// The store reviewers' test region is hidden from the admin unless they choose to see it in
// Settings; then every request asks the server for it. Only the admin is offered the choice.
import 'package:biobalance/app/router.dart';
import 'package:biobalance/core/auth/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

const _token = 'a-valid-token-of-sufficient-length-123456';

Future<(FakeServer, ProviderContainer)> signedInAs(String role) async {
  final server = FakeServer()
    ..on('GET /v1/me', meJson(role: role))
    ..on('GET /v1/regions', <Object>[]);
  final container = ProviderContainer(
    overrides: server.overrides(token: _token),
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await container.read(sessionProvider.future);
  await container.read(preferencesProvider.future);
  return (server, container);
}

String? askedFor(FakeServer server) =>
    server.calls.last.headers['X-BioBalance-Sandbox'] as String?;

void main() {
  test('an admin who shows the test region asks the server for it', () async {
    final (server, container) = await signedInAs('ADMIN');
    await container.read(apiClientProvider).get('/v1/regions');
    expect(askedFor(server), isNull);

    await container.read(showTestRegionProvider.notifier).choose(true);
    await container.read(apiClientProvider).get('/v1/regions');
    expect(askedFor(server), 'show');

    await container.read(showTestRegionProvider.notifier).choose(false);
    await container.read(apiClientProvider).get('/v1/regions');
    expect(askedFor(server), isNull);
  });

  test('signing out forgets the choice', () async {
    final (server, container) = await signedInAs('ADMIN');
    server.on('POST /v1/auth/logout', {'ok': true});
    await container.read(showTestRegionProvider.notifier).choose(true);
    await container.read(sessionProvider.notifier).logout();
    expect(container.read(showTestRegionProvider), isFalse);
    expect(container.read(apiHeadersProvider), isEmpty);
  });

  testWidgets('only the admin finds the switch in Settings', (tester) async {
    for (final (role, shown) in [('ADMIN', true), ('RESPONSABLE', false)]) {
      final server = FakeServer()
        ..on('GET /v1/me', meJson(role: role))
        ..on('GET /v1/notifications/unread-count', {'unread': 0})
        ..on('GET /v1/dashboard', <String, Object?>{});
      final container = await launch(tester, server, language: 'en');
      container.read(routerProvider).go('/settings');
      await settle(tester);
      expect(
        find.text('Show the test region'),
        shown ? findsOneWidget : findsNothing,
        reason: role,
      );
      if (shown) {
        await tester.scrollUntilVisible(
          find.byType(SwitchListTile),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byType(SwitchListTile));
        await settle(tester);
        expect(container.read(showTestRegionProvider), isTrue);
      }
    }
  });
}
