// The responsable corrects a count (waiting: on hold for the admin; approved: with a reason, at
// once), and the admin sees a count on hold.
import 'dart:async';
import 'dart:convert';

import 'package:biobalance/app/router.dart';
import 'package:flutter/material.dart' show IconData, SizedBox, TextField;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, Object?> declaration({
  String status = 'PENDING',
  Map<String, Object?>? editing,
  String? correctableUntil,
}) => {
  'id': 'd1',
  'kind': 'INITIAL',
  'status': status,
  'location': {'id': 'p1', 'kind': 'PDV', 'name': 'Para Lac'},
  'photoId': 'ph1',
  'photoIds': ['ph1'],
  'note': null,
  'createdBy': {'id': 'x', 'name': 'Nora'},
  'createdAt': DateTime.now().toIso8601String(),
  'decidedBy': null,
  'decidedAt': null,
  'decisionNote': null,
  'editing': editing,
  'correctableUntil': correctableUntil,
  'lines': [
    {
      'productId': 'a',
      'name': 'Serum C',
      'family': 'Serums',
      'quantity': 20,
      'approvedQuantity': status == 'APPROVED' ? 20 : null,
      'addedByAdmin': false,
    },
    {
      'productId': 'b',
      'name': 'Niacinamide',
      'family': 'Serums',
      'quantity': 10,
      'approvedQuantity': status == 'APPROVED' ? 10 : null,
      'addedByAdmin': status == 'APPROVED',
    },
  ],
};

FakeServer server(String role, Map<String, Object?> d) => FakeServer()
  ..on('GET /v1/me', meJson(role: role))
  ..on('GET /v1/notifications/unread-count', {'unread': 0})
  ..on('GET /v1/dashboard', <String, Object?>{})
  ..on('GET /v1/stock/declarations/d1', d)
  ..on('POST /v1/stock/declarations/d1/edit', d)
  ..on('DELETE /v1/stock/declarations/d1/edit', d)
  ..on('PUT /v1/stock/declarations/d1', d);

Object? sent(FakeServer s, String method) =>
    jsonDecode(jsonEncode(s.calls.lastWhere((c) => c.method == method).data));

/// Taps the "+" or "−" on the row of a product (other "+" icons exist: add a photo, add a product).
Future<void> tapStepper(
  WidgetTester tester,
  String product,
  IconData icon,
) async {
  final rowY = tester.getCenter(find.text(product)).dy;
  final centers = [
    for (final e in find.byIcon(icon).evaluate())
      tester.getCenter(find.byWidget(e.widget)),
  ]..sort((a, b) => (a.dy - rowY).abs().compareTo((b.dy - rowY).abs()));
  await tester.tapAt(centers.first);
  await tester.pump();
}

/// Product photos stay cached for five minutes after their screen closes: let that time pass.
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 6));
}

void main() {
  testWidgets('a waiting count is put on hold, corrected and sent back', (
    tester,
  ) async {
    final s = server('RESPONSABLE', declaration());
    final container = await launch(tester, s, language: 'en');
    unawaited(container.read(routerProvider).push('/stock/declarations/d1'));
    await settle(tester);
    await tester.tap(find.text('Correct this count'));
    await settle(tester);
    // Opening it puts it on hold for the admin.
    expect(s.count('POST /v1/stock/declarations/d1/edit'), 1);
    expect(find.textContaining('the admin cannot decide it'), findsOneWidget);
    // The quantities are the declared ones; the responsable changes the first.
    expect(find.text('20'), findsWidgets);
    await tapStepper(tester, 'Serum C', LucideIcons.plus);
    await tester.tap(find.text('Send to BioBalance'));
    await settle(tester);
    final body = sent(s, 'PUT') as Map;
    expect(body['photoIds'], ['ph1']);
    expect((body['lines'] as List).length, 2);
    expect(((body['lines'] as List).first as Map)['quantity'], 21);
    expect(body.containsKey('reason'), isFalse);
    await finish(tester);
  });

  testWidgets('leaving without saving gives the count back to the admin', (
    tester,
  ) async {
    final s = server('RESPONSABLE', declaration());
    final container = await launch(tester, s, language: 'en');
    unawaited(container.read(routerProvider).push('/stock/declarations/d1'));
    await settle(tester);
    await tester.tap(find.text('Correct this count'));
    await settle(tester);
    container.read(routerProvider).pop();
    await settle(tester);
    expect(s.count('DELETE /v1/stock/declarations/d1/edit'), 1);
    expect(s.count('PUT /v1/stock/declarations/d1'), 0);
    await finish(tester);
  });

  testWidgets('an approved count needs a reason to be corrected', (
    tester,
  ) async {
    final until = DateTime.now().add(const Duration(days: 2)).toIso8601String();
    final s = server(
      'RESPONSABLE',
      declaration(status: 'APPROVED', correctableUntil: until),
    );
    final container = await launch(tester, s, language: 'en');
    unawaited(container.read(routerProvider).push('/stock/declarations/d1'));
    await settle(tester);
    expect(find.text('Added by the admin'), findsOneWidget);
    await tester.tap(find.text('Correct this count'));
    await settle(tester);
    // An approved count is not put on hold: the admin is not waiting on it.
    expect(s.count('POST /v1/stock/declarations/d1/edit'), 0);
    await tapStepper(tester, 'Serum C', LucideIcons.plus);
    final save = find.text('Save the correction');
    // Without a reason nothing is sent.
    await tester.tap(save);
    await settle(tester, frames: 3);
    expect(s.count('PUT /v1/stock/declarations/d1'), 0);
    await tester.enterText(find.byType(TextField).first, 'Typed 20, was 21');
    await tester.pump();
    await tester.tap(save);
    await settle(tester);
    expect((sent(s, 'PUT') as Map)['reason'], 'Typed 20, was 21');
    await finish(tester);
  });

  testWidgets('the admin sees a count on hold and cannot decide it', (
    tester,
  ) async {
    final s = server(
      'ADMIN',
      declaration(
        editing: {
          'by': {'id': 'x', 'name': 'Nora'},
          'until': DateTime.now()
              .add(const Duration(minutes: 20))
              .toIso8601String(),
        },
      ),
    );
    final container = await launch(tester, s, language: 'en');
    unawaited(container.read(routerProvider).push('/stock/declarations/d1'));
    await settle(tester);
    expect(
      find.text(
        'Nora is correcting this count. You can decide it when they finish.',
      ),
      findsOneWidget,
    );
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    await finish(tester);
  });

  testWidgets('a quantity below what was sold says which product and how low', (
    tester,
  ) async {
    final s = server('RESPONSABLE', declaration())
      ..handle(
        'PUT /v1/stock/declarations/d1',
        (_) => (
          status: 409,
          body: {
            'code': 'BELOW_SOLD',
            'message': 'x',
            'details': {
              'products': [
                {'productId': 'a', 'name': 'Serum C', 'minimum': 15},
              ],
            },
          },
        ),
      );
    final container = await launch(tester, s, language: 'en');
    unawaited(container.read(routerProvider).push('/stock/declarations/d1'));
    await settle(tester);
    await tester.tap(find.text('Correct this count'));
    await settle(tester);
    await tapStepper(tester, 'Serum C', LucideIcons.minus);
    await tester.tap(find.text('Send to BioBalance'));
    await settle(tester);
    expect(find.textContaining('Serum C: at least 15'), findsOneWidget);
    await finish(tester);
  });
}
