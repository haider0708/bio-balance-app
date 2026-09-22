import 'dart:async';

import 'package:biobalance/data/repositories/notifications_repository.dart';
import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/repositories/repository_context.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/features/catalog/catalog_screen.dart';
import 'package:biobalance/ui/features/inventory/inventory_screens.dart';
import 'package:biobalance/ui/features/inventory/stock_view_model.dart';
import 'package:biobalance/ui/features/notifications/notifications_view_model.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ControlledInbox extends NotificationsRepository {
  ControlledInbox(super.context);
  int calls = 0;
  Object? failure;
  Completer<List<Json>>? pending;
  @override
  Future<List<Json>> list({String? before}) async {
    calls++;
    if (failure != null) throw failure!;
    return pending?.future ??
        [
          {'id': 'one', 'title': 'Stock', 'readAt': null},
        ];
  }
}

class CountedSync extends OfflineRepository {
  int calls = 0;
  CountedSync(super.db, super.api);
  @override
  Future<void> synchronize(UserAccount user, Store store) async {
    calls++;
  }
}

Future<void> indexReady(WidgetTester t, StockViewModel stock) async {
  // Real isolate messages must arrive before pumping the widget fake clock.
  for (var i = 0; i < 100 && stock.loading; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump();
  }
  expect(stock.loading, isFalse);
  expect(stock.error, isNull);
}

