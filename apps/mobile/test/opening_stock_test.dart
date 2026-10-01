import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/features/inventory/inventory_screens.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_test.dart' show MemoryDraftRepository;

const user = UserAccount(
  id: 'manager',
  name: 'Responsable',
  email: 'manager@example.test',
  admin: false,
);

Store store({bool closed = false}) => Store.fromJson({
  'id': 'store',
  'organizationId': 'org',
  'name': 'Pharmacie Tunis',
  'permissions': ['manage'],
  if (closed) 'openingClosedAt': '2026-10-01T10:00:00.000Z',
});

Future<void> pump(
  WidgetTester tester,
  Store s, {
  List<Map<String, dynamic>> lots = const [],
}) async {
  final db = AppDatabase(NativeDatabase.memory()),
      api = ApiClient(baseUrl: 'http://test')
        ..authenticate('token', accountId: user.id);
  final vm = WorkspaceViewModel(user, MemoryDraftRepository(db, api), api);
  vm.state = WorkspaceState(
    store: s,
    stores: [s],
    data: StoreData({'lots': lots, 'products': const []}),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: vm,
      child: MaterialApp(
        home: Scaffold(body: OpeningStockCard(vm: vm)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
    await db.close();
  });
}

void main() {
  testWidgets('a store that never declared its stock is asked once', (t) async {
    await pump(t, store());
    expect(find.text('Avez-vous déjà du stock ?'), findsOneWidget);
    expect(find.text('Oui, je le saisis'), findsOneWidget);
    expect(find.text('Non, je commande'), findsOneWidget);
  });

  testWidgets('the question is gone once the stock is declared', (t) async {
    await pump(t, store(closed: true));
    expect(find.text('Avez-vous déjà du stock ?'), findsNothing);
  });

  testWidgets('a store that already holds lots is never asked', (t) async {
    await pump(
      t,
      store(),
      lots: [
        {
          'id': 'lot',
          'productId': 'p',
          'batch': 'A',
          'expiry': '2030-01-31',
          'sellable': 3,
          'damaged': 0,
          'version': 1,
        },
      ],
    );
    expect(find.text('Avez-vous déjà du stock ?'), findsNothing);
  });
}
