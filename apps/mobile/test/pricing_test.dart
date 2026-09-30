import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/features/catalog/product_information.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_test.dart' show MemoryDraftRepository;

UserAccount account({bool admin = false}) => UserAccount(
  id: admin ? 'admin' : 'person',
  name: 'Person',
  email: 'person@example.test',
  admin: admin,
);
Store store(List<String> permissions) => Store.fromJson({
  'id': 'store',
  'organizationId': 'org',
  'name': 'Pharmacie',
  'permissions': permissions,
});
final product = <String, dynamic>{
  'id': 'p',
  'name': 'Sérum',
  'reference': 'SERUM',
  'referencePriceMillimes': '55000',
  'priceStatus': 'verified',
};

Future<void> show(WidgetTester tester, UserAccount user, Store? current) async {
  final db = AppDatabase(NativeDatabase.memory()),
      api = ApiClient(baseUrl: 'http://test')
        ..authenticate('token', accountId: user.id);
  final vm = WorkspaceViewModel(user, MemoryDraftRepository(db, api), api);
  vm.state = WorkspaceState(store: current, stores: [?current]);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: vm,
      child: MaterialApp(
        home: Scaffold(
          body: ProductInformation(vm: vm, product: product),
        ),
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
  testWidgets(
    'BioBalance sees the reference price and manages the price levels',
    (tester) async {
      await show(tester, account(admin: true), null);
      expect(find.text('Prix de référence'), findsOneWidget);
      expect(find.text('Prix de gros et d’approvisionnement'), findsOneWidget);
      expect(find.text('Historique des prix'), findsNothing);
    },
  );

  testWidgets(
    'a responsable sees his price history, never the reference price',
    (tester) async {
      await show(tester, account(), store(['manage', 'sell', 'receive']));
      expect(find.text('Prix de référence'), findsNothing);
      expect(find.text('Prix de gros et d’approvisionnement'), findsNothing);
      expect(find.text('Historique des prix'), findsOneWidget);
    },
  );

  testWidgets('a seller sees no price management at all', (tester) async {
    await show(tester, account(), store(['sell']));
    expect(find.text('Prix de référence'), findsNothing);
    expect(find.text('Historique des prix'), findsNothing);
    expect(find.text('Prix de gros et d’approvisionnement'), findsNothing);
  });
}
