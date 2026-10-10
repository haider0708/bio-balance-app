// What the app stores check and what protects people's work: account deletion, the legal
// pages, and nothing lost by a stray back gesture.
import 'package:biobalance/core/theme/app_theme.dart';
import 'package:biobalance/core/widgets/leave_guard.dart';
import 'package:biobalance/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'vendeur_flow_test.dart' show vendeurServer;

void main() {
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
    expect(find.text('Privacy policy'), findsOneWidget);
    await tester.ensureVisible(find.text('Delete my account'));
    await tester.tap(find.text('Delete my account'));
    await settle(tester);
    expect(find.text('Delete your account?'), findsOneWidget);
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

void unawaitedPush(GlobalKey<NavigatorState> navigator) {
  navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => const LeaveGuard(dirty: true, child: Text('form')),
    ),
  );
}
