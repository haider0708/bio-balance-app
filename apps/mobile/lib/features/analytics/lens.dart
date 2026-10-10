import 'package:flutter/foundation.dart';

import '../../core/util/dates.dart';

/// What a ranking is ordered by, and what the curve draws.
enum Metric {
  units,
  sales,
  reward;

  static Metric parse(String? raw) =>
      Metric.values.where((m) => m.name == raw).firstOrNull ?? Metric.units;
}

/// The places and products a lens can be narrowed to, one at a time each.
enum Facet { region, group, pdv, seller, product, family }

/// Today in Tunis (UTC+1 all year), the calendar the server counts sales in, wherever the screen is.
String tunisToday() =>
    Dates.day(DateTime.now().toUtc().add(const Duration(hours: 1)));

String _shift(String day, int days) =>
    Dates.day(Dates.parseDay(day).add(Duration(days: days)));

/// A question about sales: a period, and any of region, group, store, seller, product and family.
/// Every number on a dashboard opens one; every row of the answer opens a narrower one. It travels
/// in the address (`/explore?from=…&pdv=…`), so a page of the web console can be bookmarked or shared.
@immutable
class Lens {
  const Lens({
    required this.from,
    required this.to,
    this.regionId,
    this.groupId,
    this.pdvId,
    this.sellerId,
    this.productId,
    this.family,
    this.sort = Metric.units,
  });

  /// The last [days] days, today included.
  factory Lens.lastDays(int days, {String? today, Metric sort = Metric.units}) {
    final end = today ?? tunisToday();
    return Lens(from: _shift(end, 1 - days), to: end, sort: sort);
  }

  factory Lens.day(String day) => Lens(from: day, to: day);

  factory Lens.thisMonth() {
    final end = tunisToday();
    return Lens(from: '${end.substring(0, 8)}01', to: end);
  }

  factory Lens.fromQuery(Map<String, String> q) {
    final fallback = Lens.lastDays(30);
    final day = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    final from = q['from'];
    final to = q['to'];
    final valid =
        from != null &&
        to != null &&
        day.hasMatch(from) &&
        day.hasMatch(to) &&
        from.compareTo(to) <= 0;
    String? id(String key) {
      final v = q[key];
      return v != null && v.isNotEmpty ? v : null;
    }

    return Lens(
      from: valid ? from : fallback.from,
      to: valid ? to : fallback.to,
      regionId: id('region'),
      groupId: id('group'),
      pdvId: id('pdv'),
      sellerId: id('seller'),
      productId: id('product'),
      family: id('family'),
      sort: Metric.parse(q['sort']),
    );
  }

  final String from;
  final String to;
  final String? regionId;
  final String? groupId;
  final String? pdvId;
  final String? sellerId;
  final String? productId;
  final String? family;
  final Metric sort;

  int get days =>
      Dates.parseDay(to).difference(Dates.parseDay(from)).inDays + 1;

  bool get isSingleDay => from == to;

  String? value(Facet f) => switch (f) {
    Facet.region => regionId,
    Facet.group => groupId,
    Facet.pdv => pdvId,
    Facet.seller => sellerId,
    Facet.product => productId,
    Facet.family => family,
  };

  /// The facets set, from the widest to the narrowest.
  List<Facet> get facets => [
    for (final f in Facet.values)
      if (value(f) != null) f,
  ];

  Lens copyWith({String? from, String? to, Metric? sort}) => Lens(
    from: from ?? this.from,
    to: to ?? this.to,
    regionId: regionId,
    groupId: groupId,
    pdvId: pdvId,
    sellerId: sellerId,
    productId: productId,
    family: family,
    sort: sort ?? this.sort,
  );

  /// The same question narrowed to one more thing (or [value] null to widen it again).
  Lens withFacet(Facet facet, String? value) => Lens(
    from: from,
    to: to,
    regionId: facet == Facet.region ? value : regionId,
    groupId: facet == Facet.group ? value : groupId,
    pdvId: facet == Facet.pdv ? value : pdvId,
    sellerId: facet == Facet.seller ? value : sellerId,
    productId: facet == Facet.product ? value : productId,
    family: facet == Facet.family ? value : family,
    sort: sort,
  );

  /// What the server's analytics and sales endpoints take.
  Map<String, Object?> get query => {
    'from': from,
    'to': to,
    'regionId': regionId,
    'groupId': groupId,
    'pdvId': pdvId,
    'sellerId': sellerId,
    'productId': productId,
    'family': family,
  };

  /// The address of this question on a page of the app.
  String location([String path = '/explore']) => Uri(
    path: path,
    queryParameters: {
      'from': from,
      'to': to,
      'region': ?regionId,
      'group': ?groupId,
      'pdv': ?pdvId,
      'seller': ?sellerId,
      'product': ?productId,
      'family': ?family,
      if (sort != Metric.units) 'sort': sort.name,
    },
  ).toString();

  @override
  bool operator ==(Object other) =>
      other is Lens &&
      other.from == from &&
      other.to == to &&
      other.regionId == regionId &&
      other.groupId == groupId &&
      other.pdvId == pdvId &&
      other.sellerId == sellerId &&
      other.productId == productId &&
      other.family == family &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    from,
    to,
    regionId,
    groupId,
    pdvId,
    sellerId,
    productId,
    family,
    sort,
  );
}

/// The periods offered as one tap; anything else is a custom range.
enum PeriodPreset {
  today,
  yesterday,
  last7,
  last30,
  thisMonth,
  lastMonth,
  last90;

  ({String from, String to}) range([String? today]) {
    final end = today ?? tunisToday();
    final d = Dates.parseDay(end);
    return switch (this) {
      PeriodPreset.today => (from: end, to: end),
      PeriodPreset.yesterday => (from: _shift(end, -1), to: _shift(end, -1)),
      PeriodPreset.last7 => (from: _shift(end, -6), to: end),
      PeriodPreset.last30 => (from: _shift(end, -29), to: end),
      PeriodPreset.thisMonth => (from: '${end.substring(0, 8)}01', to: end),
      PeriodPreset.lastMonth => (
        from: Dates.day(DateTime(d.year, d.month - 1)),
        to: Dates.day(DateTime(d.year, d.month, 0)),
      ),
      PeriodPreset.last90 => (from: _shift(end, -89), to: end),
    };
  }

  static PeriodPreset? of(Lens lens) {
    for (final p in PeriodPreset.values) {
      final r = p.range();
      if (r.from == lens.from && r.to == lens.to) return p;
    }
    return null;
  }
}
