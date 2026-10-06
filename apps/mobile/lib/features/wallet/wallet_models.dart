import '../../core/api/json.dart';

class EarningsWindow {
  const EarningsWindow({required this.sales, required this.units, required this.rewardMillimes});

  factory EarningsWindow.fromJson(Json j) => EarningsWindow(
        sales: j.integer('sales'),
        units: j.integer('units'),
        rewardMillimes: j.integer('rewardMillimes'),
      );

  static const zero = EarningsWindow(sales: 0, units: 0, rewardMillimes: 0);

  final int sales;
  final int units;
  final int rewardMillimes;
}

/// A team member's money: what they hold, what is already requested, what they earned lately.
class WalletSummary {
  const WalletSummary({
    required this.balanceMillimes,
    required this.pendingMillimes,
    required this.availableMillimes,
    required this.today,
    required this.week,
    required this.month,
  });

  factory WalletSummary.fromJson(Json j) => WalletSummary(
        balanceMillimes: j.integer('balanceMillimes'),
        pendingMillimes: j.integer('pendingPayoutMillimes'),
        availableMillimes: j.integer('availableMillimes'),
        today: EarningsWindow.fromJson(j.obj('today')),
        week: EarningsWindow.fromJson(j.obj('week')),
        month: EarningsWindow.fromJson(j.obj('month')),
      );

  final int balanceMillimes;
  final int pendingMillimes;
  final int availableMillimes;
  final EarningsWindow today;
  final EarningsWindow week;
  final EarningsWindow month;
}

enum WalletKind { sale, correction, payout }

class WalletEntry {
  const WalletEntry({required this.id, required this.kind, required this.amountMillimes, required this.createdAt, this.saleId, this.note});

  factory WalletEntry.fromJson(Json j) => WalletEntry(
        id: j.str('id'),
        kind: switch (j.str('kind')) {
          'SALE' => WalletKind.sale,
          'PAYOUT' => WalletKind.payout,
          _ => WalletKind.correction,
        },
        amountMillimes: j.integer('amountMillimes'),
        createdAt: j.date('createdAt'),
        saleId: j.strOrNull('saleId'),
        note: j.strOrNull('note'),
      );

  final String id;
  final WalletKind kind;
  final int amountMillimes;
  final DateTime createdAt;
  final String? saleId;
  final String? note;
}

enum PayoutStatus {
  pending,
  approved,
  rejected,
  cancelled;

  static PayoutStatus parse(String v) => PayoutStatus.values.firstWhere((s) => s.name.toUpperCase() == v, orElse: () => PayoutStatus.pending);
}

class Payout {
  const Payout({
    required this.id,
    required this.amountMillimes,
    required this.status,
    required this.createdAt,
    this.userName,
    this.userPdv,
    this.userPhone,
    this.regionId,
    this.decidedAt,
    this.decisionNote,
    this.paidAt,
    this.reference,
  });

  factory Payout.fromJson(Json j) => Payout(
        id: j.str('id'),
        amountMillimes: j.integer('amountMillimes'),
        status: PayoutStatus.parse(j.str('status')),
        createdAt: j.date('createdAt'),
        userName: j.objOrNull('user')?.str('name'),
        userPdv: j.objOrNull('user')?.strOrNull('pdv'),
        userPhone: j.objOrNull('user')?.strOrNull('phone'),
        regionId: j.strOrNull('regionId'),
        decidedAt: j.dateOrNull('decidedAt'),
        decisionNote: j.strOrNull('decisionNote'),
        paidAt: j.dateOrNull('paidAt'),
        reference: j.strOrNull('reference'),
      );

  final String id;
  final int amountMillimes;
  final PayoutStatus status;
  final DateTime createdAt;
  final String? userName;
  final String? userPdv;
  final String? userPhone;
  final String? regionId;
  final DateTime? decidedAt;
  final String? decisionNote;
  final DateTime? paidAt;
  final String? reference;
}

/// One team member's wallet, as the admin sees it.
class WalletOverview {
  const WalletOverview({
    required this.userId,
    required this.name,
    required this.pdv,
    required this.region,
    required this.earned,
    required this.paid,
    required this.balance,
    required this.pending,
    required this.available,
  });

  factory WalletOverview.fromJson(Json j) => WalletOverview(
        userId: j.str('userId'),
        name: j.str('name'),
        pdv: j.str('pdv'),
        region: j.str('region'),
        earned: j.integer('earned'),
        paid: j.integer('paid'),
        balance: j.integer('balance'),
        pending: j.integer('pending'),
        available: j.integer('availableMillimes'),
      );

  final String userId;
  final String name;
  final String pdv;
  final String region;
  final int earned;
  final int paid;
  final int balance;
  final int pending;
  final int available;
}
