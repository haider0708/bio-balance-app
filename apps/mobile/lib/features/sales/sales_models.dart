import '../../core/api/json.dart';
import '../../core/auth/me.dart';
import '../wallet/wallet_models.dart';

class SaleLine {
  const SaleLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.rewardMillimes,
    this.imageId,
  });

  factory SaleLine.fromJson(Json j) => SaleLine(
    productId: j.str('productId'),
    name: j.str('name'),
    imageId: j.strOrNull('imageId'),
    quantity: j.integer('quantity'),
    rewardMillimes: j.integer('rewardMillimes'),
  );

  final String productId;
  final String name;
  final String? imageId;
  final int quantity;
  final int rewardMillimes;
}

class SaleRevision {
  const SaleRevision({
    required this.version,
    required this.reason,
    required this.createdAt,
  });

  factory SaleRevision.fromJson(Json j) => SaleRevision(
    version: j.integer('version'),
    reason: j.str('reason'),
    createdAt: j.date('createdAt'),
  );

  final int version;
  final String reason;
  final DateTime createdAt;
}

class Sale {
  const Sale({
    required this.id,
    required this.day,
    required this.voided,
    required this.version,
    required this.occurredAt,
    required this.createdAt,
    required this.units,
    required this.rewardMillimes,
    required this.seller,
    required this.pdv,
    required this.lines,
    this.revisions = const [],
    this.wallet,
    this.replay = false,
  });

  factory Sale.fromJson(Json j) => Sale(
    id: j.str('id'),
    day: j.str('day'),
    voided: j.str('status') == 'VOIDED',
    version: j.integer('version', 1),
    occurredAt: j.date('occurredAt'),
    createdAt: j.date('createdAt'),
    units: j.integer('units'),
    rewardMillimes: j.integer('rewardMillimes'),
    seller: Place.fromJson(j.obj('seller')),
    pdv: Place.fromJson(j.obj('pdv')),
    lines: j.list('lines').map(SaleLine.fromJson).toList(),
    revisions: j.list('revisions').map(SaleRevision.fromJson).toList(),
    wallet: j.objOrNull('wallet') == null
        ? null
        : WalletSummary.fromJson(j.obj('wallet')),
    replay: j.flag('replay'),
  );

  final String id;

  /// The Tunis calendar day, `YYYY-MM-DD`.
  final String day;
  final bool voided;
  final int version;
  final DateTime occurredAt;
  final DateTime createdAt;
  final int units;
  final int rewardMillimes;
  final Place seller;
  final Place pdv;
  final List<SaleLine> lines;
  final List<SaleRevision> revisions;

  /// Present right after recording a sale: the new totals for the celebration screen.
  final WalletSummary? wallet;
  final bool replay;

  /// Recorded without a connection and sent more than an hour after it happened.
  bool get sentLater =>
      createdAt.difference(occurredAt) > const Duration(hours: 1);

  /// A seller may correct their own sale for 48 hours.
  bool get sellerCanCorrect =>
      !voided &&
      DateTime.now().difference(createdAt) < const Duration(hours: 48);
}

class SalesPage {
  const SalesPage(this.items, this.nextCursor);

  final List<Sale> items;
  final String? nextCursor;
}

/// A sale saved on the phone because there was no connection. It keeps its id,
/// so sending it twice can never count it twice.
class PendingSale {
  const PendingSale({
    required this.id,
    required this.occurredAt,
    required this.lines,
    this.error,
  });

  factory PendingSale.fromJson(Json j) => PendingSale(
    id: j.str('id'),
    occurredAt: j.date('occurredAt'),
    lines: j.list('lines').map(PendingLine.fromJson).toList(),
    error: j.strOrNull('error'),
  );

  final String id;
  final DateTime occurredAt;
  final List<PendingLine> lines;

  /// Set when the server refused the sale (it will not be retried).
  final String? error;

  int get units => lines.fold(0, (sum, l) => sum + l.quantity);

  PendingSale withError(String message) =>
      PendingSale(id: id, occurredAt: occurredAt, lines: lines, error: message);

  Json toJson() => {
    'id': id,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'lines': [for (final l in lines) l.toJson()],
    'error': error,
  };
}

class PendingLine {
  const PendingLine({
    required this.productId,
    required this.name,
    required this.quantity,
  });

  factory PendingLine.fromJson(Json j) => PendingLine(
    productId: j.str('productId'),
    name: j.str('name'),
    quantity: j.integer('quantity'),
  );

  final String productId;
  final String name;
  final int quantity;

  Json toJson() => {'productId': productId, 'name': name, 'quantity': quantity};
}

/// A day of sales with its totals.
class SaleDay {
  const SaleDay({
    required this.day,
    required this.sales,
    required this.units,
    required this.rewardMillimes,
  });

  factory SaleDay.fromJson(Json j) => SaleDay(
    day: j.str('day'),
    sales: j.integer('sales'),
    units: j.integer('units'),
    rewardMillimes: j.integer('rewardMillimes'),
  );

  final String day;
  final int sales;
  final int units;
  final int rewardMillimes;
}
