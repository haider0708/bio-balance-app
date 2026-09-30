import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/synchronization/stock_projection.dart';
import 'package:flutter_test/flutter_test.dart';

StoreData data(int sellable) => StoreData({
  'lots': [
    {
      'id': 'lot',
      'productId': 'p',
      'batch': 'A',
      'expiry': '2099-01-01',
      'sellable': sellable,
      'damaged': 0,
      'version': 4,
    },
  ],
});

void main() {
  test('a flag holds units out of sale offline, like a damage report', () {
    for (final type in ['quality.flag', 'stock.damage']) {
      final projection = StockProjection.forCommand('store', {
        'type': type,
        'lotId': 'lot',
        'quantity': 3,
        'kind': 'damaged',
      }, data(10));
      final movement = projection.movements.single;
      expect(movement.sellableDelta, -3, reason: type);
      expect(movement.damagedDelta, 3, reason: type);
      // Two stock changes on the server: two version increments here.
      expect(movement.increments, 2, reason: type);
      expect(projection.records, contains('lot:lot'));
    }
  });

  test('flagging more than the lot holds is refused before it is queued', () {
    expect(
      () => StockProjection.forCommand('store', {
        'type': 'quality.flag',
        'lotId': 'lot',
        'quantity': 11,
        'kind': 'expired',
      }, data(10)),
      throwsA(
        isA<AppFailure>().having((e) => e.code, 'code', 'INSUFFICIENT_STOCK'),
      ),
    );
  });

  test('the projected lot shows the flagged units as unsellable', () {
    final lots = [Map<String, dynamic>.from(data(10).raw['lots'][0])];
    final projection = StockProjection.forCommand('store', {
      'type': 'quality.flag',
      'lotId': 'lot',
      'quantity': 4,
      'kind': 'damaged',
    }, data(10));
    for (final movement in projection.movements) {
      StockProjection.apply(lots, movement.toJson());
    }
    expect(lots.single['sellable'], 6);
    expect(lots.single['damaged'], 4);
    expect(lots.single['version'], 6);
  });
}
