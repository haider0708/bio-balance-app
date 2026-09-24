import 'package:biobalance/data/services/api/generated/models.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/synchronization/sync_summary.dart';
import 'package:biobalance/domain/models/order_workflow.dart';
import 'package:biobalance/domain/models/receipt_plan.dart';
import 'package:biobalance/domain/models/workspace_scope.dart';
import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/features/inventory/inventory_screens.dart';
import 'package:biobalance/ui/features/replenishment/order_creation_screen.dart';
import 'package:biobalance/ui/features/replenishment/scoped_order_screen.dart';
import 'package:biobalance/ui/features/team/team_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_test.dart' show MemoryDraftRepository;
import 'ui_test.dart' show PreviewApi, screenshot;
import 'replenishment_test.dart' as stock;

const orderId = '00000000-0000-4000-8000-000000000001';

class OrderApi extends PreviewApi {
  @override
  Future<DashboardOrderResponseDto> dashboardOrder({
    required String groupId,
    required String storeId,
    required String id,
  }) async => DashboardOrderResponseDto.fromJson({
    'order': {
      'id': id,
      'organizationId': groupId,
      'storeId': storeId,
      'createdBy': 'user',
      'requestedLines': [
        {'productId': 'p', 'quantity': 6},
      ],
      'cancelledLines': [],
      'lines': [
        {'productId': 'p', 'quantity': 6},
      ],
      'status': 'requested',
      'version': 1,
      'createdAt': '2026-09-24T10:00:00Z',
      'storeName': 'Magasin Tunis',
      'groupName': 'Parahouse',
    },
    'deliveries': [],
    'receipts': [],
    'issues': [],
    'problem': null,
    'history': [],
    'fulfillment': [
      {
        'productId': 'p',
        'ordered': 6,
        'received': 0,
        'inTransit': 0,
        'remainingToDispatch': 6,
        'remainingToReceive': 6,
        'cancelled': 0,
      },
    ],
  });
}

class OrderRepository extends MemoryDraftRepository {
  OrderRepository(super.db, super.api);
  final loads = <String>[];
  @override
  Stream<SyncSummary> watchSyncSummary(String account) => const Stream.empty();
  @override
  Future<StoreData?> load(UserAccount user, Store store) async {
    loads.add(store.id);
    return StoreData({
      ...stock.data().raw,
      'permissions': ['manage'],
      'store': store.toJson(),
    });
  }

  @override
  Future<void> synchronize(UserAccount user, Store store) async {}
}

