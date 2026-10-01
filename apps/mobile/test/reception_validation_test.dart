import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/features/replenishment/reception_validation_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_test.dart' show MemoryDraftRepository;

const admin = UserAccount(
  id: 'admin',
  name: 'BioBalance',
  email: 'admin@example.test',
  admin: true,
);
final store = Store.fromJson({
  'id': 'store',
  'organizationId': 'org',
  'name': 'Pharmacie Tunis',
  'permissions': ['manage'],
});
final delivery = <String, dynamic>{
  'id': 'delivery',
  'ticketNumber': 'BL-2026-000007',
  'version': 3,
  'status': 'pending_review',
  'sourceStoreId': 'depot',
  'lines': [
    {
      'productId': 'p',
      'quantity': 10,
      'allocations': [
        {'batch': 'A1', 'expiry': '2030-05-31', 'quantity': 10},
      ],
    },
  ],
  'claim': {
    'manualReason': 'Pas de caméra',
    'note': '',
    'lines': [
      {
        'productId': 'p',
        'batch': 'A1',
        'expiry': '2030-05-31',
        'quantity': 6,
        'condition': 'sellable',
      },
    ],
  },
};

class RecordingWorkspace extends WorkspaceViewModel {
  RecordingWorkspace(super.user, super.repository, super.api);
  Json? submitted;
  int? version;
  @override
  Future<void> online(
    Json command, {
    int? expectedVersion,
    Store? targetStore,
    String? supplierStoreId,
  }) async {
    submitted = command;
    version = expectedVersion;
  }
}

void main() {
  testWidgets(
    'BioBalance sees the shipment beside the claim, corrects it and validates',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory()),
          api = ApiClient(baseUrl: 'http://test')
            ..authenticate('token', accountId: admin.id);
      final vm = RecordingWorkspace(admin, MemoryDraftRepository(db, api), api);
      vm.state = WorkspaceState(
        store: store,
        stores: [store],
        data: StoreData({
          'products': [
            {'id': 'p', 'reference': 'SERUM', 'name': 'Sérum', 'active': true},
          ],
        }),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            home: ReceptionValidationScreen(vm: vm, delivery: delivery),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Réception sans scan'), findsOneWidget);
      expect(find.textContaining('Pas de caméra'), findsOneWidget);
      // Shipped 10, the store claims 6: 4 are missing and BioBalance decides.
      expect(find.textContaining('Expédié : 10'), findsOneWidget);
      expect(find.textContaining('manque 4'), findsOneWidget);
      expect(find.textContaining('retournent au dépôt'), findsOneWidget);
      // A decision needs its explanation.
      await tester.tap(
        find.widgetWithText(FilledButton, 'Valider la réception'),
      );
      await tester.pumpAndSettle();
      expect(vm.submitted, isNull);
      await tester.enterText(
        find.byType(TextField).last,
        'Vérifié avec le dépôt',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Valider la réception'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
      await tester.pumpAndSettle();
      expect(vm.submitted!['type'], 'delivery.validate');
      expect(vm.submitted!['deliveryId'], 'delivery');
      expect(vm.submitted!['shortfall'], 'returned');
      expect(objects(vm.submitted!['lines']).single['quantity'], 6);
      expect(vm.version, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      await db.close();
    },
  );
}
