import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show loadFonts, server;
import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, Object?> info(
  String id,
  String name, {
  Map<String, Object?>? boss,
  int pdvs = 0,
  bool deletable = false,
}) => {
  'id': id,
  'code': name.toUpperCase(),
  'name': name,
  'responsable': boss,
  'pdvs': pdvs,
  'groups': 0,
  'grossistes': 0,
  'members': 0,
  'deletable': deletable,
};

FakeServer world() => base.server('ADMIN')
  ..on('GET /v1/regions/overview', [
    info(
      'r1',
      'Nord',
      boss: {
        'id': 'u1',
        'name': 'Nora Ben Salah',
        'email': 'n@x.tn',
        'phone': null,
        'status': 'ACTIVE',
      },
      pdvs: 4,
    ),
    info('r2', 'Sahel', deletable: true),
  ]);

void main() {
  setUpAll(base.loadFonts);

  testWidgets('the admin sees each region with who looks after it', (
    tester,
  ) async {
    await launch(tester, world(), language: 'fr');
    await tester.tap(find.text('Plus').last);
    await settle(tester);
    await tester.tap(find.text('Régions').last);
    await settle(tester);
    expect(find.text('Nord'), findsOneWidget);
    expect(find.text('Nora Ben Salah'), findsOneWidget);
    expect(find.text('Sahel'), findsOneWidget);
    expect(find.text('Pas encore de responsable'), findsOneWidget);
    expect(find.text('Nouvelle région'), findsOneWidget);
    await screenshot(tester, '55-regions');
  });

  testWidgets('a region can be deleted only when it is empty', (tester) async {
    final s = world()..on('DELETE /v1/regions/r2', {'ok': true});
    await launch(tester, s, language: 'fr');
    await tester.tap(find.text('Plus').last);
    await settle(tester);
    await tester.tap(find.text('Régions').last);
    await settle(tester);
    final menus = find.byIcon(Icons.more_vert);
    expect(menus, findsNWidgets(2));
    // Nord holds stores: it only offers a rename.
    await tester.tap(menus.first);
    await settle(tester);
    expect(find.text('Renommer la région'), findsOneWidget);
    expect(find.text('Supprimer la région'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    // Sahel is empty: it can be deleted, after a confirmation.
    await tester.tap(menus.last);
    await settle(tester);
    await tester.tap(find.text('Supprimer la région'));
    await settle(tester);
    await tester.tap(find.text('Supprimer la région').last);
    await settle(tester);
    expect(
      s.calls.where((c) => c.method == 'DELETE' && c.path == '/v1/regions/r2'),
      hasLength(1),
    );
  });

  testWidgets('the admin creates a region', (tester) async {
    final s = world()..on('POST /v1/regions', {'id': 'r9', 'name': 'Sfax'});
    await launch(tester, s, language: 'fr');
    await tester.tap(find.text('Plus').last);
    await settle(tester);
    await tester.tap(find.text('Régions').last);
    await settle(tester);
    await tester.tap(find.text('Nouvelle région'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Sfax');
    await tester.tap(find.text('Enregistrer').last);
    await settle(tester);
    final posted = s.calls.where(
      (c) => c.method == 'POST' && c.path == '/v1/regions',
    );
    expect(posted.single.data, {'name': 'Sfax'});
  });
}
