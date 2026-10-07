import '../../core/api/json.dart';

enum StockLevel { ok, low, negative }

class StockItem {
  const StockItem({
    required this.productId,
    required this.name,
    required this.family,
    required this.quantity,
    required this.level,
    this.imageId,
  });

  factory StockItem.fromJson(Json j) => StockItem(
    productId: j.str('productId'),
    name: j.str('name'),
    family: j.str('family'),
    imageId: j.strOrNull('imageId'),
    quantity: j.integer('quantity'),
    level: switch (j.str('level')) {
      'NEGATIVE' => StockLevel.negative,
      'LOW' => StockLevel.low,
      _ => StockLevel.ok,
    },
  );

  final String productId;
  final String name;
  final String family;
  final String? imageId;
  final int quantity;
  final StockLevel level;
}

class StockLocation {
  const StockLocation({
    required this.id,
    required this.kind,
    required this.name,
    required this.status,
  });

  factory StockLocation.fromJson(Json j) => StockLocation(
    id: j.str('id'),
    kind: j.str('kind'),
    name: j.str('name'),
    status: j.str('status'),
  );

  final String id;
  final String kind;
  final String name;
  final String status;
}

class StockLevels {
  const StockLevels({required this.location, required this.items});

  factory StockLevels.fromJson(Json j) => StockLevels(
    location: StockLocation.fromJson(j.obj('location')),
    items: j.list('items').map(StockItem.fromJson).toList(),
  );

  final StockLocation location;
  final List<StockItem> items;

  int get units => items.fold(0, (s, i) => s + i.quantity);
}

class DeclarationLine {
  const DeclarationLine({
    required this.productId,
    required this.name,
    required this.family,
    required this.quantity,
    this.approvedQuantity,
  });

  factory DeclarationLine.fromJson(Json j) => DeclarationLine(
    productId: j.str('productId'),
    name: j.str('name'),
    family: j.str('family'),
    quantity: j.integer('quantity'),
    approvedQuantity: j.integerOrNull('approvedQuantity'),
  );

  final String productId;
  final String name;
  final String family;
  final int quantity;
  final int? approvedQuantity;
}

enum DeclarationStatus {
  pending,
  approved,
  rejected;

  static DeclarationStatus parse(String v) =>
      DeclarationStatus.values.firstWhere(
        (s) => s.name.toUpperCase() == v,
        orElse: () => DeclarationStatus.pending,
      );
}

class StockDeclaration {
  const StockDeclaration({
    required this.id,
    required this.initial,
    required this.status,
    required this.location,
    this.photoId,
    this.photoIds = const [],
    required this.createdBy,
    required this.createdAt,
    required this.lines,
    this.note,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote,
  });

  factory StockDeclaration.fromJson(Json j) => StockDeclaration(
    id: j.str('id'),
    initial: j.str('kind') == 'INITIAL',
    status: DeclarationStatus.parse(j.str('status')),
    location: StockLocation(
      id: j.obj('location').str('id'),
      kind: j.obj('location').str('kind'),
      name: j.obj('location').str('name'),
      status: '',
    ),
    photoId: j.strOrNull('photoId'),
    photoIds: ((j['photoIds'] as List<dynamic>?) ?? const []).cast<String>(),
    note: j.strOrNull('note'),
    createdBy: j.obj('createdBy').str('name'),
    createdAt: j.date('createdAt'),
    decidedBy: j.objOrNull('decidedBy')?.str('name'),
    decidedAt: j.dateOrNull('decidedAt'),
    decisionNote: j.strOrNull('decisionNote'),
    lines: j.list('lines').map(DeclarationLine.fromJson).toList(),
  );

  final String id;

  /// The first declaration of a place; later ones are recounts.
  final bool initial;
  final DeclarationStatus status;
  final StockLocation location;
  final String? photoId;
  final List<String> photoIds;
  final String? note;
  final String createdBy;
  final DateTime createdAt;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String? decisionNote;
  final List<DeclarationLine> lines;

  int get units => lines.fold(0, (s, l) => s + l.quantity);
}
