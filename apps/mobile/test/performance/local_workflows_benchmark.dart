// Explicit benchmark, excluded from the normal *_test.dart discovery.
import 'dart:convert';
import 'dart:io';

import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/money.dart';
import 'package:biobalance/domain/use_cases/record_sale.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, num> summary(List<double> values) {
  values.sort();
  return {
    'samples': values.length,
    'p50Ms': values[(values.length * .5).ceil() - 1],
    'p95Ms': values[(values.length * .95).ceil() - 1],
    'maxMs': values.last,
  };
}

void main() {
  test(
    'measure cached loading, search and durable local sale writes',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'biobalance-benchmark-',
      );
      final file = File('${folder.path}/data.sqlite');
      AppDatabase open() => AppDatabase(
        NativeDatabase.createInBackground(
          file,
          setup: (db) {
            db.execute('PRAGMA journal_mode=WAL');
          },
        ),
      );
      var db = open();
      final api = ApiClient(baseUrl: 'http://unused')
        ..authenticate('synthetic', accountId: 'bench');
      const user = UserAccount(
        id: 'bench',
        name: 'Benchmark',
        email: 'benchmark@example.test',
        admin: false,
      );
      final stores = List.generate(
        4,
        (s) => Store.fromJson({
          'id': 'store-$s',
          'organizationId': 'org',
          'name': 'Store $s',
          'permissions': ['manage', 'sell'],
        }),
      );
      final entries = <CacheEntriesCompanion>[];
      void cache(Store store, String resource, String id, Json value) =>
          entries.add(
            CacheEntriesCompanion.insert(
              accountId: user.id,
              storeId: store.id,
              resource: resource,
              entityId: id,
              payload: jsonEncode(value),
            ),
          );
      for (final store in stores) {
        for (var p = 0; p < 200; p++) {
          cache(store, 'products', 'p$p', {
            'id': 'p$p',
            'name': 'Sérum synthétique $p',
            'reference': 'PDRN-$p',
            'barcode': '619$p',
          });
          cache(store, 'config', 'c$p', {
            'id': 'c$p',
            'productId': 'p$p',
            'priceMillimes': '49900',
            'pointsPerUnit': 10,
            'pointsConfigured': true,
            'threshold': 5,
          });
          for (var lot = 0; lot < 3; lot++) {
            cache(store, 'lots', 'l$p-$lot', {
              'id': 'l$p-$lot',
              'productId': 'p$p',
              'batch': 'B$lot',
              'expiry': '2030-12-31',
              'sellable': 1000,
              'version': 2,
            });
          }
        }
        for (var n = 0; n < 100; n++) {
          cache(store, 'sales', 's$n', {
            'id': 's$n',
            'sellerId': user.id,
            'version': 1,
            'occurredAt': '2026-09-01T10:00:00Z',
            'totalMillimes': '49900',
            'earnedPoints': '10',
            'lines': [],
          });
        }
      }
      await db.batch((b) => b.insertAll(db.cacheEntries, entries));
      var repo = OfflineRepository(db, api);
      final save = <double>[],
          load = <double>[],
          search = <double>[],
          reopen = <double>[];
      for (var n = 0; n < 120; n++) {
        final clock = Stopwatch()..start();
        await RecordSale(repo).execute(user, stores.first, [
          SaleLine(
            id: 'new$n',
            productId: 'p0',
            quantity: 1,
            price: Money(49900),
            allocations: [
              {'lotId': 'l0-0', 'quantity': 1},
            ],
          ),
        ]);
        save.add(clock.elapsedMicroseconds / 1000);
      }
      expect(await repo.pendingCount(user.id), 120);
      for (var n = 0; n < 100; n++) {
        final clock = Stopwatch()..start();
        final data = (await repo.load(user, stores[n % 4]))!;
        load.add(clock.elapsedMicroseconds / 1000);
        final products = data.products;
        clock.reset();
        final matches = products
            .where(
              (p) => '${p.name} ${p.reference} ${p.barcode}'
                  .toLowerCase()
                  .contains('pdrn-1'),
            )
            .toList();
        search.add(clock.elapsedMicroseconds / 1000);
        expect(matches, isNotEmpty);
      }
      for (var n = 0; n < 30; n++) {
        await db.close();
        final clock = Stopwatch()..start();
        db = open();
        repo = OfflineRepository(db, api);
        expect((await repo.load(user, stores.first))!.lots.length, 600);
        reopen.add(clock.elapsedMicroseconds / 1000);
      }
      final report = {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'runtime': Platform.version,
        'os': Platform.operatingSystem,
        'physicalReferenceDevice': false,
        'mode': 'host Flutter test VM; not release or cold app startup',
        'fixture': {
          'cachedStores': 4,
          'productsPerStore': 200,
          'lotsPerStore': 600,
          'recentSalesPerStore': 100,
          'pendingSales': 120,
        },
        'localSalePersistence': summary(save),
        'cachedStoreLoadAndSwitch': summary(load),
        'cachedProductSearch': summary(search),
        'sqliteReopenAndLoad': summary(reopen),
      };
      final result = File(
        Platform.environment['BENCHMARK_OUTPUT'] ??
            'build/local-benchmark.json',
      );
      await result.parent.create(recursive: true);
      await result.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );
      // Measurements are recorded, not misrepresented as physical-device release gates.
      // ignore: avoid_print -- machine-readable benchmark output.
      print(jsonEncode(report));
      await db.close();
      await folder.delete(recursive: true);
    },
  );
}
