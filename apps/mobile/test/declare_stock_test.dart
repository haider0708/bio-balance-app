import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show server;
import 'support/fake_server.dart';
import 'support/harness.dart';

void main() {
  testWidgets('a responsable declares the first stock by choosing products from the catalogue', (tester) async {
    final s = base.server('RESPONSABLE')
      ..on('GET /v1/stock/locations/p1', stockJson([]))
      ..on('GET /v1/stock/declarations', <Object>[])
      ..on('GET /v1/pdvs/p1', {'id': 'p1', 'name': 'Para Lac', 'address': '1 rue', 'city': 'Tunis', 'phone': null, 'status': 'ACTIVE', 'regionId': 'r1', 'groupId': null, 'groupName': null, 'memberCount': 0, 'initialStock': 'NONE', 'members': <Object>[]})
      ..on('GET /v1/pdvs', [
        {'id': 'p1', 'name': 'Para Lac', 'address': '1 rue', 'city': 'Tunis', 'phone': null, 'status': 'ACTIVE', 'regionId': 'r1', 'groupId': null, 'groupName': null, 'memberCount': 0, 'initialStock': 'NONE'},
      ]);
    await launch(tester, s, language: 'en');
    await tester.tap(find.text('Stores').last);
    await settle(tester);
    await tester.tap(find.text('Para Lac').first);
    await settle(tester);
    await tester.tap(find.text('Declare the opening stock with a photo'));
    await settle(tester);
    await tester.tap(find.text('Declare the stock').first);
    await settle(tester);
    expect(find.text('This store has no stock yet'), findsOneWidget);
    await tester.tap(find.text('Add a product').first);
    await settle(tester);
    expect(find.text('BIOBALANCE SÉRUM VITAMINE C 30ML'), findsOneWidget);
    expect(find.text('BIOBALANCE SÉRUM NIACINAMIDE 10%'), findsOneWidget);
  });

  testWidgets('the product list is there for a responsable in the More menu', (tester) async {
    final s = base.server('RESPONSABLE');
    await launch(tester, s, language: 'en');
    await tester.tap(find.text('More').last);
    await settle(tester);
    await tester.tap(find.text('Catalog'));
    await settle(tester);
    expect(find.text('BIOBALANCE SÉRUM VITAMINE C 30ML'), findsOneWidget);
  });
}
