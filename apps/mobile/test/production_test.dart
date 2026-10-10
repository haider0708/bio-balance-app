// The opening, what the app stores check and what protects people's work: account deletion,
// the legal pages, and nothing lost by a stray back gesture.
import 'package:biobalance/core/theme/app_theme.dart';
import 'package:biobalance/core/widgets/leave_guard.dart';
import 'package:biobalance/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:biobalance/core/widgets/photo_set.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show loadFonts;
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

  testWidgets('a sale being built is not lost by the back gesture', (
    tester,
  ) async {
    await launch(tester, vendeurServer(), language: 'en');
    await tester.tap(find.text('New sale').first);
    await settle(tester);
    await tester.tap(find.text('Serum Vitamin C'));
    await settle(tester, frames: 5);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Leave without saving?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.textContaining('Review sale'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('Discard'));
    await settle(tester);
    expect(find.text('Hello, Karim'), findsOneWidget);
  });

  testWidgets('the guard never blocks the app leaving after a save', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        navigatorKey: navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Text('home'),
      ),
    );
    unawaitedPush(navigator);
    await tester.pumpAndSettle();
    expect(find.text('form'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });
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

void unawaitedPush(GlobalKey<NavigatorState> navigator) {
  navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => const LeaveGuard(dirty: true, child: Text('form')),
    ),
  );
}
