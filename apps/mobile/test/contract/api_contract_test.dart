// Runs the app's real repositories against a real API server (see apps/api/test/serve-fixture.ts).
// It proves that what the server sends is what the app parses. Skipped unless CONTRACT_FIXTURE is set.
import 'dart:convert';
import 'dart:io';

import 'package:biobalance/core/api/api_client.dart';
import 'package:biobalance/core/api/api_exception.dart';
import 'package:biobalance/core/api/json.dart';
import 'package:biobalance/core/auth/me.dart';
import 'package:biobalance/core/auth/session.dart';
import 'package:biobalance/features/approvals/approvals_repository.dart';
import 'package:biobalance/features/catalog/catalog_repository.dart';
import 'package:biobalance/features/messages/messages_repository.dart';
import 'package:biobalance/features/network/network_models.dart';
import 'package:biobalance/features/network/network_repository.dart';
import 'package:biobalance/features/notifications/notifications_repository.dart';
import 'package:biobalance/features/reports/reports_repository.dart';
import 'package:biobalance/features/restock/restock_models.dart';
import 'package:biobalance/features/restock/restock_repository.dart';
import 'package:biobalance/features/rewards/rewards_repository.dart';
import 'package:biobalance/features/sales/sales_repository.dart';
import 'package:biobalance/features/stock/stock_models.dart';
import 'package:biobalance/features/stock/stock_repository.dart';
import 'package:biobalance/features/training/training_repository.dart';
import 'package:biobalance/features/wallet/wallet_models.dart';
import 'package:biobalance/features/wallet/wallet_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Json fixture;

