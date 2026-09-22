import 'dart:async';

import 'package:biobalance/ui/core/form_draft.dart';
import 'package:biobalance/domain/use_cases/record_return.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:biobalance/data/services/api/session_storage.dart';
import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/money.dart';
import 'package:biobalance/ui/features/sales/sale_view_model.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const actor = UserAccount(
  id: 'audit',
  name: 'Audit',
  email: 'audit@example.test',
  admin: false,
);
final shop = Store.fromJson({
  'id': 'shop',
  'organizationId': 'org',
  'name': 'Audit',
  'permissions': ['manage', 'sell', 'receive'],
});
SaleLine line(String id) => SaleLine(
  id: id,
  productId: 'p',
  quantity: 1,
  price: Money(1000),
  allocations: [
    {'lotId': 'lot', 'quantity': 1},
  ],
);

class ReadbackFaultRepository extends OfflineRepository {
  bool readFailure = false,
      failAfterCommit = false,
      draftFailure = false,
      commitFailure = false;
  Completer<void>? draftGate;
  ReadbackFaultRepository(super.db, super.api);
  @override
  Future<StoreData?> load(UserAccount user, Store store) async {
    if (readFailure) {
      throw const AppFailure('STORAGE_UNAVAILABLE', 'Stockage indisponible');
    }
    return super.load(user, store);
  }

  @override
  Future<Json?> draft(String userId, String storeId, String kind) async {
    await draftGate?.future;
    if (draftFailure) {
      throw const AppFailure('STORAGE_UNAVAILABLE', 'Stockage indisponible');
    }
    return super.draft(userId, storeId, kind);
  }

