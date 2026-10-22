// A team member's page shows what they sold: the numbers of a period, the latest sales (each opens
// the sale), and the way to the full list and the analysis.
import 'dart:async';
import 'dart:ui' show Size;

import 'package:biobalance/app/router.dart';
import 'package:biobalance/features/network/network_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'analytics_test.dart' as a;
import 'support/harness.dart';

Person amira({String role = 'VENDEUR'}) => Person.fromJson({
  'id': 'u1',
  'name': 'Amira Gharbi',
  'email': 'a@x.tn',
  'phone': '+21621345678',
  'role': role,
  'status': 'ACTIVE',
  'regionId': 'r1',
  'pdvId': 'p1',
  'activated': true,
});

void main() {
  testWidgets('the admin sees the numbers and the latest sales of a salesman', (
    tester,
  ) async {
    final s = a.analyticsServer();
    final container = await launch(
      tester,
      s,
      language: 'en',
      size: const Size(412, 1600),
    );
    unawaited(
      container.read(routerProvider).push('/people/u1', extra: amira()),
    );
    await settle(tester);
    expect(find.text('Sales'), findsWidgets);
    // The numbers of the last 30 days, for this seller only.
    expect(find.text('630'), findsOneWidget);
    final asked = s.calls.where((c) => c.path == '/v1/analytics/overview');
    expect(
      asked.any((c) => c.queryParameters['sellerId'] == 'u1'),
      isTrue,
      reason: 'the numbers are asked for this seller',
    );
    // A sale is listed, and tapping hints at what can be done with it.
    expect(find.text('Latest sales'), findsOneWidget);
    expect(find.text('Tap a sale to see it or correct it.'), findsOneWidget);
    expect(find.text('All sales'), findsOneWidget);
    expect(find.text('Full analysis'), findsOneWidget);
    // Another period asks again.
    final before = asked.length;
    await tester.tap(find.text('7 days'));
    await settle(tester);
    expect(
      s.calls.where((c) => c.path == '/v1/analytics/overview').length,
      greaterThan(before),
    );
  });

  testWidgets(
    'a responsable sees no sales block for a person who is not a salesman',
    (tester) async {
      final s = a.analyticsServer();
      final container = await launch(
        tester,
        s,
        language: 'en',
        size: const Size(412, 1600),
      );
      unawaited(
        container
            .read(routerProvider)
            .push('/people/u1', extra: amira(role: 'RESPONSABLE')),
      );
      await settle(tester);
      expect(find.text('Latest sales'), findsNothing);
    },
  );
}
