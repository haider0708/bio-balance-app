import 'pick_date.dart';

import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/delivery_ticket.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/features/inventory/inventory_screens.dart';
import 'package:biobalance/ui/features/replenishment/declared_dispatch_screen.dart';
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
final store = Store.fromJson({
  'id': 'store',
  'organizationId': 'org',
  'name': 'Pharmacie Tunis',
  'permissions': ['manage', 'receive'],
});
const deliveryId = '3f2b8c1e-0b5a-4d0e-9a55-2d1d9c6f7a10';
const code = 'AbCdEfGhIjKlMnOpQrStUv';
final delivery = <String, dynamic>{
  'id': deliveryId,
  'ticketNumber': 'BL-2026-000123',
  'version': 2,
  'lines': [
    {
      'productId': 'p',
      'quantity': 10,
      'allocations': [
        {'batch': 'A1', 'expiry': '2030-05-31', 'quantity': 6},
        {'batch': 'B2', 'expiry': '2031-01-31', 'quantity': 4},
      ],
    },
  ],
};

class RecordingWorkspace extends WorkspaceViewModel {
  RecordingWorkspace(super.user, super.repository, super.api);
  Json? submitted;
  @override
  Future<void> queue(
    Json command, {
    int? expectedVersion,
    Json effect = const {},
    Store? targetStore,
    String? draftKey,
  }) async {
    submitted = command;
    if (draftKey != null) {
      await repository.saveDraft(user.id, targetStore!.id, draftKey, {});
    }
  }
}

Future<RecordingWorkspace> pump(
  WidgetTester tester, {
  String? scannedCode,
}) async {
  final db = AppDatabase(NativeDatabase.memory()),
      api = ApiClient(baseUrl: 'http://test')
        ..authenticate('token', accountId: user.id);
  final vm = RecordingWorkspace(user, MemoryDraftRepository(db, api), api);
  vm.state = WorkspaceState(
    store: store,
    stores: [store],
    data: StoreData({
      'products': [
        {'id': 'p', 'reference': 'SERUM', 'name': 'Sérum', 'active': true},
      ],
      'deliveries': [delivery],
    }),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: vm,
      child: MaterialApp(
        home: ReceiptScreen(
          vm: vm,
          delivery: delivery,
          scannedCode: scannedCode,
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
  return vm;
}

void main() {
  test('only a BioBalance delivery QR is understood', () {
    final scan = TicketScan.parse('BB1.$deliveryId.$code');
    expect(scan?.deliveryId, deliveryId);
    expect(scan?.code, code);
    expect(
      TicketScan.parse('  BB1.${deliveryId.toUpperCase()}.$code ')?.deliveryId,
      deliveryId,
    );
    for (final bad in [
      '',
      '3760123456789',
      'BB2.$deliveryId.$code',
      'BB1.not-a-uuid.$code',
      'BB1.$deliveryId.short',
      'BB1.$deliveryId.$code.extra',
    ]) {
      expect(TicketScan.parse(bad), isNull, reason: bad);
    }
  });

  testWidgets(
    'a scanned parcel shows the ticket read-only and sends only the QR code',
    (tester) async {
      final vm = await pump(tester, scannedCode: code);
      expect(find.text('Bon BL-2026-000123 vérifié'), findsOneWidget);
      // The ticket is the truth: its lots are shown, nothing to type.
      expect(find.textContaining('6 × lot A1'), findsOneWidget);
      expect(find.textContaining('4 × lot B2'), findsOneWidget);
      expect(find.text('Saisir le lot reçu'), findsNothing);
      await tester.ensureVisible(find.text('Confirmer la réception'));
      await tester.tap(find.text('Confirmer la réception'));
      await tester.pumpAndSettle();
      expect(vm.submitted!['type'], 'delivery.receive');
      expect(vm.submitted!['ticketCode'], code);
      expect(vm.submitted!.containsKey('manualReason'), isFalse);
      expect(objects(vm.submitted!['lines']), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'without a scan the receiver says why, and BioBalance validates the claim',
    (tester) async {
      final vm = await pump(tester);
      expect(find.text('Scanner le QR du bon BL-2026-000123'), findsOneWidget);
      await tester.tap(find.text('Je ne peux pas scanner'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'BioBalance comparera avec ce qui a été expédié, puis validera. Le stock n’augmente qu’à ce moment.',
        ),
        findsOneWidget,
      );
      // Nothing is pre-filled without the scan: the receiver enters what he counts.
      expect(find.textContaining('Lot A1'), findsNothing);
      expect(find.text('Envoyer à BioBalance pour validation'), findsOneWidget);
      expect(vm.submitted, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'BioBalance declares the lots of a shipment before the ticket exists',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory()),
          api = ApiClient(baseUrl: 'http://test')
            ..authenticate('token', accountId: user.id);
      final vm = RecordingWorkspace(user, MemoryDraftRepository(db, api), api);
      vm.state = WorkspaceState(
        store: store,
        stores: [store],
        data: StoreData({
          'products': [
            {'id': 'p', 'reference': 'SERUM', 'name': 'Sérum', 'active': true},
          ],
        }),
      );
      final sent = <Json>[];
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            home: DeclaredDispatchScreen(
              parent: vm,
              destination: store,
              order: {'id': 'order', 'version': 3},
              lines: [
                {'productId': 'p', 'remainingToDispatch': 8},
              ],
              submit: (command, version) async {
                expect(version, 3);
                sent.add(command);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      // Lot, expiry, quantity (pre-filled with what remains to ship).
      expect(fields, findsNWidgets(3));
      expect(tester.widget<TextField>(fields.at(2)).controller!.text, '8');
      await tester.tap(find.text('Confirmer et créer le bon'));
      await tester.pumpAndSettle();
      expect(find.textContaining('numéro de lot'), findsOneWidget);
      await tester.enterText(fields.at(0), 'L-42');
      await pickDate(tester, fields.at(1), '01/01/2020');
      await tester.tap(find.text('Confirmer et créer le bon'));
      await tester.pumpAndSettle();
      expect(find.textContaining('est périmé'), findsOneWidget);
      await pickDate(tester, fields.at(1), '31/12/2099');
      await tester.tap(find.text('Confirmer et créer le bon'));
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(sent.single['type'], 'delivery.dispatch');
      expect(sent.single['deliveryId'], isNotEmpty);
      expect(sent.single['lines'], [
        {
          'productId': 'p',
          'quantity': 8,
          'allocations': [
            {'batch': 'L-42', 'expiry': '2099-12-31', 'quantity': 8},
          ],
        },
      ]);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      await db.close();
    },
  );
}
