// The opening, what the app stores check and what protects people's work: account deletion,
// the legal pages, and work in progress kept as a draft.
import 'dart:async';

import 'package:biobalance/app/router.dart';
import 'package:biobalance/core/theme/app_theme.dart';
import 'package:biobalance/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:biobalance/core/widgets/photo_set.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show loadFonts, server;
import 'support/fake_server.dart';
import 'support/harness.dart';
import 'vendeur_flow_test.dart' show vendeurServer;

void main() {
  setUpAll(base.loadFonts);
  documentTests();

  testWidgets('the opening plays, then the app goes on by itself', (
    tester,
  ) async {
    await launch(tester, vendeurServer(), language: 'en', wait: false);
    // Moments of the opening, in milliseconds since the first frame.
    var at = 0;
    for (final (ms, name) in [(60, 'a'), (450, 'b'), (900, 'c'), (1500, 'd')]) {
      await tester.pump(Duration(milliseconds: ms - at));
      at = ms;
      await screenshot(tester, '80-splash-$name');
    }
    expect(find.text('BACK TO NATURE'), findsOneWidget);
    await settle(tester);
    expect(find.text('Hello, Karim'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sign-in screen links the privacy policy and the terms', (
    tester,
  ) async {
    await launch(tester, vendeurServer(), signedIn: false, language: 'en');
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Terms of use'), findsOneWidget);
  });

  testWidgets('a person deletes their own account and lands signed out', (
    tester,
  ) async {
    final server = vendeurServer()
      ..on('GET /v1/wallet', {
        'balanceMillimes': 5000,
        'pendingPayoutMillimes': 0,
        'availableMillimes': 5000,
        'today': {'sales': 0, 'units': 0, 'rewardMillimes': 0},
        'week': {'sales': 0, 'units': 0, 'rewardMillimes': 0},
        'month': {'sales': 0, 'units': 0, 'rewardMillimes': 0},
      })
      ..on('POST /v1/me/delete', {'ok': true}, status: 201);
    await launch(tester, server, language: 'en', size: const Size(412, 1200));
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await screenshot(tester, '81-settings');
    expect(find.text('Privacy policy'), findsOneWidget);
    await tester.ensureVisible(find.text('Delete my account'));
    await tester.tap(find.text('Delete my account'));
    await settle(tester);
    expect(find.text('Delete your account?'), findsOneWidget);
    await screenshot(tester, '82-delete-account');
    // The money still to be paid is pointed out before anything happens.
    expect(find.textContaining('5.000 TND'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'my-password');
    await tester.tap(find.text('Delete my account for good'));
    await settle(tester);
    expect(server.count('POST /v1/me/delete'), 1);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Your account was deleted.'), findsOneWidget);
  });

  testWidgets('a sale being built is kept as a draft, then gone once recorded', (
    tester,
  ) async {
    final server = vendeurServer();
    await launch(tester, server, language: 'en');
    await tester.tap(find.text('New sale').first);
    await settle(tester);
    await tester.tap(find.text('Serum Vitamin C'));
    await settle(tester, frames: 5);

    // Back (the button or the iPhone edge swipe) is never blocked: the sale is kept.
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.text('Hello, Karim'), findsOneWidget);
    expect(find.text('Kept as a draft: finish it later.'), findsOneWidget);

    await tester.tap(find.text('New sale').first);
    await settle(tester);
    expect(find.text('Your unfinished entry is back.'), findsOneWidget);
    expect(find.textContaining('Review sale · 1 unit'), findsOneWidget);
    await screenshot(tester, '16-vendeur-draft');

    // Starting over asks first, then empties the sale.
    await tester.tap(find.text('Start over'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Start over').last);
    await settle(tester);
    expect(find.textContaining('Review sale'), findsNothing);
    expect(find.text('Your unfinished entry is back.'), findsNothing);

    // A recorded sale (here kept on the phone, offline) leaves no draft behind.
    await tester.tap(find.text('Serum Vitamin C'));
    await settle(tester, frames: 5);
    server.offline = true;
    await tester.tap(find.textContaining('Review sale'));
    await settle(tester);
    await tester.tap(find.text('Record the sale'));
    await settle(tester, frames: 40);
    expect(find.text('Saved on your phone'), findsOneWidget);
    await tester.tap(find.text('New sale').last);
    await settle(tester);
    expect(find.text('Your unfinished entry is back.'), findsNothing);
    expect(find.textContaining('Review sale'), findsNothing);
    // Back online: the outbox tries the kept sale and stops retrying.
    server.offline = false;
    await tester.pump(const Duration(seconds: 31));
    await settle(tester);
  });

  testWidgets(
    'a stock count is kept as a draft with its note, until started over',
    (tester) async {
      final server = base.server('RESPONSABLE')
        ..on('GET /v1/stock/locations/p1', stockJson(['a', 'b']));
      final container = await launch(tester, server, language: 'en');
      final router = container.read(routerProvider);
      unawaited(router.push('/stock/p1/declare', extra: 'Para Lac'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Note (optional)'),
        'Shelf 2 checked',
      );
      await settle(tester, frames: 5);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.text('Kept as a draft: finish it later.'), findsOneWidget);

      unawaited(router.push('/stock/p1/declare', extra: 'Para Lac'));
      await settle(tester);
      expect(find.text('Your unfinished entry is back.'), findsOneWidget);
      expect(find.text('Shelf 2 checked'), findsOneWidget);
      await tester.tap(find.text('Start over'));
      await settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Start over').last);
      await settle(tester);
      expect(find.text('Shelf 2 checked'), findsNothing);
      expect(find.text('Your unfinished entry is back.'), findsNothing);
      // Nothing left: leaving now keeps nothing.
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.text('Kept as a draft: finish it later.'), findsNothing);
    },
  );
}

Widget _host(FakeServer server, Widget child) => UncontrolledProviderScope(
  container: ProviderContainer(overrides: server.overrides(token: 'x' * 40)),
  child: MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  ),
);

void documentTests() {
  testWidgets('a document among the proofs shows as a document', (
    tester,
  ) async {
    final server = FakeServer()
      ..on('GET /v1/media/d1/info', {
        'id': 'd1',
        'mime': 'application/pdf',
        'fileName': 'bon-livraison.pdf',
        'size': 2048,
      })
      ..on('GET /v1/media/p1/info', {
        'id': 'p1',
        'mime': 'image/jpeg',
        'fileName': 'photo.jpg',
        'size': 2048,
      });
    await tester.pumpWidget(_host(server, const PhotoStrip(ids: ['d1', 'p1'])));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('bon-livraison.pdf'), findsOneWidget);
    // Let the image cache release what it kept (it holds files a few minutes).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  });

  testWidgets('proofs can be photos or a document', (tester) async {
    await tester.pumpWidget(
      _host(
        FakeServer(),
        PhotoSet(label: 'Delivery paper', onChanged: (_, _) {}),
      ),
    );
    await tester.tap(find.text('Delivery paper'));
    await tester.pumpAndSettle();
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose a document'), findsOneWidget);
    expect(find.text('0 of 5 photos or documents'), findsOneWidget);
  });
}
