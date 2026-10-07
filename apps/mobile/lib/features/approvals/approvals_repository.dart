import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';

/// Kinds of thing waiting for the admin.
enum ApprovalType {
  group('GROUP'),
  pdv('PDV'),
  member('MEMBER'),
  stock('STOCK'),
  receipt('RECEIPT'),
  restockRequest('RESTOCK_REQUEST'),
  payout('PAYOUT'),
  recount('RECOUNT');

  const ApprovalType(this.wire);
  final String wire;

  static ApprovalType parse(String v) => ApprovalType.values.firstWhere(
    (t) => t.wire == v,
    orElse: () => ApprovalType.pdv,
  );
}

class ApprovalItem {
  const ApprovalItem({
    required this.type,
    required this.id,
    required this.name,
    required this.createdAt,
    this.by,
    this.region,
    this.regionId,
    this.meta = const {},
  });

  factory ApprovalItem.fromJson(Json j) => ApprovalItem(
    type: ApprovalType.parse(j.str('type')),
    id: j.str('id'),
    name: j.str('name'),
    by: j.strOrNull('by'),
    region: j.strOrNull('region'),
    regionId: j.strOrNull('regionId'),
    createdAt: j.date('createdAt'),
    meta: j.obj('meta'),
  );

  final ApprovalType type;
  final String id;
  final String name;
  final String? by;
  final String? region;
  final String? regionId;
  final DateTime createdAt;
  final Json meta;
}

class Approvals {
  const Approvals({required this.counts, required this.items});

  factory Approvals.fromJson(Json j) => Approvals(
    counts: {
      for (final t in ApprovalType.values) t: j.obj('counts').integer(t.wire),
    },
    items: j.list('items').map(ApprovalItem.fromJson).toList(),
  );

  final Map<ApprovalType, int> counts;
  final List<ApprovalItem> items;

  int get total => counts.values.fold(0, (a, b) => a + b);
}

final approvalsProvider = FutureProvider.autoDispose.family<Approvals, String?>(
  (ref, regionId) async => Approvals.fromJson(
    await ref
            .watch(apiClientProvider)
            .get('/v1/approvals', query: {'regionId': regionId})
        as Json,
  ),
);
