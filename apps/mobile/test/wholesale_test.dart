import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/order_workflow.dart';
import 'package:biobalance/domain/models/workspace_scope.dart';
import 'package:biobalance/ui/features/wholesale/supplier_orders_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_test.dart' show MemoryDraftRepository;

const grossiste = UserAccount(
  id: 'grossiste',
  name: 'Grossiste',
  email: 'grossiste@example.test',
  admin: false,
);
final depot = Store.fromJson({
  'id': 'depot',
  'organizationId': 'wholesale',
  'organizationName': 'Grossiste Nord',
  'organizationKind': 'wholesale',
  'name': 'Grossiste Nord',
  'permissions': ['manage', 'receive'],
});
final destination = Store.fromJson({
  'id': 'store',
  'organizationId': 'org',
  'name': 'Pharmacie Tunis',
  'permissions': ['manage'],
});

List<Json> fulfillment({int inTransit = 0, int received = 0}) => [
  {
    'productId': 'p',
    'ordered': 8,
    'received': received,
    'inTransit': inTransit,
    'remainingToDispatch': 8 - received - inTransit,
    'remainingToReceive': 8 - received,
  },
];

void main() {
  test('a depot is never a selling store, even for its manager', () {
    expect(depot.wholesale, isTrue);
    expect(depot.canManage, isTrue);
    expect(depot.canSell, isFalse);
    final retail = Store.fromJson({
      ...depot.toJson(),
      'organizationKind': 'retail',
    });
    expect(retail.canSell, isTrue);
    // The kind survives the cache round trip.
    expect(Store.fromJson(depot.toJson()).wholesale, isTrue);
    expect(
      PartnerGroup.fromJson({'id': 'g', 'name': 'G', 'kind': 'wholesale'})
          .wholesale,
      isTrue,
    );
    expect(PartnerGroup.fromJson({'id': 'g', 'name': 'G'}).wholesale, isFalse);
  });

  test('one party handles an order: BioBalance or its assigned grossiste', () {
    Json order([String? supplier]) => {
      'status': 'requested',
      'supplierStoreId': supplier,
      'supplierName': supplier == null ? null : 'Grossiste Nord',
    };
    OrderWorkflow admin(Json o, List<Json> f, {bool wholesale = false}) =>
        OrderWorkflow(
          o,
          f,
          admin: true,
          manager: true,
          wholesaleStore: wholesale,
        );
    final own = admin(order(), fulfillment());
    expect(own.canPrepare, isTrue);
    expect(own.canAssign, isTrue);
    final assigned = admin(order('depot'), fulfillment());
    expect(assigned.assigned, isTrue);
    expect(assigned.canPrepare, isFalse);
    expect(assigned.canDispatch, isFalse);
    // The assignment can still be changed or taken back until shipping starts.
    expect(assigned.canAssign, isTrue);
    expect(assigned.nextStep, contains('Grossiste Nord'));
    expect(admin(order('depot'), fulfillment(inTransit: 3)).canAssign, isFalse);
    expect(admin(order('depot'), fulfillment(received: 2)).canAssign, isFalse);
    // A grossiste's own order always stays with BioBalance.
    expect(admin(order(), fulfillment(), wholesale: true).canAssign, isFalse);
    final manager = OrderWorkflow(
      order('depot'),
      fulfillment(),
      admin: false,
      manager: true,
    );
    expect(manager.canAssign, isFalse);
    expect(manager.nextStep, contains('Grossiste Nord'));
  });

  testWidgets(
    'shipping proposes the earliest lots, keeps to stock and sends lots with one delivery identity',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory()),
          api = ApiClient(baseUrl: 'http://test')
            ..authenticate('token', accountId: grossiste.id);
      final vm = WorkspaceViewModel(
        grossiste,
        MemoryDraftRepository(db, api),
        api,
      );
      vm.state = WorkspaceState(
        store: depot,
        stores: [depot],
        data: StoreData({
          'products': [
            {'id': 'p', 'reference': 'SERUM', 'name': 'Sérum', 'active': true},
          ],
          'lots': [
            {
              'id': 'late',
              'productId': 'p',
              'batch': 'B',
              'expiry': '2099-01-01',
              'sellable': 10,
              'damaged': 0,
              'version': 1,
            },
            {
              'id': 'early',
              'productId': 'p',
              'batch': 'A',
              'expiry': '2098-01-01',
              'sellable': 5,
              'damaged': 0,
              'version': 1,
            },
            {
              'id': 'old',
              'productId': 'p',
              'batch': 'X',
              'expiry': '2020-01-01',
              'sellable': 9,
              'damaged': 0,
              'version': 1,
            },
          ],
        }),
      );
      final sent = <Json>[];
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            home: SupplierDispatchScreen(
              parent: vm,
              depot: depot,
              destination: destination,
              order: {'id': 'order', 'version': 4},
              lines: fulfillment(),
              submit: (command, version) async {
                expect(version, 4);
                sent.add(command);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The expired lot is not offered; the earliest lot is filled first.
      expect(find.textContaining('Lot X'), findsNothing);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, '5');
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, '3');
      // A lot cannot give more than it holds.
      await tester.enterText(fields.at(0), '6');
      await tester.tap(find.text('Confirmer l’expédition'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(find.textContaining('ne contient que 5'), findsOneWidget);
      await tester.enterText(fields.at(0), '5');
      await tester.enterText(fields.at(1), '2');
      await tester.tap(find.text('Confirmer l’expédition'));
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(sent.single['type'], 'delivery.dispatch');
      expect(sent.single['orderId'], 'order');
      expect(sent.single['lines'], [
        {
          'productId': 'p',
          'quantity': 7,
          'allocations': [
            {'lotId': 'early', 'quantity': 5},
            {'lotId': 'late', 'quantity': 2},
          ],
        },
      ]);
      expect(sent.single['deliveryId'], isNotEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      await db.close();
    },
  );
}
