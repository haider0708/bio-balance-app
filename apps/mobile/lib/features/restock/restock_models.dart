import '../../core/api/json.dart';
import '../../core/auth/me.dart';

enum RestockStatus {
  requested,
  assigned,
  shipped,
  received,
  completed,
  cancelled;

  static RestockStatus parse(String v) => RestockStatus.values.firstWhere(
    (s) => s.name.toUpperCase() == v,
    orElse: () => RestockStatus.requested,
  );
  String get wire => name.toUpperCase();

  bool get open => this != completed && this != cancelled;
}

class RestockLine {
  const RestockLine({
    required this.productId,
    required this.name,
    required this.family,
    required this.requested,
    this.shipped,
    this.received,
    this.approved,
  });

  factory RestockLine.fromJson(Json j) => RestockLine(
    productId: j.str('productId'),
    name: j.str('name'),
    family: j.str('family'),
    requested: j.integer('requested'),
    shipped: j.integerOrNull('shipped'),
    received: j.integerOrNull('received'),
    approved: j.integerOrNull('approved'),
  );

  final String productId;
  final String name;
  final String family;
  final int requested;
  final int? shipped;
  final int? received;
  final int? approved;
}

class Actor {
  const Actor({required this.id, required this.name});

  static Actor? from(Json? j) =>
      j == null ? null : Actor(id: j.str('id'), name: j.str('name'));

  final String id;
  final String name;
}

class RestockOrder {
  const RestockOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.destination,
    required this.destinationKind,
    required this.destinationId,
    required this.createdAt,
    required this.lines,
    this.regionId,
    this.source,
    this.supplier,
    this.supplierId,
    this.supplierRegionId,
    this.suggestedSupplier,
    this.requestedBy,
    this.receiver,
    this.note,
    this.receiptPhotoId,
    this.receiptPhotoIds = const [],
    this.receiptNote,
    this.decisionNote,
    this.cancelReason,
    this.shippedAt,
    this.receivedAt,
    this.decidedAt,
  });

  factory RestockOrder.fromJson(Json j) => RestockOrder(
    id: j.str('id'),
    number: j.str('number'),
    status: RestockStatus.parse(j.str('status')),
    source: j.strOrNull('source'),
    regionId: j.strOrNull('regionId'),
    destination: j.obj('destination').str('name'),
    destinationKind: j.obj('destination').str('kind'),
    destinationId: j.obj('destination').str('id'),
    supplier: j.objOrNull('supplier')?.str('name'),
    supplierId: j.objOrNull('supplier')?.str('id'),
    supplierRegionId: j.objOrNull('supplier')?.strOrNull('regionId'),
    suggestedSupplier: j.objOrNull('suggestedSupplier') == null
        ? null
        : Actor.from(j.objOrNull('suggestedSupplier')),
    requestedBy: Actor.from(j.objOrNull('requestedBy')),
    receiver: Actor.from(j.objOrNull('receiver')),
    note: j.strOrNull('note'),
    createdAt: j.date('createdAt'),
    shippedAt: j.dateOrNull('shippedAt'),
    receivedAt: j.dateOrNull('receivedAt'),
    decidedAt: j.dateOrNull('decidedAt'),
    receiptPhotoId: j.strOrNull('receiptPhotoId'),
    receiptPhotoIds: ((j['receiptPhotoIds'] as List<dynamic>?) ?? const [])
        .cast<String>(),
    receiptNote: j.strOrNull('receiptNote'),
    decisionNote: j.strOrNull('decisionNote'),
    cancelReason: j.strOrNull('cancelReason'),
    lines: j.list('lines').map(RestockLine.fromJson).toList(),
  );

  final String id;
  final String number;
  final RestockStatus status;

  /// GROSSISTE or BIOBALANCE once the admin has routed it.
  final String? source;
  final String? regionId;
  final String destination;
  final String destinationKind;
  final String destinationId;
  final String? supplier;
  final String? supplierId;

  /// The region the goods leave from: its responsable ships them.
  final String? supplierRegionId;

  /// The grossiste the responsable suggested (the admin decides).
  final Actor? suggestedSupplier;
  final Actor? requestedBy;
  final Actor? receiver;
  final String? note;
  final DateTime createdAt;
  final DateTime? shippedAt;
  final DateTime? receivedAt;
  final DateTime? decidedAt;
  final String? receiptPhotoId;
  final List<String> receiptPhotoIds;

  /// What the receiver wrote when confirming the delivery.
  final String? receiptNote;
  final String? decisionNote;
  final String? cancelReason;
  final List<RestockLine> lines;

  int get requestedUnits => lines.fold(0, (s, l) => s + l.requested);
  int get approvedUnits => lines.fold(0, (s, l) => s + (l.approved ?? 0));

  bool get toDepot => destinationKind == 'DEPOT';

  /// Can this person still choose who confirms the delivery? The store's own responsable only.
  bool canChooseReceiver(Me me) =>
      me.role == Role.responsable &&
      regionId == me.region?.id &&
      !toDepot &&
      (status == RestockStatus.assigned ||
          status == RestockStatus.shipped ||
          status == RestockStatus.requested);
}

/// A grossiste the admin can send an order from, with what it holds of the order's products.
class SupplierOption {
  const SupplierOption({
    required this.id,
    required this.name,
    required this.city,
    required this.regionId,
    required this.regionName,
    required this.held,
  });

  factory SupplierOption.fromJson(Json j) => SupplierOption(
    id: j.str('id'),
    name: j.str('name'),
    city: j.str('city'),
    regionId: j.str('regionId'),
    regionName: j.str('regionName'),
    held: {
      for (final l in j.list('lines')) l.str('productId'): l.integer('held'),
    },
  );

  final String id;
  final String name;
  final String city;
  final String regionId;
  final String regionName;

  /// Units it holds, by product.
  final Map<String, int> held;

  /// The products it holds fewer of than `wanted` asks for.
  int missing(Map<String, int> wanted) =>
      wanted.entries.where((e) => (held[e.key] ?? 0) < e.value).length;
}

/// A grossiste a responsable may suggest, and whether it covers the order (never its quantities).
class SupplierCoverage {
  const SupplierCoverage({
    required this.id,
    required this.name,
    required this.city,
    required this.regionName,
    required this.missing,
  });

  factory SupplierCoverage.fromJson(Json j) => SupplierCoverage(
    id: j.str('id'),
    name: j.str('name'),
    city: j.str('city'),
    regionName: j.str('regionName'),
    missing: j.integer('missing'),
  );

  final String id;
  final String name;
  final String city;
  final String regionName;

  /// How many of the order's products it does not hold enough of.
  final int missing;
}
