// Working hours: the admin sets them, and a closed server shows the closed screen.
import 'dart:convert';

import 'package:biobalance/app/router.dart';
import 'package:flutter/widgets.dart' show Scrollable;
import 'package:flutter_test/flutter_test.dart';

import 'app_settings_test.dart' show settingsJson;
import 'support/fake_server.dart';
import 'support/harness.dart';

void main() {
  testWidgets('the admin switches the working hours on and saves them', (
    tester,
  ) async {
    final server = FakeServer()
      ..on('GET /v1/me', meJson(role: 'ADMIN'))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/settings', settingsJson())
      ..on('PUT /v1/settings', settingsJson());
    final container = await launch(tester, server, language: 'en');
    container.read(routerProvider).go('/app-settings');
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Close the app outside the hours'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Close the app outside the hours'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save the hours'));
    await tester.pump();
    await tester.tap(find.text('Save the hours'));
    await settle(tester);
    final put = server.calls.lastWhere((c) => c.method == 'PUT');
    final hours =
        (jsonDecode(jsonEncode(put.data)) as Map<String, dynamic>)['hours']
            as Map<String, dynamic>;
    expect(hours['enabled'], true);
    expect((hours['days'] as List).length, 7);
    expect((hours['days'] as List).first, {'open': '08:00', 'close': '21:00'});
  });

  testWidgets('a closed server shows the closed screen with the opening time', (
    tester,
  ) async {
    final server = FakeServer()
      ..on('GET /v1/me', meJson())
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', {
        'code': 'SERVER_CLOSED',
        'message': 'closed',
        'details': {'opensAt': null, 'time': '08:00'},
      }, status: 423);
    await launch(tester, server, language: 'en');
    await settle(tester);
    expect(find.text('BioBalance is closed for now'), findsOneWidget);
    expect(find.textContaining('08:00'), findsOneWidget);
  });
}
