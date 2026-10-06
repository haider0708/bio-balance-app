import '../../core/api/json.dart';

class RewardRule {
  const RewardRule({
    required this.id,
    required this.byProduct,
    required this.targetName,
    required this.amountMillimes,
    required this.startsOn,
    this.productId,
    this.family,
    this.endsOn,
    this.note,
  });

  factory RewardRule.fromJson(Json j) => RewardRule(
    id: j.str('id'),
    byProduct: j.str('scope') == 'PRODUCT',
    productId: j.strOrNull('productId'),
    family: j.strOrNull('family'),
    targetName: j.str('targetName'),
    amountMillimes: j.integer('amountMillimes'),
    startsOn: DateTime.parse(j.str('startsOn')),
    endsOn: j.strOrNull('endsOn') == null
        ? null
        : DateTime.parse(j.str('endsOn')),
    note: j.strOrNull('note'),
  );

  final String id;
  final bool byProduct;
  final String? productId;
  final String? family;
  final String targetName;
  final int amountMillimes;
  final DateTime startsOn;
  final DateTime? endsOn;
  final String? note;
}

/// What a product pays today, and where that value comes from.
class EffectiveReward {
  const EffectiveReward({
    required this.productId,
    required this.name,
    required this.family,
    required this.amountMillimes,
  });

  factory EffectiveReward.fromJson(Json j) => EffectiveReward(
    productId: j.str('productId'),
    name: j.str('name'),
    family: j.str('family'),
    amountMillimes: j.integer('amountMillimes'),
  );

  final String productId;
  final String name;
  final String family;
  final int amountMillimes;
}
