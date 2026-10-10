import 'package:biobalance/app/console_shell.dart';
import 'package:biobalance/core/auth/session.dart';
import 'package:biobalance/core/theme/app_theme.dart';
import 'package:biobalance/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'screenshots_test.dart' as base show server;

/// The web console's sidebar, on its own: it must be reachable by keyboard and screen readers, and lead everywhere.
void main() {
  Future<GoRouter> pump(
    WidgetTester tester,
    Size size, {
    String role = 'ADMIN',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: base
          .server(role)
          .overrides(token: 'a-valid-token-of-sufficient-length-123456'),
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(sessionProvider.future));
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (_, _, child) => ConsoleShell(child: child),
          routes: [
            for (final p in ['/home', '/approvals', '/reports', '/settings'])
              GoRoute(
                path: p,
                builder: (_, _) => Center(child: Text('page $p')),
              ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    return router;
  }

  testWidgets('wide: the sidebar is in the accessibility tree and navigates', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const Size(1400, 900));
    expect(find.bySemanticsLabel('Approvals'), findsOneWidget);
    expect(find.bySemanticsLabel('Reports'), findsOneWidget);
    await tester.tap(find.text('Reports'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('page /reports'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a responsable gets their own sections, not the admin\'s', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const Size(1400, 900), role: 'RESPONSABLE');
    expect(find.bySemanticsLabel('Restocks'), findsOneWidget);
    expect(find.bySemanticsLabel('Reports'), findsOneWidget);
    expect(find.bySemanticsLabel('Grossistes'), findsOneWidget);
    expect(find.bySemanticsLabel('Approvals'), findsNothing);
    expect(find.bySemanticsLabel('Payouts'), findsNothing);
    expect(find.bySemanticsLabel('Regions'), findsNothing);
    handle.dispose();
  });

  testWidgets('the admin also gets the regions', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const Size(1400, 900));
    expect(find.bySemanticsLabel('Regions'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('narrow: a drawer replaces the sidebar', (tester) async {
    await pump(tester, const Size(600, 900));
    expect(find.text('Approvals'), findsNothing);
    final scaffold = tester.firstState<ScaffoldState>(find.byType(Scaffold));
    scaffold.openDrawer();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Approvals'), findsOneWidget);
  });
}
