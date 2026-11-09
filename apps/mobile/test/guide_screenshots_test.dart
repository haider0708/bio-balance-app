// The pictures of the install page (https://api.galylio.com/install): sign-in, activating an account
// with the code, choosing one's own password, and the home screen. Real screens, sample data. Not part
// of the normal run:
//
//   GUIDE_SHOTS=1 flutter test test/guide_screenshots_test.dart
//
// Written to build/guide/<language>/; copy them to apps/api/guide/ (docs/runbook.md, "Installing the app").
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Size, TextFormField;
import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show loadFonts, server;
import 'support/fake_server.dart';
import 'support/harness.dart';

const _size = Size(390, 844);

void main() {
  setUpAll(base.loadFonts);
  final skip = !Platform.environment.containsKey('GUIDE_SHOTS');

  for (final lang in ['fr', 'en']) {
    final fr = lang == 'fr';
    Future<void> shot(WidgetTester tester, String name) =>
        screenshot(tester, '../guide/$lang/$name');

    testWidgets('guide: sign-in and activation, $lang', skip: skip, (
      tester,
    ) async {
      await launch(
        tester,
        FakeServer(),
        signedIn: false,
        language: lang,
        size: _size,
      );
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'amira.gharbi@gmail.com',
      );
      await settle(tester, frames: 3);
      await shot(tester, '1-sign-in');
      await tester.tap(
        find.text(fr ? 'Activer mon compte' : 'Activate my account'),
      );
      await settle(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'amira.gharbi@gmail.com');
      await tester.enterText(fields.at(1), 'K7MQ-4XZR');
      await settle(tester, frames: 3);
      await shot(tester, '2-activate');
    });

    testWidgets('guide: choose a password and home, $lang', skip: skip, (
      tester,
    ) async {
      await launch(
        tester,
        base.server('VENDEUR')..handle(
          'GET /v1/me',
          (_) => (
            status: 200,
            body: {
              ...meJson(name: 'Amira Gharbi', locale: lang),
              'mustChangePassword': true,
            },
          ),
        ),
        language: lang,
        size: _size,
        cachedMe: jsonEncode({
          ...meJson(name: 'Amira Gharbi', locale: lang),
          'mustChangePassword': true,
        }),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Mon-mot-de-passe-42');
      await tester.enterText(fields.at(1), 'Mon-mot-de-passe-42');
      await settle(tester, frames: 3);
      await shot(tester, '3-choose-password');
    });

    testWidgets('guide: home, $lang', skip: skip, (tester) async {
      await launch(tester, base.server('VENDEUR'), language: lang, size: _size);
      await shot(tester, '4-home');
    });
  }
}