void main() {
  test(
    'catalog matching keeps leading zeros, UPC equivalence and active scope',
    () {
      final data = StoreData({
        'products': [
          {
            'id': 'ean',
            'name': 'Sérum',
            'reference': 'REF-A',
            'barcode': '0012345678905',
          },
          {
            'id': 'off',
            'name': 'Archivé',
            'reference': 'OLD',
            'barcode': '619123',
            'active': false,
          },
        ],
      });
      expect(data.productForBarcode('012345678905')?.id, 'ean');
      expect(data.productForBarcode('0012345678905')?.id, 'ean');
      expect(data.productForBarcode('619123'), isNull);
      expect(data.productForBarcode('012345678906'), isNull);
      expect(data.products.first.matches('ref-a'), isTrue);
    },
  );

  testWidgets(
    'inbox is idle off-screen, avoids overlap and unchanged rebuilds',
    (t) async {
      final api = ApiClient(baseUrl: 'http://unused');
      final repo = ControlledInbox(RepositoryContext(api));
      final vm = NotificationsViewModel(repo);
      var changes = 0;
      vm.addListener(() => changes++);
      await t.pump(const Duration(minutes: 1));
      expect(repo.calls, 0);
      vm.setActive(true);
      await t.pump();
      expect(changes, 1);
      await t.pump(const Duration(seconds: 4));
      expect(repo.calls, 2);
      expect(changes, 1);
      repo.pending = Completer();
      await t.pump(const Duration(seconds: 4));
      await t.pump(const Duration(minutes: 1));
      expect(repo.calls, 3);
      vm.setActive(false);
      repo.pending!.complete([]);
      await t.pump();
      await t.pump(const Duration(minutes: 1));
      expect(repo.calls, 3);
      vm.dispose();
      api.http.close();
    },
  );

  testWidgets(
    'offline inbox backs off and confirmed access loss stops polling',
    (t) async {
      final api = ApiClient(baseUrl: 'http://unused');
      final repo = ControlledInbox(RepositoryContext(api))
        ..failure = Exception('offline');
      final vm = NotificationsViewModel(repo)..setActive(true);
      await t.pump();
      expect(repo.calls, 1);
      await t.pump(const Duration(seconds: 4));
      expect(repo.calls, 1);
      await t.pump(const Duration(seconds: 4));
      expect(repo.calls, 2);
      final request = RequestOptions(path: '/notifications');
      repo.failure = DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 401),
      );
      await t.pump(const Duration(seconds: 16));
      expect(repo.calls, 3);
      await t.pump(const Duration(minutes: 5));
      expect(repo.calls, 3);
      vm.dispose();
      api.http.close();
    },
  );

  testWidgets('workspace scheduling stops in background and after disposal', (
    t,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final api = ApiClient(baseUrl: 'http://unused')
      ..authenticate('token', accountId: 'u');
    final repo = CountedSync(db, api);
    final vm = WorkspaceViewModel(
      const UserAccount(
        id: 'u',
        name: 'Test',
        email: 'test@example.test',
        admin: false,
      ),
      repo,
      api,
    );
    vm.state = WorkspaceState(
      store: Store.fromJson({
        'id': 's',
        'organizationId': 'o',
        'name': 'Store',
      }),
    );
    vm.setForeground(false);
    await t.pump(const Duration(minutes: 2));
    await vm.synchronize();
    expect(repo.calls, 0);
    vm.setForeground(true);
    await t.runAsync(() async {
      for (var i = 0; i < 100 && vm.state.syncing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    expect(repo.calls, 1);
    expect(vm.state.syncing, isFalse);
    vm.setForeground(false);
    await t.pump(const Duration(minutes: 2));
    expect(repo.calls, 1);
    vm.dispose();
    vm.setForeground(true);
    await t.pump(const Duration(minutes: 2));
    expect(repo.calls, 1);
    await t.runAsync(db.close);
    api.http.close();
  });

  test(
    'large stock indexing keeps the latest store and tolerates disposal',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final api = ApiClient(baseUrl: 'http://unused');
      final vm = WorkspaceViewModel(
        const UserAccount(
          id: 'u',
          name: 'Test',
          email: 'test@example.test',
          admin: true,
        ),
        OfflineRepository(db, api),
        api,
      );
      final large = StoreData({
        'products': [
          for (var i = 0; i < 2000; i++)
            {'id': 'old$i', 'name': 'Old', 'reference': '$i'},
        ],
      });
      vm.state = WorkspaceState(data: large);
      final stock = StockViewModel(vm);
      expect(stock.loading, isTrue);
      vm.state = WorkspaceState(
        data: StoreData({
          'products': [
            {'id': 'new', 'name': 'New store', 'reference': 'NEW'},
          ],
        }),
      );
      stock.refresh();
      expect(stock.rows, isEmpty);
      await stock.prepared;
      expect(stock.rows.single.product.id, 'new');
      expect(stock.loading, isFalse);
      vm.state = WorkspaceState(data: large);
      stock.refresh();
      stock.dispose();
      await stock.prepared;
      vm.dispose();
      api.http.close();
      await db.close();
    },
  );

  for (final catalog in [false, true]) {
    testWidgets(
      '${catalog ? 'catalog' : 'stock'} builds a bounded number of cards for 2000 products',
      (t) async {
        final db = AppDatabase(NativeDatabase.memory());
        final api = ApiClient(baseUrl: 'http://unused');
        final vm = WorkspaceViewModel(
          const UserAccount(
            id: 'u',
            name: 'Test',
            email: 'test@example.test',
            admin: true,
          ),
          OfflineRepository(db, api),
          api,
        );
        vm.state = WorkspaceState(
          data: StoreData({
            'products': [
              for (var i = 0; i < 2000; i++)
                {
                  'id': 'p$i',
                  'name': 'Produit $i',
                  'reference': 'REF-$i',
                  'active': true,
                },
            ],
          }),
        );
        final stock = StockViewModel(vm);
        await indexReady(t, stock);
        final first = stock.rows.first;
        stock.search('ref-1');
        stock.search('');
        expect(identical(stock.rows.first, first), isTrue);
        await t.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: catalog ? CatalogPage(vm: vm) : StockPage(vm: vm),
            ),
          ),
        );
        if (!catalog) {
          final builder = t
              .widgetList<ListenableBuilder>(find.byType(ListenableBuilder))
              .firstWhere((b) => b.listenable is StockViewModel);
          await indexReady(t, builder.listenable as StockViewModel);
          await t.pump();
        }
        expect(find.byType(Card).evaluate().length, greaterThan(0));
        expect(find.byType(Card).evaluate().length, lessThan(20));
        expect(find.text('Produit 1999'), findsNothing);
        await t.drag(find.byType(Scrollable).first, const Offset(0, -1600));
        await t.pumpAndSettle();
        expect(find.byType(Card).evaluate().length, lessThan(25));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        stock.dispose();
        vm.dispose();
        await db.close();
        api.http.close();
      },
    );
  }
}
