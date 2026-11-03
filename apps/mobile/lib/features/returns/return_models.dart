import '../../core/api/json.dart';
import '../transfers/transfer_models.dart';

/// What a return does to stock: take quantities out of a para, move them to another, or only add them.
enum ReturnAction {
  remove,
  move,
  add;

  static ReturnAction parse(String v) => switch (v) {
    'MOVE' => move,
    'ADD' => add,
    _ => remove,
  };

  String get wire => name.toUpperCase();
}

class StockReturn {
  const StockReturn({
    required this.id,
    required this.number,
    required this.status,
    required this.action,
    required this.para,
    required this.createdBy,
    required this.createdAt,
    required this.units,
    required this.lines,
    required this.canEdit,
    required this.canCancel,
    required this.canDecide,
    required this.changes,
    this.to,
    this.region,
    this.note,
    this.expiresAt,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote,
  });

  factory StockReturn.fromJson(Json j) => StockReturn(
    id: j.str('id'),
    number: j.str('number'),
    status: TransferStatus.parse(j.str('status')),
    action: ReturnAction.parse(j.str('action')),
    para: TransferPara.fromJson(j.obj('para')),
    to: j.objOrNull('to') == null ? null : TransferPara.fromJson(j.obj('to')),
    region: j.strOrNull('region'),
    createdBy: j.objOrNull('createdBy')?.str('name') ?? '',
    createdAt: j.date('createdAt'),
    expiresAt: j.dateOrNull('expiresAt'),
    note: j.strOrNull('note'),
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
  final ReturnAction action;

  /// The para the quantities leave (take out, move) or enter (add).
  final TransferPara para;

  /// The para that receives them (move only).
  final TransferPara? to;
  final String? region;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String? note;
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
