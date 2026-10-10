import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show loadFonts, server;
import 'support/fake_server.dart';
import 'support/harness.dart';

/// Grossistes are warehouses without accounts: the admin and the responsable of the region handle them.
Map<String, Object?> depot(
  String id,
  String name, {
  String status = 'ACTIVE',
  bool counted = false,
  bool pending = false,
  String region = 'Nord',
}) => {
  'id': id,
  'name': name,
  'address': '1 rue du Dépôt',
  'city': 'Tunis',
  'phone': '20 111 222',
  'status': status,
  'region': {'id': 'r-$region', 'name': region},
  'photoIds': <String>[],
  'units': counted ? 120 : 0,
  'products': counted ? 6 : 0,
  'counted': counted,
  'countPending': pending,
};

FakeServer world(String role) {
  final list = [
    depot('d1', 'Dépôt Hedi', counted: true),
    depot('d2', 'Dépôt Mounir'),
    depot('d3', 'Dépôt Slim', status: 'SUSPENDED', region: 'Sud'),
  ];
  final s = base.server(role)..on('GET /v1/depots', list);
  for (final d in list) {
    s
      ..on('GET /v1/depots/${d['id']}', d)
      ..on(
        'GET /v1/stock/locations/${d['id']}',
        d['counted'] == true ? stockJson(['a', 'b', 'c']) : stockJson(const []),
      )
      ..on('GET /v1/stock/recounts', <Object?>[]);
  }
  // A counted grossiste has an approved first count; the others have none.
  s.handle('GET /v1/stock/declarations', (request) {
    final place = request.queryParameters['locationId'];
    final d = list.firstWhere((d) => d['id'] == place);
    return (
      status: 200,
      body: [
        if (d['counted'] == true)
          {
            'id': 'x-${d['id']}',
            'kind': 'INITIAL',
            'status': 'APPROVED',
            'location': {'id': d['id'], 'kind': 'DEPOT', 'name': d['name']},
            'photoIds': <String>[],
            'createdBy': {'id': 'u', 'name': 'Admin'},
            'createdAt': DateTime.now().toIso8601String(),
            'lines': <Object?>[],
          },
      ],
    );
  });
  return s;
}

void main() {
  setUpAll(base.loadFonts);

  testWidgets('the admin sees every grossiste, grouped by region', (
    tester,
  ) async {
    await launch(tester, world('ADMIN'), language: 'fr');
    await tester.tap(find.text('Plus').last);
    await settle(tester);
    await tester.tap(find.text('Grossistes').last);
    await settle(tester);
    expect(find.text('Dépôt Hedi'), findsOneWidget);
    expect(find.text('Dépôt Mounir'), findsOneWidget);
    expect(find.text('Dépôt Slim'), findsOneWidget);
    expect(find.text('Nord'), findsOneWidget);
    expect(find.text('Sud'), findsOneWidget);
    expect(find.text('Aucun stock saisi'), findsOneWidget);
    expect(find.text('Suspendu'), findsOneWidget);
    expect(find.text('Nouveau grossiste'), findsOneWidget);
    await screenshot(tester, '50-grossistes');
  });

  testWidgets('a responsable sees only a plain list and cannot create one', (
    tester,
  ) async {
    await launch(tester, world('RESPONSABLE'), language: 'fr');
    await tester.tap(find.text('Plus').last);
    await settle(tester);
    await tester.tap(find.text('Grossistes').last);
    await settle(tester);
    expect(find.text('Dépôt Hedi'), findsOneWidget);
    expect(find.text('Nouveau grossiste'), findsNothing);
  });

  testWidgets(
    'a counted grossiste: the admin can restock and correct it, the responsable can restock and ask for a recount',
    (tester) async {
      await launch(tester, world('ADMIN'), language: 'fr');
      await tester.tap(find.text('Plus').last);
      await settle(tester);
      await tester.tap(find.text('Grossistes').last);
      await settle(tester);
      await tester.tap(find.text('Dépôt Hedi'));
      await settle(tester);
      expect(find.text('Réapprovisionner'), findsOneWidget);
      expect(find.text('Corriger le stock'), findsOneWidget);
      expect(find.text('Demander un nouveau comptage'), findsNothing);
      await screenshot(tester, '51-grossiste-counted');
    },
  );

  testWidgets(
    'a grossiste without stock offers the first count to the responsable',
    (tester) async {
      await launch(tester, world('RESPONSABLE'), language: 'fr');
      await tester.tap(find.text('Plus').last);
      await settle(tester);
      await tester.tap(find.text('Grossistes').last);
      await settle(tester);
      await tester.tap(find.text('Dépôt Mounir'));
      await settle(tester);
      expect(find.text('Déclarer le stock'), findsOneWidget);
      expect(find.text('Réapprovisionner'), findsNothing);
      await screenshot(tester, '52-grossiste-empty');
    },
  );

  testWidgets(
    'a counted grossiste lets the responsable restock it and ask for a recount',
    (tester) async {
      await launch(tester, world('RESPONSABLE'), language: 'fr');
      await tester.tap(find.text('Plus').last);
      await settle(tester);
      await tester.tap(find.text('Grossistes').last);
      await settle(tester);
      await tester.tap(find.text('Dépôt Hedi'));
      await settle(tester);
      expect(find.text('Réapprovisionner'), findsOneWidget);
      expect(find.text('Demander un nouveau comptage'), findsOneWidget);
      expect(find.text('Corriger le stock'), findsNothing);
    },
  );

  testWidgets('a suspended grossiste takes nothing', (tester) async {
    await launch(tester, world('ADMIN'), language: 'fr');
    await tester.tap(find.text('Plus').last);
    await settle(tester);
    await tester.tap(find.text('Grossistes').last);
    await settle(tester);
    await tester.tap(find.text('Dépôt Slim'));
    await settle(tester);
    expect(find.text('Réapprovisionner'), findsNothing);
    expect(find.text('Déclarer le stock'), findsNothing);
  });

  testWidgets('the admin creates a grossiste', (tester) async {
    final s = world('ADMIN')..on('POST /v1/depots', depot('d9', 'Nouveau'));
    await launch(tester, s, language: 'fr');
    await tester.tap(find.text('Plus').last);
    await settle(tester);
    await tester.tap(find.text('Grossistes').last);
    await settle(tester);
    await tester.tap(find.text('Nouveau grossiste'));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'Dépôt Sfax');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Zone industrielle',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'Sfax');
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settle(tester);
    await tester.tap(find.text('Nord').last);
    await settle(tester);
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);
    final posted = s.calls.where(
      (c) => c.method == 'POST' && c.path == '/v1/depots',
    );
    expect(posted, hasLength(1));
    expect(posted.single.data, containsPair('name', 'Dépôt Sfax'));
    expect(posted.single.data, containsPair('regionId', isNotEmpty));
  });
}
