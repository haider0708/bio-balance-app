// A responsable the admin allowed may suggest the grossiste of a store's restock; the admin
// approves it in one tap, and turns the permission on and off in the settings.
import 'dart:async';
import 'dart:convert';

import 'package:biobalance/app/router.dart';
import 'package:flutter/material.dart' show SizedBox, SwitchListTile;
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

Object? sent(FakeServer s, String method, [String? path]) => jsonDecode(
  jsonEncode(
    s.calls
        .lastWhere(
          (c) => c.method == method && (path == null || c.path == path),
        )
        .data,
  ),
);

Map<String, Object?> store() => {
  'id': 'p1',
  'name': 'Para Lac',
  'status': 'ACTIVE',
  'address': 'x',
  'city': 'Tunis',
  'regionId': 'r1',
  'memberCount': 2,
  'initialStock': 'APPROVED',
};

Map<String, Object?> me({
  required bool canChoose,
  String role = 'RESPONSABLE',
}) => {...meJson(role: role), 'canChooseSupplier': canChoose};

Map<String, Object?> order({Map<String, Object?>? suggested}) => {
  'id': 'o1',
  'number': 'RS-2026-000001',
  'status': 'REQUESTED',
  'regionId': 'r1',
  'destination': {'id': 'p1', 'kind': 'PDV', 'name': 'Para Lac'},
  'requestedBy': {'id': 'x', 'name': 'Nora'},
  'createdAt': DateTime.now().toIso8601String(),
  'suggestedSupplier': suggested,
  'lines': [
    {
      'productId': 'a',
      'name': 'Serum C',
      'family': 'Serums',
      'requested': 6,
      'shipped': null,
      'received': null,
      'approved': null,
    },
  ],
};

void main() {
  setUpAll(() {});

  testWidgets('an allowed responsable suggests a grossiste with its coverage', (
    tester,
  ) async {
    final s = FakeServer()
      ..on('GET /v1/me', me(canChoose: true))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/pdvs', [store()])
      ..on('GET /v1/depots', <Object>[])
      ..on('GET /v1/products', [productJson('a', 'Serum C')])
      ..on('POST /v1/restocks/suppliers', [
        {
          'id': 'd1',
          'name': 'Dépôt Hedi',
          'city': 'Tunis',
          'regionName': 'Nord',
          'missing': 0,
          'lines': [],
        },
        {
          'id': 'd2',
          'name': 'Dépôt Sfax',
          'city': 'Sfax',
          'regionName': 'Sud',
          'missing': 1,
          'lines': [],
        },
      ])
      ..on('POST /v1/restocks', order(suggested: {'id': 'd2', 'name': 'x'}));
    final container = await launch(tester, s, language: 'en');
    unawaited(
      container.read(routerProvider).push('/restocks/new', extra: 'p1'),
    );
    await settle(tester);
    // Without products there is nothing to cover yet.
    await tester.tap(find.text('Grossiste (optional)'));
    await settle(tester, frames: 5);
    expect(find.text('Add the products first.'), findsOneWidget);
    // Add a product, then choose the grossiste that covers it.
    await tester.tap(find.text('Add a product'));
    await settle(tester);
    await tester.tap(find.text('Serum C'));
    await tester.pump();
    await tester.tap(find.text('Add 1 product'));
    await settle(tester);
    await tester.tap(find.text('Grossiste (optional)'));
    await settle(tester);
    expect(find.text('Has everything'), findsOneWidget);
    expect(find.text('Short of 1 product'), findsOneWidget);
    await tester.tap(find.text('Dépôt Hedi'));
    await settle(tester);
    expect(find.text('Dépôt Hedi'), findsOneWidget); // now shown on the form
    await tester.tap(find.text('Send the request'));
    await settle(tester);
    final body = sent(s, 'POST', '/v1/restocks') as Map;
    expect(body['supplierId'], 'd1');
    expect(body['destId'], 'p1');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  });

  testWidgets('a responsable who is not allowed sees nothing new', (
    tester,
  ) async {
    final s = FakeServer()
      ..on('GET /v1/me', me(canChoose: false))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/pdvs', [store()])
      ..on('GET /v1/depots', <Object>[]);
    final container = await launch(tester, s, language: 'en');
    unawaited(
      container.read(routerProvider).push('/restocks/new', extra: 'p1'),
    );
    await settle(tester);
    expect(find.text('Grossiste (optional)'), findsNothing);
  });

  testWidgets('the admin approves the suggested grossiste in one tap', (
    tester,
  ) async {
    final s = FakeServer()
      ..on('GET /v1/me', meJson(role: 'ADMIN'))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on(
        'GET /v1/restocks/o1',
        order(suggested: {'id': 'd2', 'name': 'Dépôt Sfax'}),
      )
      ..on('POST /v1/restocks/o1/assign', <String, Object?>{});
    final container = await launch(tester, s, language: 'en');
    unawaited(container.read(routerProvider).push('/restocks/o1'));
    await settle(tester);
    expect(find.text('Suggested grossiste'), findsOneWidget);
    expect(find.text('Dépôt Sfax'), findsOneWidget);
    await tester.tap(find.text('Assign to Dépôt Sfax'));
    await settle(tester);
    expect(sent(s, 'POST', '/v1/restocks/o1/assign'), {'depotId': 'd2'});
  });

  testWidgets('the admin turns the choice on and allows one responsable', (
    tester,
  ) async {
    Map<String, Object?> settings(bool on) => {
      'minimumBuild': {'ios': 0, 'android': 0},
      'stores': {'ios': null, 'android': null},
      'hours': {
        'enabled': false,
        'days': List.generate(7, (_) => {'open': '08:00', 'close': '21:00'}),
      },
      'supplierChoice': on,
      'open': true,
      'nextOpening': null,
    };
    var on = false;
    final s = FakeServer()
      ..on('GET /v1/me', meJson(role: 'ADMIN'))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..handle('GET /v1/settings', (_) => (status: 200, body: settings(on)))
      ..handle('PUT /v1/settings', (r) {
        on = (r.data as Map)['supplierChoice'] == true;
        return (status: 200, body: settings(on));
      })
      ..on('GET /v1/users', [
        {
          'id': 'u9',
          'name': 'Nora Nord',
          'email': 'n@x.tn',
          'role': 'RESPONSABLE',
          'status': 'ACTIVE',
          'activated': true,
          'regionId': 'r1',
          'canChooseSupplier': false,
        },
      ])
      ..on('PUT /v1/users/u9/supplier-choice', <String, Object?>{});
    final container = await launch(tester, s, language: 'en');
    unawaited(container.read(routerProvider).push('/app-settings'));
    await settle(tester);
    expect(find.text('Nora Nord'), findsNothing);
    await tester.tap(
      find.widgetWithText(
        SwitchListTile,
        'Responsables may suggest the grossiste',
      ),
    );
    await settle(tester);
    expect(sent(s, 'PUT', '/v1/settings'), {'supplierChoice': true});
    expect(find.text('Nora Nord'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Nora Nord'));
    await settle(tester);
    expect(sent(s, 'PUT', '/v1/users/u9/supplier-choice'), {'allowed': true});
  });
}
