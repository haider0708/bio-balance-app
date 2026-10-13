// A build the server no longer supports shows one screen: update. Nothing else blocks the app.
import 'package:biobalance/core/update/app_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

FakeServer serverWithMinimum(int? minimumBuild) {
  final server = FakeServer();
  if (minimumBuild != null) {
    server.on('GET /v1/app-config', {
      'minimumBuild': minimumBuild,
      'stores': {
        'android': 'https://play.google.com/store/apps/details?id=x',
        'ios': null,
      },
    });
  }
  return server;
}

Future<void> start(WidgetTester tester, FakeServer server) => launch(
  tester,
  server,
  signedIn: false,
  language: 'en',
  overrides: [appBuildProvider.overrideWith((_) async => 41)],
);

void main() {
  testWidgets('an unsupported build is asked to update, with its store link', (
    tester,
  ) async {
    await start(tester, serverWithMinimum(42));
    expect(find.text('Update required'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('a supported build opens normally', (tester) async {
    await start(tester, serverWithMinimum(41));
    expect(find.text('Update required'), findsNothing);
  });

  testWidgets('a phone that cannot ask the server is never blocked', (
    tester,
  ) async {
    await start(tester, serverWithMinimum(null));
    expect(find.text('Update required'), findsNothing);
  });
}
