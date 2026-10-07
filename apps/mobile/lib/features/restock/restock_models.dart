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
    this.requestedBy,
    this.receiver,
    this.note,
    this.receiptPhotoId,
    this.receiptPhotoIds = const [],
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
  final Actor? requestedBy;
  final Actor? receiver;
  final String? note;
  final DateTime createdAt;
  final DateTime? shippedAt;
  final DateTime? receivedAt;
  final DateTime? decidedAt;
  final String? receiptPhotoId;
  final List<String> receiptPhotoIds;
  final String? decisionNote;
  final String? cancelReason;
  final List<RestockLine> lines;

  int get requestedUnits => lines.fold(0, (s, l) => s + l.requested);
  int get shippedUnits => lines.fold(0, (s, l) => s + (l.shipped ?? 0));
  int get receivedUnits => lines.fold(0, (s, l) => s + (l.received ?? 0));
  int get approvedUnits => lines.fold(0, (s, l) => s + (l.approved ?? 0));

  bool get toDepot => destinationKind == 'DEPOT';

  /// Can this person still choose who counts the delivery?
  bool canChooseReceiver(Role role) =>
      role == Role.responsable &&
      !toDepot &&
      (status == RestockStatus.assigned ||
          status == RestockStatus.shipped ||
          status == RestockStatus.requested);
}
