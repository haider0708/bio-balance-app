// Explicit host benchmark; native frame times and camera latency are separate gates.
import 'dart:convert';
import 'dart:io';

import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/inventory_rules.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/features/inventory/stock_view_model.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'local_workflows_benchmark.dart' show summary;

void main() {
  test(
    'compare stock filtering against the previous screen calculation',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final api = ApiClient(baseUrl: 'http://unused');
      final workspace = WorkspaceViewModel(
        const UserAccount(
          id: 'bench',
          name: 'Benchmark',
          email: 'test@example.test',
          admin: true,
        ),
        OfflineRepository(db, api),
        api,
      );
      final data = StoreData({
        'products': [
          for (var i = 0; i < 2000; i++)
            {
              'id': 'p$i',
              'name': 'Sérum synthétique $i',
              'reference': 'PDRN-$i',
              'barcode': '619$i',
            },
        ],
        'lots': [
          for (var p = 0; p < 2000; p++)
            for (var l = 0; l < 3; l++)
              {
                'id': 'l$p-$l',
                'productId': 'p$p',
                'batch': 'B$l',
                'expiry': '2030-12-31',
                'sellable': p % 10,
                'version': 2,
              },
        ],
      });
      workspace.state = WorkspaceState(data: data);
      final clock = Stopwatch()..start();
      final stock = StockViewModel(workspace);
      await stock.prepared;
      final initialization = clock.elapsedMicroseconds / 1000;
      final previous = <double>[], current = <double>[];
      for (var i = 0; i < 120; i++) {
        final query = [
          'pdrn-1',
          '6192',
          'sérum',
          'absent',
          'pdrn-19',
          '',
        ][i % 6];
        clock.reset();
        final old = data.products
            .where(
              (p) =>
                  '${p.name} ${p.reference} ${p.barcode}'
                      .toLowerCase()
                      .contains(query) &&
                  StockSummary.forProduct(data, p.id).matches('all'),
            )
            .toList();
        // The old widget also calculated every visible and off-screen card summary.
        for (final p in old) {
          StockSummary.forProduct(data, p.id);
        }
        previous.add(clock.elapsedMicroseconds / 1000);
        clock.reset();
        stock.search(query);
        current.add(clock.elapsedMicroseconds / 1000);
        expect(stock.rows.map((r) => r.product.id), old.map((p) => p.id));
      }
      final report = {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'runtime': Platform.version,
        'mode': 'Linux Flutter test VM; calculation only, excludes widget layout/raster and native camera',
        'physicalReferenceDevice': false,
        'fixture': {'products': 2000, 'lots': 6000, 'queries': 120},
        'initialStockIndexWallMs': initialization,
        'initialStockIndexOffUiThread': true,
        'previousStockFilterAndCardSummaries': summary(previous),
        'cachedStockFilter': summary(current),
      };
      final result = File(
        Platform.environment['BENCHMARK_OUTPUT'] ??
            'build/catalog-benchmark.json',
      );
      await result.parent.create(recursive: true);
      await result.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );
      // ignore: avoid_print -- machine-readable benchmark output.
      print(jsonEncode(report));
      stock.dispose();
      workspace.dispose();
      api.http.close();
      await db.close();
    },
  );
}
