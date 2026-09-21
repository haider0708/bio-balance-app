import 'models.dart';

class FulfillmentLine {
  final String productId;
  final int ordered,
      received,
      inTransit,
      remainingToDispatch,
      remainingToReceive;
  FulfillmentLine.fromJson(Json json)
    : productId = json['productId'],
      ordered = integer(json['ordered']),
      received = integer(json['received']),
      inTransit = integer(json['inTransit']),
      remainingToDispatch = integer(json['remainingToDispatch']),
      remainingToReceive = integer(json['remainingToReceive']);
  static int outstanding(StoreData data, String product) {
    if (data.raw.containsKey('outstandingSupply')) {
      return data
          .list('outstandingSupply')
          .where((line) => line['productId'] == product)
          .fold(0, (sum, line) => sum + integer(line['quantity']));
    }
    return data
        .list('orders')
        .expand((order) => objects(order['fulfillment']))
        .where((line) => line['productId'] == product)
        .fold(0, (sum, line) => sum + integer(line['remainingToReceive']));
  }
}

class OrderFulfillment {
  final String orderId, status;
  final int version;
  final List<FulfillmentLine> lines;
  OrderFulfillment.fromJson(Json json)
    : orderId = json['orderId'],
      status = json['status'],
      version = integer(json['version']),
      lines = List.unmodifiable(
        objects(json['lines']).map(FulfillmentLine.fromJson),
      );
}
