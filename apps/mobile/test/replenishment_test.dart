import 'dart:convert';

import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/order_fulfillment.dart';
import 'package:biobalance/ui/features/inventory/inventory_screens.dart';
import 'package:biobalance/ui/features/replenishment/order_screens.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_test.dart' show MemoryDraftRepository;

const user = UserAccount(
  id: 'manager',
  name: 'Manager',
  email: 'test@example.test',
  admin: false,
);
final store = Store.fromJson({
  'id': 'store',
  'organizationId': 'org',
  'name': 'Magasin Tunis',
  'permissions': ['manage', 'receive'],
});
final delivery = <String, dynamic>{
  'id': 'delivery',
  'version': 1,
  'lines': [
    {'productId': 'p', 'quantity': 6},
  ],
};
StoreData data() => StoreData({
  'products': [
    {'id': 'p', 'reference': 'SERUM', 'name': 'Sérum', 'active': true},
  ],
  'lots': [
    {
      'id': 'lot',
      'productId': 'p',
      'batch': 'A',
      'expiry': '2029-12-31',
      'sellable': 3,
      'damaged': 0,
      'version': 2,
    },
  ],
  'config': [
    {'productId': 'p', 'threshold': 5},
  ],
  'orders': [
    {
      'id': 'order',
      'fulfillment': [
        {
          'productId': 'p',
          'ordered': 10,
          'received': 4,
          'inTransit': 3,
          'remainingToDispatch': 3,
          'remainingToReceive': 6,
        },
      ],
    },
  ],
  'deliveries': [delivery],
});

class RecordingWorkspace extends WorkspaceViewModel {
  RecordingWorkspace(super.user, super.repository, super.api);
  Json? submitted;
  Store? submittedStore;
  @override
  Future<void> queue(
    Json command, {
    int? expectedVersion,
    Json effect = const {},
    Store? targetStore,
    String? draftKey,
  }) async {
    submitted = command;
    submittedStore = targetStore;
    if (draftKey != null) {
      await repository.saveDraft(user.id, targetStore!.id, draftKey, {});
    }
  }

  @override
  Future<void> online(
    Json command, {
    int? expectedVersion,
    Store? targetStore,
  }) async {
    submitted = command;
    submittedStore = targetStore;
  }
}

void main() {
  testWidgets(
    'alert order draft shows stock, threshold and supply, retains original store',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory()),
          api = ApiClient(baseUrl: 'http://test')
            ..authenticate('token', accountId: user.id);
      final vm = RecordingWorkspace(user, MemoryDraftRepository(db, api), api);
      // Use the actual controller-owned repository for draft checks.
      final drafts = vm.repository as MemoryDraftRepository;
      vm.state = WorkspaceState(store: store, stores: [store], data: data());
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            home: OrderEditor(vm: vm, initialProductId: 'p'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Stock : 3 · Seuil : 5\nEn attente : 6 unités'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Unités à commander'),
        '7',
      );
      await tester.pumpAndSettle();
      final original = await drafts.draft(user.id, store.id, 'order');
      expect(original!['values']['p'], '7');
      final orderId = original['values']['_orderId'];
      vm.state = WorkspaceState(
        store: Store.fromJson({...store.toJson(), 'id': 'other'}),
        data: data(),
      );
      await tester.ensureVisible(find.text('Envoyer la commande'));
      await tester.tap(find.text('Envoyer la commande'));
      await tester.pumpAndSettle();
      expect(vm.submittedStore!.id, store.id);
      expect(vm.submitted, {
        'type': 'order.create',
        'orderId': orderId,
        'lines': [
          {'productId': 'p', 'quantity': 7},
        ],
      });
      expect(await drafts.draft(user.id, store.id, 'order'), isEmpty);
      expect(FulfillmentLine.outstanding(data(), 'p'), 6);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      await db.close();
    },
  );
  testWidgets(
    'zero receipt needs a reason and explicit confirmation, supports cancellation',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory()),
          api = ApiClient(baseUrl: 'http://test')
            ..authenticate('token', accountId: user.id);
      final vm = RecordingWorkspace(user, MemoryDraftRepository(db, api), api);
      vm.state = WorkspaceState(store: store, stores: [store], data: data());
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            home: ReceiptScreen(vm: vm, delivery: delivery),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Aucune unité reçue'));
      await tester.tap(find.text('Aucune unité reçue'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirmer la réception'));
      await tester.tap(find.text('Confirmer la réception'));
      await tester.pumpAndSettle();
      expect(vm.submitted, isNull);
      expect(
        find.text('Expliquez pourquoi aucune unité n’a été reçue.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Colis non arrivé');
      await tester.ensureVisible(find.text('Confirmer la réception'));
      await tester.tap(find.text('Confirmer la réception'));
      await tester.pumpAndSettle();
      expect(vm.submitted, isNull);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(vm.submitted, isNull);
      final draft = await vm.repository.draft(
        user.id,
        store.id,
        'receipt:delivery',
      );
      expect(draft!['note'], 'Colis non arrivé');
      await tester.tap(find.text('Confirmer la réception'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer zéro unité'));
      await tester.pumpAndSettle();
      expect(vm.submitted, {
        'type': 'delivery.receive',
        'deliveryId': 'delivery',
        'lines': [],
        'note': 'Colis non arrivé',
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      await db.close();
    },
  );
  test('offline receipt persists one pending reception and prevents duplicate local stock effects', () async {
    final db = AppDatabase(NativeDatabase.memory()),
        api = ApiClient(baseUrl: 'http://test');
    addTearDown(db.close);
    final repo = OfflineRepository(db, api);
    await db
        .into(db.cacheEntries)
        .insert(
          CacheEntriesCompanion.insert(
            accountId: user.id,
            storeId: store.id,
            resource: 'meta',
            entityId: 'meta',
            payload: jsonEncode(data().raw),
          ),
        );
    final operation = <String, dynamic>{
      'operationId': 'op',
      'organizationId': store.organizationId,
      'storeId': store.id,
      'payloadVersion': 2,
      'expectedVersion': 1,
      'command': {
        'type': 'delivery.receive',
        'deliveryId': 'delivery',
        'lines': [],
        'note': 'Colis perdu',
      },
    };
    await repo.enqueue(user, store, operation, {});
    expect(
      (await repo.load(user, store))!.list('deliveries').single['syncStatus'],
      'pending',
    );
    await expectLater(
      repo.enqueue(user, store, {...operation, 'operationId': 'duplicate'}, {}),
      throwsA(
        isA<AppFailure>().having((e) => e.code, 'code', 'DELIVERY_PENDING'),
      ),
    );
    expect(await repo.operations(user.id, store.id), hasLength(1));
    expect((await repo.load(user, store))!.lots.single.sellable, 3);
  });
}
