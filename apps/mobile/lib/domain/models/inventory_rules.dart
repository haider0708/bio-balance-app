import 'models.dart';
import 'tunis_dates.dart';

class InventorySelection {
  static List<InventoryLot> forSale(
    Iterable<InventoryLot> lots,
    String saleDate, {
    Set<String> retainedLotIds = const {},
  }) {
    final valid = lots
        .where(
          (l) =>
              retainedLotIds.contains(l.id) ||
              (l.sellable > 0 && !l.expiredOn(saleDate)),
        )
        .toList();
    valid.sort((a, b) {
      final available = (a.sellable > 0 ? 0 : 1).compareTo(
        b.sellable > 0 ? 0 : 1,
      );
      if (available != 0) return available;
      final expiry = a.expiry.compareTo(b.expiry);
      return expiry != 0 ? expiry : a.id.compareTo(b.id);
    });
    return valid;
  }

  static List<InventoryLot> inStock(Iterable<InventoryLot> lots) =>
      lots.where((lot) => lot.sellable != 0 || lot.damaged > 0).toList()
        ..sort((a, b) => a.expiry.compareTo(b.expiry));
}

class StockSummary {
  final int available, threshold;
  final bool discrepancy, approaching, expired;
  const StockSummary(
    this.available,
    this.threshold,
    this.discrepancy,
    this.approaching,
    this.expired,
  );
  bool get low => available <= threshold;
  factory StockSummary.forProduct(
    StoreData data,
    String product, {
    String? today,
  }) {
    final date = today ?? TunisDates.today(),
        lots = data.lotsByProduct[product] ?? [];
    return StockSummary(
      lots
          .where((l) => !l.expiredOn(date))
          .fold(0, (n, l) => n + (l.sellable > 0 ? l.sellable : 0)),
      data.config(product)['threshold'] == null
          ? 5
          : integer(data.config(product)['threshold']),
      lots.any((l) => l.sellable < 0),
      lots.any((l) => l.sellable > 0 && l.approachingOn(date)),
      lots.any((l) => (l.sellable > 0 || l.damaged > 0) && l.expiredOn(date)),
    );
  }
  bool matches(String filter) => switch (filter) {
    'low' => low,
    'discrepancy' => discrepancy,
    'approaching' => approaching,
    'expired' => expired,
    _ => true,
  };
}

class SaleSnapshot {
  static Json latest(Json original, Json? cached, Json? remote) {
    if (cached?['syncStatus'] != null) return cached!;
    var selected = original;
    for (final value in [cached, remote]) {
      if (value != null &&
          integer(value['version']) >= integer(selected['version'])) {
        selected = value;
      }
    }
    return selected;
  }
}