ProviderContainer as(String role) {
  final tokens = fixture.obj('tokens');
  final dio = Dio(BaseOptions(baseUrl: fixture.str('baseUrl')));
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWith(
        (ref) => ApiClient(
          dio: dio,
          tokenReader: () => tokens.str(role),
          localeReader: () => 'fr',
          onUnauthorized: () {},
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

String id(String key) => fixture.obj('ids').str(key);

void main() {
  final path = Platform.environment['CONTRACT_FIXTURE'];
  if (path == null) {
    test(
      'API contract (skipped: set CONTRACT_FIXTURE)',
      () {},
      skip: 'needs a running fixture server',
    );
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding blocks real HTTP by default; this test talks to a real local server.
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({});
  setUpAll(() => fixture = jsonDecode(File(path).readAsStringSync()) as Json);

  group('team member', () {
    test('sees their wallet, sales, notifications and training', () async {
      final c = as('vendeur');
      final me = Me.fromJson(
        await c.read(apiClientProvider).get('/v1/me') as Json,
      );
      expect(me.role, Role.vendeur);
      expect(me.pdv?.name, 'Para Lac');
      expect(me.region?.code, 'NORD');

      final wallet = await c.read(walletRepositoryProvider).summary();
      // 2 units at 800 + 1 at 500 = 2100, corrected to 1 unit at 800 + 1 at 500 = 1300; 500 requested for payout.
      expect(wallet.balanceMillimes, 1300);
      expect(wallet.pendingMillimes, 500);
      expect(wallet.availableMillimes, 800);
      expect(wallet.today.sales, 1);

      final entries = await c.read(walletRepositoryProvider).entries();
      expect(entries.entries.map((e) => e.kind), [
        WalletKind.correction,
        WalletKind.sale,
      ]);

      final payouts = await c.read(walletRepositoryProvider).payouts();
      expect(payouts.single.status, PayoutStatus.pending);

      final sales = await c.read(salesRepositoryProvider).list();
      expect(sales.items, hasLength(1));
      final sale = await c.read(salesRepositoryProvider).get(id('sale'));
      expect(sale.version, 2);
      expect(sale.revisions.single.reason, 'Recount');
      expect(
        sale.lines.map((l) => l.name),
        containsAll(['Serum Vitamin C', 'Serum Niacinamide']),
      );
      expect(sale.rewardMillimes, 1300);

      final dashboard =
          await c.read(apiClientProvider).get('/v1/dashboard') as Json;
      expect(
        WalletSummary.fromJson(dashboard.obj('wallet')).balanceMillimes,
        1300,
      );
      expect(dashboard.obj('pdv').str('status'), 'ACTIVE');

      final products = await c.read(catalogRepositoryProvider).products();
      expect(products, hasLength(3));
      expect(products.first.family, isNotEmpty);

      final inbox = await c.read(notificationsRepositoryProvider).page();
      expect(inbox.pinned.single.title, 'Nouveau sérum');
      expect(inbox.items.any((n) => n.isMessage), isTrue);
      expect(
        await c.read(notificationsRepositoryProvider).unread(),
        greaterThan(0),
      );

      final courses = await c.read(trainingRepositoryProvider).courses();
      expect(courses.single.title, 'Vendre les sérums');
      final course = await c
          .read(trainingRepositoryProvider)
          .course(courses.single.id);
      expect(course.lessons.single.title, 'Introduction');
    });

    test('a retried sale is not counted twice', () async {
      final c = as('vendeur');
      final api = c.read(apiClientProvider);
      final body = {
        'id': '22222222-2222-4222-8222-222222222222',
        'lines': [
          // A product with no reward rule, so the shared wallet totals stay as the other tests expect.
          {'productId': id('product3'), 'quantity': 1},
        ],
      };
      final first = Sale2.parse(await api.post('/v1/sales', body) as Json);
      final again = Sale2.parse(await api.post('/v1/sales', body) as Json);
      expect(again.replay, isTrue);
      expect(again.balance, first.balance);
    });
  });

  group('responsable', () {
    test('manages their region', () async {
      final c = as('responsable');
      final network = c.read(networkRepositoryProvider);
      final pdvs = await network.pdvs();
      expect(pdvs.map((p) => p.name), containsAll(['Para Lac', 'Para Marsa']));
      final lac = pdvs.firstWhere((p) => p.name == 'Para Lac');
      expect(lac.status, ItemStatus.active);
      expect(lac.initialStock, 'APPROVED');
      expect(lac.groupName, 'Groupe Tunis');
      expect(
        pdvs.firstWhere((p) => p.name == 'Para Marsa').status,
        ItemStatus.pending,
      );

      final groups = await network.groups();
      expect(groups.single.pdvCount, 1);
      final team = await network.people(role: 'VENDEUR', pdvId: id('pdv'));
      expect(
        team.map((p) => p.name),
        containsAll(['Karim Vendeur', 'Amira Vendeuse']),
      );
      expect(
        team.firstWhere((p) => p.name == 'Karim Vendeur').status,
        ItemStatus.pending,
      );
      expect((await network.depots()).single.name, 'Depot Hedi');

      final stock = await c.read(stockRepositoryProvider).levels(id('pdv'));
      expect(stock.items, hasLength(3));
      final declarations = await c
          .read(stockRepositoryProvider)
          .declarations(locationId: id('pdv'));
      expect(
        declarations.map((d) => d.status),
        containsAll([DeclarationStatus.approved, DeclarationStatus.pending]),
      );
      final waiting = await c
          .read(stockRepositoryProvider)
          .declaration(id('pendingStock'));
      expect(waiting.lines, hasLength(2));
      expect(waiting.location.name, 'Para Lac');

      final restocks = await c.read(restockRepositoryProvider).list();
      expect(
        restocks.map((r) => r.status),
        containsAll([
          RestockStatus.requested,
          RestockStatus.assigned,
          RestockStatus.shipped,
          RestockStatus.completed,
        ]),
      );
      final done = await c
          .read(restockRepositoryProvider)
          .get(id('doneRestock'));
      expect(done.lines.map((l) => l.approved), [5, 5]);
      expect(done.receiver?.name, 'Amira Vendeuse');
      expect(done.receiptPhotoId, isNotNull);
      expect(done.supplier, 'Depot Hedi');

      final dashboard =
          await c.read(apiClientProvider).get('/v1/dashboard') as Json;
      expect(dashboard.obj('sales').obj('today').integer('sales'), 2);
      expect(dashboard.list('trend'), hasLength(14));
      expect(dashboard.obj('approvals').integer('PDV'), 1);

      final report = await c.read(reportsRepositoryProvider).sales((
        from: '2020-01-01',
        to: '2099-01-01',
        groupBy: 'family',
        regionId: null,
        pdvId: null,
        sellerId: null,
        productId: null,
        family: null,
      ));
      expect(report.rows.map((r) => r.label), contains('Sérums'));
      await c.read(reportsRepositoryProvider).attention();
    });

    test('cannot reach the admin inbox or another region', () async {
      final c = as('responsableSud');
      expect(
        c.read(approvalsProvider(null).future),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
      expect(await c.read(networkRepositoryProvider).pdvs(), isEmpty);
      expect(
        c.read(stockRepositoryProvider).levels(id('pdv')),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
    });
  });

  group('grossiste', () {
    test('sees the orders assigned to them and their depot', () async {
      final c = as('grossiste');
      final orders = await c.read(restockRepositoryProvider).list(active: true);
      expect(
        orders.where((o) => o.status == RestockStatus.assigned),
        hasLength(1),
      );
      final stock = await c.read(stockRepositoryProvider).levels(id('depot'));
      // 50/40/30 declared; 5 and 5 left for the completed restock.
      expect(
        {for (final i in stock.items) i.name: i.quantity},
        {'Serum Vitamin C': 45, 'Serum Niacinamide': 35, 'Shampoing Argan': 30},
      );
      final dashboard =
          await c.read(apiClientProvider).get('/v1/dashboard') as Json;
      expect(dashboard.integer('toShip'), 1);
      expect(dashboard.obj('stock').integer('units'), 110);
    });
  });

  group('admin', () {
    test('sees everything that waits for them', () async {
      final c = as('admin');
      final approvals = await c.read(approvalsProvider(null).future);
      expect(approvals.counts[ApprovalType.pdv], 1);
      expect(approvals.counts[ApprovalType.member], 1);
      expect(approvals.counts[ApprovalType.stock], 1);
      expect(approvals.counts[ApprovalType.restockRequest], 1);
      expect(approvals.counts[ApprovalType.payout], 1);
      expect(
        approvals.items.firstWhere((i) => i.type == ApprovalType.pdv).by,
        'Nora Nord',
      );

      final payouts = await c
          .read(walletRepositoryProvider)
          .payouts(status: 'PENDING');
      expect(payouts.single.userName, 'Amira Vendeuse');
      expect(payouts.single.userPdv, 'Para Lac');
      final wallets = await c.read(walletRepositoryProvider).overview();
      expect(wallets.single.balance, 1300);

      final rules = await c.read(rewardsRepositoryProvider).rules('current');
      expect(
        rules.map((r) => r.targetName),
        containsAll(['Sérums', 'Serum Vitamin C']),
      );
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final effective = await c
          .read(rewardsRepositoryProvider)
          .effective(today);
      expect(
        {for (final e in effective) e.name: e.amountMillimes},
        {
          'Serum Vitamin C': 800,
          'Serum Niacinamide': 500,
          'Shampoing Argan': 0,
        },
      );

      final messages = await c.read(messagesRepositoryProvider).list();
      expect(messages.single.title, 'Nouveau sérum');
      final recipients = await c
          .read(messagesRepositoryProvider)
          .recipients(messages.single.id);
      expect(recipients.recipients.single.name, 'Amira Vendeuse');
      final preview = await c
          .read(messagesRepositoryProvider)
          .preview(const Audience(roles: {'RESPONSABLE'}));
      expect(preview.recipients, 2);

      final dashboard =
          await c.read(apiClientProvider).get('/v1/dashboard') as Json;
      expect(dashboard.list('regions'), hasLength(3));
      expect(dashboard.obj('payouts').integer('pending'), 1);

      final progress = await c
          .read(trainingRepositoryProvider)
          .progress(id('course'));
      expect(progress.total, 1);
      expect(
        (await c.read(networkRepositoryProvider).people(role: 'RESPONSABLE'))
            .map((p) => p.name),
        containsAll(['Nora Nord', 'Sami Sud']),
      );
      expect(
        (await c
            .read(catalogRepositoryProvider)
            .products(includeInactive: true)),
        hasLength(3),
      );
      expect(
        (await c.read(networkRepositoryProvider).regions()).map((r) => r.code),
        containsAll(['NORD', 'CENTRE', 'SUD']),
      );
    });
  });
}

/// Just what the idempotency check needs from a sale response.
class Sale2 {
  Sale2(this.replay, this.balance);

  factory Sale2.parse(Json j) =>
      Sale2(j.flag('replay'), j.obj('wallet').integer('balanceMillimes'));

  final bool replay;
  final int balance;
}
