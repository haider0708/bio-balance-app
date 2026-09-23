import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/money.dart';
import 'package:biobalance/domain/use_cases/record_sale.dart';
import 'package:biobalance/ui/features/sales/sale_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_test.dart' show MemoryDraftRepository;

const user = UserAccount(
  id: 'a',
  name: 'Seller',
  email: 'a@example.test',
  admin: false,
);
final store = Store.fromJson({
  'id': 'store',
  'organizationId': 'org',
  'name': 'Test',
  'permissions': ['sell'],
});
void main() {
  testWidgets('seller enters a missing batch while recording a manual sale', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory()),
        api = ApiClient(baseUrl: 'http://test')
          ..authenticate('token', accountId: 'a');
    final repository = MemoryDraftRepository(db, api),
        vm = WorkspaceViewModel(user, repository, api);
    vm.state = WorkspaceState(
      store: store,
      stores: [store],
      data: StoreData({
        'products': [
          {'id': 'p', 'name': 'Sérum', 'reference': 'SERUM'},
        ],
        'lots': [],
        'config': [
          {'productId': 'p', 'priceMillimes': '2000'},
        ],
      }),
    );
    SaleLine? result;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: vm,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<SaleLine>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LineEditor(workspace: vm, productId: 'p'),
                    ),
                  );
                },
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Lot manquant ? Le renseigner'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lot manquant ? Le renseigner'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Numéro du lot'),
      'MISSING-UI',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Péremption : JJ/MM/AAAA ou MM/AAAA'),
      '12/2029',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Unités vendues'),
      '2',
    );
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('un écart sera signalé'), findsOneWidget);
    await tester.ensureVisible(find.text('Ajouter à la vente'));
    await tester.tap(find.text('Ajouter à la vente'));
    await tester.pumpAndSettle();
    expect(result!.quantity, 2);
    expect(result!.batchDeclarations.single.batch, 'MISSING-UI');
    expect(result!.batchDeclarations.single.expiry, '2029-12-31');
    expect(
      result!.allocations.single['lotId'],
      result!.batchDeclarations.single.lotId,
    );
    expect(tester.takeException(), isNull);
    expect(vm.state.data!.lots, isEmpty);
    expect(
      repository.saved.values.any(
        (draft) => draft.toString().contains('MISSING-UI'),
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
    await db.close();
  });
  test(
    'offline correction rejects quantities already returned before enqueuing',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = MemoryDraftRepository(db, ApiClient(baseUrl: 'http://test'));
      await expectLater(
        RecordSale(repo).execute(
          user,
          store,
          [
            SaleLine(
              id: 'line',
              productId: 'p',
              quantity: 1,
              price: Money(1000),
              allocations: [
                {'lotId': 'lot', 'quantity': 1},
              ],
            ),
          ],
          original: {
            'id': 'sale',
            'version': 2,
            'sellerId': user.id,
            'occurredAt': '2026-09-21T12:00:00Z',
            'returned': {'line:lot': 2},
            'lines': [],
          },
        ),
        throwsA(
          isA<AppFailure>().having((e) => e.code, 'code', 'ALREADY_RETURNED'),
        ),
      );
      expect(await repo.operations(user.id, store.id), isEmpty);
    },
  );
}
