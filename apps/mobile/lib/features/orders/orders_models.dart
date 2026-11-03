import '../../core/api/json.dart';

/// What waits in the orders, by step.
class OrderCounts {
  const OrderCounts({
    required this.requested,
    required this.proposed,
    required this.toShip,
    required this.onTheRoad,
    required this.delivered,
    required this.toApprove,
  });

  factory OrderCounts.fromJson(Json j) => OrderCounts(
    requested: j.integer('requested'),
    proposed: j.integer('proposed'),
    toShip: j.integer('toShip'),
    onTheRoad: j.integer('onTheRoad'),
    delivered: j.integer('delivered'),
    toApprove: j.integer('toApprove'),
  );

  /// Asked by a para, nothing proposed yet.
  final int requested;

  /// Proposed, waiting for the admin.
  final int proposed;
  final int toShip;
  final int onTheRoad;
  final int delivered;
  final int toApprove;
}

enum ParaLevel { ok, low, out }

/// One para on the board: how its stock stands, without any money.
class ParaRow {
  const ParaRow({
    required this.id,
    required this.name,
    required this.city,
    required this.region,
    required this.group,
    required this.products,
    required this.units,
    required this.low,
    required this.out,
    required this.sold7Days,
    required this.openOrders,
    this.phone,
    this.address,
  });

  factory ParaRow.fromJson(Json j) {
    final stock = j.obj('stock');
    return ParaRow(
      id: j.str('id'),
      name: j.str('name'),
      city: j.str('city'),
      address: j.strOrNull('address'),
      phone: j.strOrNull('phone'),
      region: j.obj('region').str('name'),
      group: j.objOrNull('group')?.str('name'),
      products: stock.integer('products'),
      units: stock.integer('units'),
      low: stock.integer('low'),
      out: stock.integer('out'),
      sold7Days: j.integer('sold7Days'),
      openOrders: j.integer('openOrders'),
    );
  }

  final String id;
  final String name;
  final String city;
  final String? address;
  final String? phone;
  final String region;
  final String? group;
  final int products;
  final int units;
  final int low;
  final int out;
  final int sold7Days;
  final int openOrders;

  ParaLevel get level => out > 0
      ? ParaLevel.out
      : low > 0
      ? ParaLevel.low
      : ParaLevel.ok;
}

class OrdersOverview {
  const OrdersOverview({
    required this.orders,
    required this.total,
    required this.low,
    required this.out,
    required this.attention,
  });

  factory OrdersOverview.fromJson(Json j) => OrdersOverview(
    orders: OrderCounts.fromJson(j.obj('orders')),
    total: j.obj('paras').integer('total'),
    low: j.obj('paras').integer('low'),
    out: j.obj('paras').integer('out'),
    attention: j.list('attention').map(ParaRow.fromJson).toList(),
  );

  final OrderCounts orders;
  final int total;
  final int low;
  final int out;
  final List<ParaRow> attention;
}

class ParaStockLine {
  const ParaStockLine({
    required this.productId,
    required this.name,
    required this.family,
    required this.quantity,
    required this.level,
    required this.sold7Days,
    this.coverDays,
  });

  factory ParaStockLine.fromJson(Json j) => ParaStockLine(
    productId: j.str('productId'),
    name: j.str('name'),
    family: j.str('family'),
    quantity: j.integer('quantity'),
    level: switch (j.str('level')) {
      'OUT' => ParaLevel.out,
      'LOW' => ParaLevel.low,
      _ => ParaLevel.ok,
    },
    sold7Days: j.integer('sold7Days'),
    coverDays: j.integerOrNull('coverDays'),
  );

  final String productId;
  final String name;
  final String family;
  final int quantity;
  final ParaLevel level;
  final int sold7Days;

  /// Days the quantity would last at last week's pace; null when nothing sold.
  final int? coverDays;
}

class ParaOrder {
  const ParaOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.units,
    required this.proposed,
    required this.delivered,
  });

  factory ParaOrder.fromJson(Json j) => ParaOrder(
    id: j.str('id'),
    number: j.str('number'),
    status: j.str('status'),
    units: j.integer('units'),
    proposed: j.flag('proposed'),
    delivered: j.flag('delivered'),
  );

  final String id;
  final String number;
  final String status;
  final int units;
  final bool proposed;
  final bool delivered;
}

class ParaContact {
  const ParaContact({
    required this.id,
    required this.name,
    required this.role,
    this.phone,
  });

  factory ParaContact.fromJson(Json j) => ParaContact(
    id: j.str('id'),
    name: j.str('name'),
    role: j.str('role'),
    phone: j.strOrNull('phone'),
  );

  final String id;
  final String name;

  /// VENDEUR or RESPONSABLE.
  final String role;
  final String? phone;
}

/// One para opened: its stock line by line, what is on order, who to call.
class ParaDetail {
  const ParaDetail({
    required this.row,
    required this.lines,
    required this.orders,
    required this.contacts,
    this.lastAskedAt,
  });

  factory ParaDetail.fromJson(Json j) => ParaDetail(
    row: ParaRow.fromJson(j),
    lines: j.obj('stock').list('lines').map(ParaStockLine.fromJson).toList(),
    orders: j.list('orders').map(ParaOrder.fromJson).toList(),
    contacts: j.list('contacts').map(ParaContact.fromJson).toList(),
    lastAskedAt: j.dateOrNull('lastAskedAt'),
  );

  final ParaRow row;
  final List<ParaStockLine> lines;
  final List<ParaOrder> orders;
  final List<ParaContact> contacts;
  final DateTime? lastAskedAt;
}
