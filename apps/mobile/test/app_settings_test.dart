// The admin's application settings: the oldest app build still allowed, per platform.
import 'dart:convert';

import 'package:biobalance/app/router.dart';
import 'package:biobalance/core/update/app_update.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, Object?> settingsJson({int ios = 0, int android = 0}) => {
  'minimumBuild': {'ios': ios, 'android': android},
  'stores': {'ios': null, 'android': 'https://play.google.com/x'},
  'hours': {
    'enabled': false,
    'days': List.generate(7, (_) => {'open': '08:00', 'close': '21:00'}),
  },
  'supplierChoice': false,
  'open': true,
  'nextOpening': null,
};

void main() {
  testWidgets('the admin raises the minimum build of one platform', (
    tester,
  ) async {
    final server = FakeServer()
      ..on('GET /v1/me', meJson(role: 'ADMIN'))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/settings', settingsJson(android: 40))
      ..on('PUT /v1/settings', settingsJson(ios: 45, android: 40));
    final container = await launch(
      tester,
      server,
      language: 'en',
      overrides: [appBuildProvider.overrideWith((_) async => 42)],
    );
    container.read(routerProvider).go('/app-settings');
    await settle(tester);
    expect(find.text('Minimum version'), findsOneWidget);
    expect(find.text('This app is build 42.'), findsOneWidget);
    // The android field shows what is saved; the admin sets the iPhone one.
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '45');
    await tester.ensureVisible(find.text('Save'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester);
    final put = server.calls.lastWhere((c) => c.method == 'PUT');
    expect(jsonDecode(jsonEncode(put.data)), {
      'minimumBuild': {'ios': 45, 'android': 40},
    });
  });

  testWidgets('the same build can be used for both platforms in one tap', (
    tester,
  ) async {
    final server = FakeServer()
      ..on('GET /v1/me', meJson(role: 'ADMIN'))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/settings', settingsJson())
      ..on('PUT /v1/settings', settingsJson(ios: 42, android: 42));
    final container = await launch(
      tester,
      server,
      language: 'en',
      overrides: [appBuildProvider.overrideWith((_) async => 42)],
    );
    container.read(routerProvider).go('/app-settings');
    await settle(tester);
    await tester.ensureVisible(find.text('Use this build'));
    await tester.pump();
    await tester.tap(find.text('Use this build'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester);
    final put = server.calls.lastWhere((c) => c.method == 'PUT');
    expect(jsonDecode(jsonEncode(put.data)), {
      'minimumBuild': {'ios': 42, 'android': 42},
    });
  });
}
