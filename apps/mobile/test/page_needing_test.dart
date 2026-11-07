import 'package:biobalance/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Build 47 crashed ("type 'Null' is not a subtype of type 'SaleOutcome'", "Null check operator")
/// when the router rebuilt a page without the object the previous screen handed over.
void main() {
  Widget app(GoRouter router) => MaterialApp.router(routerConfig: router);

  GoRouter routerWith({required String start}) => GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const Text('home page')),
      // No redirect on purpose: the builder alone has to cope, as when the router rebuilds a
      // page that is already on screen.
      GoRoute(
        path: '/needs',
        builder: (_, state) =>
            pageNeeding<int>(state, '/home', (number) => Text('got $number')),
      ),
    ],
  );

  testWidgets('a page opened without its object goes back instead of failing', (
    tester,
  ) async {
    await tester.pumpWidget(app(routerWith(start: '/needs')));
    await tester.pumpAndSettle();
    expect(find.text('home page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a page opened with an object of another kind goes back too', (
    tester,
  ) async {
    final router = routerWith(start: '/home');
    await tester.pumpWidget(app(router));
    router.go(
      '/needs',
      extra: <String, dynamic>{'id': 'a-map-after-a-restore'},
    );
    await tester.pumpAndSettle();
    expect(find.text('home page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a page opened with its object shows it', (tester) async {
    final router = routerWith(start: '/home');
    await tester.pumpWidget(app(router));
    router.go('/needs', extra: 7);
    await tester.pumpAndSettle();
    expect(find.text('got 7'), findsOneWidget);
  });
}