  @override
  Future<void> enqueue(
    UserAccount user,
    Store store,
    Json operation,
    Json effect, {
    String? draftKey,
    List<String> supersedes = const [],
  }) async {
    if (commitFailure) throw const AppFailure('STORAGE_FULL', 'Stockage plein');
    await super.enqueue(
      user,
      store,
      operation,
      effect,
      draftKey: draftKey,
      supersedes: supersedes,
    );
    if (failAfterCommit) readFailure = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ApiClient api;
  late ReadbackFaultRepository repository;
  late WorkspaceViewModel workspace;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = ApiClient(baseUrl: 'http://unused')
      ..authenticate('token', accountId: actor.id);
    repository = ReadbackFaultRepository(db, api);
    workspace = WorkspaceViewModel(actor, repository, api);
    workspace.state = WorkspaceState(
      store: shop,
      stores: [shop],
      data: StoreData({}),
    );
    workspace.setForeground(false);
  });
  tearDown(() async {
    workspace.dispose();
    api.http.close();
    await db.close();
  });

  test('sale remains successful when committed data cannot refresh; repeated save cannot duplicate it', () async {
    final editor = SaleViewModel(workspace);
    addTearDown(editor.dispose);
    await editor.restore();
    await editor.put(line('one'));
    repository.failAfterCommit = true;
    expect(await editor.save(''), isTrue);
    expect(await editor.save(''), isTrue);
    expect(await repository.pendingCount(actor.id), 1);
    expect(await repository.draft(actor.id, shop.id, 'sale'), isNull);
    expect(workspace.state.error, contains('enregistrée'));
  });

  test(
    'stock receipt acknowledges its durable commit even when refresh fails',
    () async {
      repository.failAfterCommit = true;
      await expectLater(
        workspace.queue({
          'type': 'stock.receive',
          'reason': 'receipt',
          'lines': [
            {
              'productId': 'p',
              'batch': 'B1',
              'expiry': '2030-12-31',
              'quantity': 4,
            },
          ],
        }, draftKey: 'receipt:stock'),
        completes,
      );
      expect(await repository.pendingCount(actor.id), 1);
      expect(workspace.state.error, contains('enregistrée'));
    },
  );

  test(
    'concurrent line removals do not resurrect another removed line',
    () async {
      final editor = SaleViewModel(workspace);
      addTearDown(editor.dispose);
      await editor.restore();
      await editor.put(line('one'));
      await editor.put(line('two'));
      await Future.wait([editor.remove('one'), editor.remove('two')]);
      expect(editor.state.lines, isEmpty);
      expect(
        (await repository.draft(actor.id, shop.id, 'sale'))?['lines'],
        isEmpty,
      );
    },
  );
  test('save waits for pending draft writes and concurrent submission has one effect', () async {
    final editor = SaleViewModel(workspace);
    addTearDown(editor.dispose);
    await editor.restore();
    final editing = editor.put(line('one'));
    final saving = editor.save('');
    final repeated = editor.save('');
    await workspace.flushDrafts();
    expect(await editing, isTrue);
    expect(await saving, isTrue);
    expect(await repeated, isTrue);
    expect(await repository.pendingCount(actor.id), 1);
    expect(await repository.draft(actor.id, shop.id, 'sale'), isNull);
  });

  test('failed durable commit keeps the draft and permits recovery', () async {
    final editor = SaleViewModel(workspace);
    addTearDown(editor.dispose);
    await editor.restore();
    await editor.put(line('one'));
    repository.commitFailure = true;
    expect(await editor.save(''), isFalse);
    expect(editor.canEdit, isTrue);
    expect(await repository.pendingCount(actor.id), 0);
    expect(
      (await repository.draft(actor.id, shop.id, 'sale'))?['lines'],
      hasLength(1),
    );
    repository.commitFailure = false;
    expect(await editor.save(''), isTrue);
    expect(await repository.pendingCount(actor.id), 1);
  });

  test(
    'restoration blocks editing and failed restoration retains the saved draft',
    () async {
      await repository.saveDraft(actor.id, shop.id, 'sale', {
        'lines': [line('saved').toJson()],
      });
      final editor = SaleViewModel(workspace);
      addTearDown(editor.dispose);
      repository.draftGate = Completer<void>();
      final restoring = editor.restore();
      expect(await editor.put(line('too-early')), isFalse);
      repository.draftFailure = true;
      repository.draftGate!.complete();
      await restoring;
      expect(editor.state.restoring, isFalse);
      expect(editor.state.error, isNotNull);
      expect(editor.canEdit, isFalse);
      await workspace.flushDrafts();
      repository.draftFailure = false;
      await editor.restore();
      expect(editor.state.lines.single.id, 'saved');
      expect(editor.canEdit, isTrue);
    },
  );

  test(
    'local startup and store read failures leave a recoverable state',
    () async {
      repository.draftFailure = true;
      await expectLater(workspace.initialize(), completes);
      expect(workspace.state.loading, isFalse);
      expect(workspace.state.error, isNotNull);
      repository.draftFailure = false;
      repository.readFailure = true;
      await workspace.select(shop, refresh: false);
      expect(workspace.state.loading, isFalse);
      expect(workspace.state.data, isNull);
      expect(workspace.state.error, isNotNull);
      repository.readFailure = false;
      await workspace.select(shop, refresh: false);
      expect(workspace.state.error, isNull);
    },
  );

  test('iOS uses a distinct device-only namespace and discards legacy credentials without deleting pending work', () async {
    final options = SessionStorage.secure.iOptions;
    expect(options.accessibility, KeychainAccessibility.unlocked_this_device);
    expect(options.synchronizable, isFalse);
    expect(options.accountName, isNot(const IOSOptions().accountName));
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    FlutterSecureStorage.setMockInitialValues({
      'session': 'legacy',
      'other': 'keep',
    });
    await repository.saveDraft(actor.id, shop.id, 'sale', {
      'lines': [line('saved').toJson()],
    });
    await SessionStorage.prepare();
    expect(await const FlutterSecureStorage().read(key: 'session'), isNull);
    expect(await const FlutterSecureStorage().read(key: 'other'), 'keep');
    expect(
      (await repository.draft(actor.id, shop.id, 'sale'))?['lines'],
      hasLength(1),
    );
  });
  test('lot drafts stay separate and a committed adjustment cannot be restored by an exit guard', () async {
    final first = FormDraftController(
      workspace,
      shop,
      'stock:damage:lot-a',
      {},
    );
    final second = FormDraftController(
      workspace,
      shop,
      'stock:damage:lot-b',
      {},
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.change({'quantity': '2', 'reason': 'Lot A'});
    await second.change({'quantity': '1', 'reason': 'Lot B'});
    await first.beginSubmission();
    await workspace.queue(
      {
        'type': 'stock.damage',
        'lotId': 'lot-a',
        'quantity': 2,
        'reason': 'Lot A',
      },
      expectedVersion: 1,
      draftKey: first.key,
    );
    // Simulates a lifecycle/access guard after durable commit and before the
    // widget receives success or clears its form controller.
    await workspace.flushDrafts();
    expect(await repository.draft(actor.id, shop.id, first.key), isNull);
    expect(
      (await second.restore())?['reason'],
      isNull,
    ); // Already edited; no overwrite.
    expect(
      (await repository.draft(
        actor.id,
        shop.id,
        second.key,
      ))?['values']['reason'],
      'Lot B',
    );
    expect(await repository.pendingCount(actor.id), 1);
  });

  test(
    'return and its form draft complete in the same outbox transaction',
    () async {
      final sale = {
        'id': 'original',
        'sellerId': actor.id,
        'version': 1,
        'occurredAt': '2026-09-22T08:00:00Z',
        'lines': [line('one').toJson()],
        'returned': <String, dynamic>{},
      };
      await repository.saveDraft(actor.id, shop.id, 'return:original', {
        'quantity': '1',
      });
      await RecordReturn(repository).execute(
        actor,
        shop,
        sale,
        lineId: 'one',
        lotId: 'lot',
        quantity: 1,
        sellable: true,
        reason: 'Retour',
        draftKey: 'return:original',
      );
      expect(
        await repository.draft(actor.id, shop.id, 'return:original'),
        isNull,
      );
      expect(await repository.pendingCount(actor.id), 1);
    },
  );
}
