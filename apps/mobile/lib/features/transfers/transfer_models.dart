import '../../core/api/json.dart';

enum TransferStatus {
  pending,
  approved,
  rejected,
  cancelled,
  expired;

  static TransferStatus parse(String v) => switch (v) {
    'APPROVED' => approved,
    'REJECTED' => rejected,
    'CANCELLED' => cancelled,
    'EXPIRED' => expired,
    _ => pending,
  };

  String get wire => name.toUpperCase();
}

/// A para on one side of a transfer.
class TransferPara {
  const TransferPara({
    required this.id,
    required this.name,
    this.address = '',
    this.city = '',
  });

  factory TransferPara.fromJson(Json j) => TransferPara(
    id: j.str('id'),
    name: j.str('name'),
    address: j.str('address'),
    city: j.str('city'),
  );

  final String id;
  final String name;
  final String address;
  final String city;
}

class TransferLine {
  const TransferLine({
    required this.productId,
    required this.name,
    required this.family,
    required this.quantity,
    required this.requestedQuantity,
  });

  factory TransferLine.fromJson(Json j) => TransferLine(
    productId: j.str('productId'),
    name: j.str('name'),
    family: j.str('family'),
    quantity: j.integer('quantity'),
    requestedQuantity: j.integer('requestedQuantity'),
  );

  final String productId;
  final String name;
  final String family;

  /// What would move now.
  final int quantity;

  /// What was first asked (0 for a product added after).
  final int requestedQuantity;

  bool get changed => quantity != requestedQuantity;
}

/// One change of the quantities: who, when, from what to what.
class TransferChange {
  const TransferChange({
    required this.at,
    required this.by,
    required this.before,
    required this.after,
  });

  factory TransferChange.fromJson(Json j) => TransferChange(
    at: j.date('at'),
    by: j.objOrNull('by')?.str('name') ?? '',
    before: [for (final l in j.list('before')) _pair(l)],
    after: [for (final l in j.list('after')) _pair(l)],
  );

  static (String, int) _pair(Json l) => (l.str('name'), l.integer('quantity'));

  final DateTime at;
  final String by;
  final List<(String, int)> before;
  final List<(String, int)> after;
}

class Transfer {
  const Transfer({
    required this.id,
    required this.number,
    required this.status,
    required this.send,
    required this.groupName,
    required this.from,
    required this.to,
    required this.createdBy,
    required this.createdAt,
    required this.units,
    required this.lines,
    required this.canEdit,
    required this.canCancel,
    required this.canDecide,
    required this.changes,
    this.note,
    this.photoId,
    this.expiresAt,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote,
  });

  factory Transfer.fromJson(Json j) => Transfer(
    id: j.str('id'),
    number: j.str('number'),
    status: TransferStatus.parse(j.str('status')),
    send: j.str('direction') != 'REQUEST',
    groupName: j.obj('group').str('name'),
    from: TransferPara.fromJson(j.obj('from')),
    to: TransferPara.fromJson(j.obj('to')),
    createdBy: j.objOrNull('createdBy')?.str('name') ?? '',
    createdAt: j.date('createdAt'),
    expiresAt: j.dateOrNull('expiresAt'),
    note: j.strOrNull('note'),
    photoId: j.strOrNull('photoId'),
    decidedBy: j.objOrNull('decidedBy')?.strOrNull('name'),
    decidedAt: j.dateOrNull('decidedAt'),
    decisionNote: j.strOrNull('decisionNote'),
    units: j.integer('units'),
    lines: j.list('lines').map(TransferLine.fromJson).toList(),
    canEdit: j.flag('canEdit'),
    canCancel: j.flag('canCancel'),
    canDecide: j.flag('canDecide'),
    changes: j.list('changes').map(TransferChange.fromJson).toList(),
  );

  final String id;
  final String number;
  final TransferStatus status;

  /// True when the person who made it was sending; false when they were asking.
  final bool send;
  final String groupName;
  final TransferPara from;
  final TransferPara to;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String? note;
  final String? photoId;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String? decisionNote;
  final int units;
  final List<TransferLine> lines;
  final bool canEdit;
  final bool canCancel;
  final bool canDecide;
  final List<TransferChange> changes;

  bool get pending => status == TransferStatus.pending;
}

/// The paras of the same group as a para, to choose who to exchange with.
class Partners {
  const Partners({required this.groupName, required this.paras});

  factory Partners.fromJson(Json j) => Partners(
    groupName: j.objOrNull('group')?.strOrNull('name'),
    paras: j.list('partners').map(TransferPara.fromJson).toList(),
  );

  final String? groupName;
  final List<TransferPara> paras;
}