class Fixture {
  final db = AppDatabase(NativeDatabase.memory());
  final api = OrderApi();
  late final repo = OrderRepository(db, api);
  late final vm = WorkspaceViewModel(
    const UserAccount(
      id: 'user',
      name: 'Responsable',
      email: 'test@example.test',
      admin: false,
    ),
    repo,
    api,
  );
  late final stores = [
    for (final entry in [
      ('tunis', 'group', 'Tunis'),
      ('sousse', 'group', 'Sousse'),
      ('bizerte', 'other', 'Bizerte'),
    ])
      Store.fromJson({
        'id': entry.$1,
        'organizationId': entry.$2,
        'organizationName': 'Parahouse',
        'name': entry.$3,
        'permissions': ['manage'],
      }),
  ];
  Fixture() {
    vm.state = WorkspaceState(stores: stores);
    addTearDown(close);
  }
  Widget app(Widget home, {double scale = 1, GlobalKey? capture}) =>
      ChangeNotifierProvider.value(
        value: vm,
        child: MaterialApp(
          theme: appTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: capture, child: child!),
          ),
          home: home,
        ),
      );
  bool closed = false;
  Future<void> close() async {
    if (closed) return;
    closed = true;
    vm.dispose();
    await db.close();
  }
}

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
  test('responsible cancellation closes at preparation; dispatch follows preparation', () {
    OrderWorkflow flow(String status, bool admin) => OrderWorkflow(
      {'status': status},
      [
        {'remainingToDispatch': 6, 'inTransit': 0, 'received': 0},
      ],
      admin: admin,
      manager: true,
    );
    expect(flow('requested', false).canCancel, isTrue);
    expect(flow('preparing', false).canCancel, isFalse);
    expect(flow('dispatched', false).canCancel, isFalse);
    expect(flow('requested', true).canPrepare, isTrue);
    expect(flow('requested', true).canDispatch, isFalse);
    expect(flow('preparing', true).canDispatch, isTrue);
    expect(flow('partial', true).canPrepare, isTrue);
    expect(flow('partial', true).canDispatch, isFalse);
    expect(flow('received', true).canDispatch, isFalse);
  });
  test('reception counts damaged/refused separately and never guesses missing units', () {
    final plan = ReceiptPlan(
      [
        {'productId': 'p', 'quantity': 10},
      ],
      [
        {'productId': 'p', 'quantity': 4},
        {'productId': 'p', 'quantity': 2, 'condition': 'damaged'},
        {'productId': 'p', 'quantity': 1, 'condition': 'refused'},
      ],
    );
    expect(
      [plan.remaining('p'), plan.sellable, plan.damaged, plan.refused],
      [3, 4, 2, 1],
    );
    expect(plan.requiresExplanation, isTrue);
  });
  test('responsible team excludes self but retains colleagues', () async {
    final f = Fixture();
    final vm = GroupTeamViewModel(
      f.vm,
      const PartnerGroup(id: 'group', name: 'Parahouse', canManage: true),
    );
    vm.data = {
      'members': [
        {'id': 'user'},
        {'id': 'colleague'},
      ],
    };
    expect(vm.members.map((m) => m['id']), ['colleague']);
    vm.dispose();
    await f.close();
  });
  testWidgets(
    'group order preserves scope and separate drafts including failed writes',
    (t) async {
      final f = Fixture();
      await f.repo.saveDraft('user', '', 'selection', {'storeId': 'previous'});
      await t.pumpWidget(
        f.app(OrderCreationScreen(parent: f.vm, groupId: 'group')),
      );
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('Bizerte'), findsNothing);
      void select(String id) => t
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged!(id);
      select('tunis');
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(f.vm.state.store, isNull);
      expect(
        (await f.repo.draft('user', '', 'selection'))!['storeId'],
        'previous',
      );
      expect(f.repo.loads, contains('tunis'));
      await t.tap(find.text('Ajouter un produit'));
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await t.tap(find.text('Sérum').last);
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      f.repo.failWrites = true;
      await t.enterText(
        find.widgetWithText(TextField, 'Unités à commander'),
        '7',
      );
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      select('sousse');
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.widgetWithText(TextField, '7'), findsOneWidget);
      expect(f.repo.loads, isNot(contains('sousse')));
      f.repo.failWrites = false;
      select('sousse');
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(
        (await f.repo.draft('user', 'tunis', 'order'))!['values']['p'],
        '7',
      );
      expect(
        find.widgetWithText(TextField, 'Unités à commander'),
        findsNothing,
      );
      select('tunis');
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.widgetWithText(TextField, '7'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(f.close);
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets('responsible order action and layout at scale $scale', (
      t,
    ) async {
      t.view.physicalSize = scale == 1
          ? const Size(360, 800)
          : const Size(800, 360);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = Fixture(), key = GlobalKey();
      await t.pumpWidget(
        f.app(
          ExactOrderScreen(
            parent: f.vm,
            store: f.stores.first,
            orderId: orderId,
          ),
          scale: scale,
          capture: key,
        ),
      );
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await t.scrollUntilVisible(
        find.text('Annuler la commande'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('Mettre en préparation'), findsNothing);
      expect(find.text('Expédier une livraison'), findsNothing);
      expect(find.text('Annuler la commande').hitTestable(), findsOneWidget);
      if (scale == 1) await screenshot(t, key, 'orders-responsible-detail');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(f.close);
    });
  }
  testWidgets(
    'reception starts from product and edits the lot without duplication',
    (t) async {
      final f = Fixture();
      f.vm.state = WorkspaceState(
        store: f.stores.first,
        stores: f.stores,
        data: stock.data(),
      );
      await t.pumpWidget(
        f.app(ReceiptScreen(vm: f.vm, delivery: stock.delivery)),
      );
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await t.tap(find.text('Saisir le lot reçu'));
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.widgetWithText(TextFormField, '6'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Numéro de lot sur l’emballage'),
        'BATCH-A',
      );
      await t.enterText(
        find.widgetWithText(
          TextFormField,
          'Péremption : JJ/MM/AAAA ou MM/AAAA',
        ),
        '12/2028',
      );
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      final draft = await f.repo.draft('user', 'tunis', 'receipt:delivery');
      expect(objects(draft!['lines']).single, containsPair('quantity', 6));
      expect(objects(draft['lines']).single['expiry'], '2028-12-31');
      await t.ensureVisible(find.textContaining('Lot BATCH-A'));
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await t.tap(find.textContaining('Lot BATCH-A'));
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Quantité de ce lot'),
        '4',
      );
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(
        objects(
          (await f.repo.draft('user', 'tunis', 'receipt:delivery'))!['lines'],
        ).single['quantity'],
        4,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(f.close);
    },
  );
}
