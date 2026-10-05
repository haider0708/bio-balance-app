import 'ui_test.dart' show screenshot;

import 'package:biobalance/ui/core/design.dart';
import 'package:flutter/services.dart';
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

final capture = GlobalKey();
void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });
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
          child: RepaintBoundary(
            key: capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: appTheme(),
              home: ReceptionValidationScreen(vm: vm, delivery: delivery),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Réception sans scan'), findsOneWidget);
      expect(find.textContaining('Pas de caméra'), findsOneWidget);
      // Lot by lot: shipped 10, the store claims 6; BioBalance retains one figure.
      expect(
        find.textContaining('Expédié par le grossiste : 10'),
        findsOneWidget,
      );
      expect(find.textContaining('Déclaré par le magasin : 6'), findsOneWidget);
      final total = find.byKey(const ValueKey('validate.total.p.A1'));
      expect(tester.widget<TextField>(total).controller!.text, '6');
      await screenshot(tester, capture, 'reception-arbitration');
      // The store lied: 9 really arrived.
      await tester.enterText(total, '9');
      await tester.enterText(
        find.byKey(const ValueKey('validate.damaged.p.A1')),
        '1',
      );
      await tester.enterText(
        find.byType(TextField).last,
        'Vérifié avec le dépôt',
      );
      // Who caused the gap must be stated.
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Valider la réception'),
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Valider la réception'),
      );
      await tester.pumpAndSettle();
      expect(vm.submitted, isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('validate.responsibility.store')),
      );
      await tester.tap(
        find.byKey(const ValueKey('validate.responsibility.store')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Valider la réception'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
      await tester.pumpAndSettle();
      expect(vm.submitted!['type'], 'delivery.validate');
      expect(vm.submitted!['deliveryId'], 'delivery');
      expect(vm.submitted!['responsibility'], 'store');
      expect(objects(vm.submitted!['lines']), [
        {
          'productId': 'p',
          'batch': 'A1',
          'expiry': '2030-05-31',
          'quantity': 8,
          'condition': 'sellable',
        },
        {
          'productId': 'p',
          'batch': 'A1',
          'expiry': '2030-05-31',
          'quantity': 1,
          'condition': 'damaged',
        },
      ]);
      expect(vm.version, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      await db.close();
    },
  );
}
