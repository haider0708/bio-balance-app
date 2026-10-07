import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
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

/// A decision the admin already took.
class HistoryItem {
  const HistoryItem({
    required this.type,
    required this.id,
    required this.name,
    required this.outcome,
    required this.decidedAt,
    this.decidedBy,
    this.region,
    this.note,
  });

  factory HistoryItem.fromJson(Json j) => HistoryItem(
    type: ApprovalType.parse(j.str('type')),
    id: j.str('id'),
    name: j.str('name'),
    outcome: j.str('outcome'),
    decidedAt: j.date('decidedAt'),
    decidedBy: j.strOrNull('decidedBy'),
    region: j.strOrNull('region'),
    note: j.strOrNull('note'),
  );

  final ApprovalType type;
  final String id;
  final String name;

  /// APPROVED, REJECTED or DEACTIVATED.
  final String outcome;
  final DateTime decidedAt;
  final String? decidedBy;
  final String? region;
  final String? note;
}

class HistoryPage {
  const HistoryPage(this.items, this.next);

  final List<HistoryItem> items;
  final String? next;
}

Future<HistoryPage> fetchApprovalHistory(
  ApiClient client, {
  String? before,
  ApprovalType? type,
}) async {
  final data = await client.get(
    '/v1/approvals/history',
    query: {'before': before, 'type': type?.wire},
  ) as Json;
  return HistoryPage(
    data.list('items').map(HistoryItem.fromJson).toList(),
    data.strOrNull('nextBefore'),
  );
}
