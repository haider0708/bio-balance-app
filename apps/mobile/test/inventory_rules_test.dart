import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/tunis_dates.dart';
import 'package:biobalance/domain/models/inventory_rules.dart';
import 'package:biobalance/domain/models/batch_declaration.dart';
import 'package:flutter_test/flutter_test.dart';

Json lot(String id, String expiry, int quantity) => {
  'id': id,
  'productId': 'p',
  'batch': id,
  'expiry': expiry,
  'sellable': quantity,
  'damaged': 0,
  'version': 2,
};
void main() {
  test(
    'Tunisian dates keep civil expiries distinct from timestamp timezones',
    () {
      expect(TunisDates.expiry('02/2028'), '2028-02-29');
      expect(TunisDates.expiry('2029-02'), '2029-02-28');
      expect(TunisDates.expiry('31/12/2029'), '2029-12-31');
      expect(() => TunisDates.expiry('29/02/2029'), throwsFormatException);
      expect(
        TunisDates.dateOnlyLabel('2029-12-31T00:00:00.000Z'),
        '31/12/2029',
      );
      expect(
        TunisDates.timestampLabel('2026-09-21T23:30:00Z'),
        '22/09/2026 00:30',
      );
    },
  );
  test(
    'FEFO prioritizes available valid lots and keeps zero stock selectable',
    () {
      final lots = [
        lot('empty', '2026-09-22', 0),
        lot('available', '2026-10-01', 4),
        lot('expired', '2026-09-20', 5),
        lot('later', '2026-11-01', 8),
      ].map(InventoryLot.fromJson);
      expect(InventorySelection.forSale(lots, '2026-09-21').map((l) => l.id), [
        'available',
        'later',
        'empty',
      ]);
    },
  );
  test(
    'approaching expiry includes day 30 and excludes day 31 and empty lots',
    () {
      StockSummary summary(List<Json> lots) => StockSummary.forProduct(
        StoreData({'lots': lots}),
        'p',
        today: '2026-09-21',
      );
      expect(summary([lot('today', '2026-09-21', 1)]).approaching, isTrue);
      expect(summary([lot('day30', '2026-10-21', 1)]).approaching, isTrue);
      expect(summary([lot('day31', '2026-10-22', 1)]).approaching, isFalse);
      expect(summary([lot('empty', '2026-09-22', 0)]).approaching, isFalse);
      expect(summary([lot('expired', '2026-09-20', 1)]).expired, isTrue);
      expect(summary([lot('short', '2026-09-22', -1)]).discrepancy, isTrue);
      expect(summary([lot('low', '2026-12-22', 5)]).low, isTrue);
    },
  );
  test('batch identity is stable across French and ISO month-only input', () {
    final a = BatchDeclaration.create('store', 'p', ' LOT ', '02/2028');
    final b = BatchDeclaration.create('store', 'p', 'LOT', '2028-02-29');
    expect(a.lotId, b.lotId);
    expect(a.expiry, '2028-02-29');
  });
  test('sale details choose current revisions and retain pending edits', () {
    expect(
      SaleSnapshot.latest({'version': 1}, {'version': 3}, {
        'version': 2,
      })['version'],
      3,
    );
    expect(
      SaleSnapshot.latest(
        {'version': 1},
        {'version': 2, 'syncStatus': 'pending'},
        {'version': 3},
      )['version'],
      2,
    );
  });
}
