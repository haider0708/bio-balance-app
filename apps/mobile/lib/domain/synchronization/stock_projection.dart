import '../models/batch_declaration.dart';
import '../models/tunis_dates.dart';

import '../models/models.dart';

/// A movement changes one stock bucket and increments the lot version once.
class LotMovement {
  final String lotId;
  final int sellableDelta, damagedDelta, increments;
  final Json? declaration;
  const LotMovement(
    this.lotId, {
    this.sellableDelta = 0,
    this.damagedDelta = 0,
    this.increments = 1,
    this.declaration,
  });
  Json toJson() => {
    'id': lotId,
    'delta': sellableDelta,
    'damagedDelta': damagedDelta,
    'increments': increments,
    ...?declaration,
  };
}

class StockProjection {
  final List<LotMovement> movements;
  final Set<String> records;
  const StockProjection(this.movements, this.records);

  static String lotIdentity(String store, Json line) =>
      BatchDeclaration.identity(
        store,
        line['productId'],
        line['batch'],
        line['expiry'],
      );

  factory StockProjection.forCommand(
    String store,
    Json command,
    StoreData? data, {
    DateTime? now,
  }) {
    final movements = <LotMovement>[];
    final records = <String>{};
    final type = command['type'];
    final saleId = command['saleId'];
    if (saleId != null) records.add('sale:$saleId');
    for (final key in ['deliveryId', 'orderId', 'claimId']) {
      if (command[key] != null) records.add('$key:${command[key]}');
    }
    if (type == 'stock.receive' || type == 'delivery.receive') {
      for (final line in objects(command['lines'])) {
        final lotId = lotIdentity(store, line);
        movements.add(
          LotMovement(
            lotId,
            sellableDelta: integer(line['quantity']),
            declaration: {
              'productId': line['productId'],
              'batch': line['batch'],
              'expiry': TunisDates.expiry(line['expiry']),
            },
          ),
        );
      }
    } else if (type == 'sale.create' || type == 'sale.correct') {
      for (final declaration in objects(command['batchDeclarations'])) {
        movements.add(
          LotMovement(
            declaration['lotId'],
            increments: 0,
            declaration: {
              'productId': declaration['productId'],
              'batch': declaration['batch'],
              'expiry': declaration['expiry'],
            },
          ),
        );
      }
      final deltas = <String, int>{};
      final original = data
          ?.list('sales')
          .where((s) => s['id'] == saleId)
          .firstOrNull;
      if (type == 'sale.correct') {
        for (final line in objects(original?['lines'])) {
          for (final a in objects(line['allocations'])) {
            deltas[a['lotId']] =
                (deltas[a['lotId']] ?? 0) + integer(a['quantity']);
          }
        }
      }
      for (final line in objects(command['lines'])) {
        for (final a in objects(line['allocations'])) {
          deltas[a['lotId']] =
              (deltas[a['lotId']] ?? 0) - integer(a['quantity']);
        }
      }
      for (final e in deltas.entries) {
        records.add('lot:${e.key}');
        if (e.value != 0) {
          movements.add(LotMovement(e.key, sellableDelta: e.value));
        }
      }
    } else if (type == 'sale.return') {
      final today = TunisDates.today(now);
      for (final line in objects(command['lines'])) {
        final lot = data
            ?.list('lots')
            .where((l) => l['id'] == line['lotId'])
            .firstOrNull;
        final expiry = '${lot?['expiry'] ?? today}'.substring(0, 10);
        final sellable =
            line['sellable'] == true && expiry.compareTo(today) >= 0;
        movements.add(
          LotMovement(
            line['lotId'],
            sellableDelta: sellable ? integer(line['quantity']) : 0,
            damagedDelta: sellable ? 0 : integer(line['quantity']),
          ),
        );
      }
    } else if (type == 'stock.damage' || type == 'stock.adjust') {
      final id = command['lotId'] as String;
      final lot = data?.list('lots').where((l) => l['id'] == id).firstOrNull;
      final quantity = integer(command['quantity']);
      if (type == 'stock.damage') {
        if (lot != null && integer(lot['sellable']) < quantity) {
          throw const AppFailure(
            'INSUFFICIENT_STOCK',
            'Stock insuffisant pour cette sortie.',
          );
        }
        movements.add(
          LotMovement(
            id,
            sellableDelta: -quantity,
            damagedDelta: quantity,
            increments: 2,
          ),
        );
      } else {
        movements.add(
          LotMovement(id, sellableDelta: quantity - integer(lot?['sellable'])),
        );
      }
    }
    records.addAll(movements.map((m) => 'lot:${m.lotId}'));
    return StockProjection(
      List.unmodifiable(movements),
      Set.unmodifiable(records),
    );
  }

  static void apply(List<Json> lots, Json patch) {
    final index = lots.indexWhere((l) => l['id'] == patch['id']);
    if (index < 0 && patch['productId'] == null) return;
    final old = index < 0
        ? <String, dynamic>{...patch, 'sellable': 0, 'damaged': 0, 'version': 1}
        : lots[index];
    final updated = <String, dynamic>{
      ...old,
      'sellable': integer(old['sellable']) + integer(patch['delta']),
      'damaged': integer(old['damaged']) + integer(patch['damagedDelta']),
      'version': patch.containsKey('increments')
          ? integer(old['version']) + integer(patch['increments'])
          : integer(patch['version'] ?? old['version']),
    };
    if (index < 0) {
      lots.add(updated);
    } else {
      lots[index] = updated;
    }
  }
}
