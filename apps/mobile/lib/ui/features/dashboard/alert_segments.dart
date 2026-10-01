import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../../core/segment_bar.dart';

/// The alerts of a store, grouped by what they are about instead of one long list.
class AlertSegments extends StatefulWidget {
  final List<Json> alerts;
  final void Function(Json)? onAlert;
  const AlertSegments({super.key, required this.alerts, this.onAlert});
  @override
  State<AlertSegments> createState() => _AlertSegmentsState();
}

class _AlertSegmentsState extends State<AlertSegments> {
  static const _order = ['stock', 'expiry', 'orders', 'check'];
  static const _labels = {
    'stock': ('Stock', AppIcons.inventory2Outlined),
    'expiry': ('Péremption', AppIcons.schedule),
    'orders': ('Livraisons', AppIcons.localShippingOutlined),
    'check': ('Écarts', AppIcons.infoOutline),
  };
  static const _preview = 5;
  String? chosen;
  bool all = false;

  static String segmentOf(Json alert) => switch (alert['kind']) {
    'low' || 'zero' => 'stock',
    'expired' || 'expiring' => 'expiry',
    'order_problem' || 'delivery_issue' => 'orders',
    _ => 'check',
  };

  @override
  Widget build(BuildContext context) {
    final bySegment = {for (final k in _order) k: <Json>[]};
    for (final a in widget.alerts) {
      bySegment[segmentOf(a)]!.add(a);
    }
    // The first segment that has something to do is open by default.
    final current = chosen != null && bySegment[chosen]!.isNotEmpty
        ? chosen!
        : _order.firstWhere(
            (k) => bySegment[k]!.isNotEmpty,
            orElse: () => _order.first,
          );
    final items = bySegment[current]!;
    final shown = all ? items : items.take(_preview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentBar(
          keyPrefix: 'alerts',
          selected: current,
          onChanged: (v) => setState(() {
            chosen = v;
            all = false;
          }),
          segments: {
            for (final k in _order)
              if (bySegment[k]!.isNotEmpty)
                k: Segment(
                  _labels[k]!.$1,
                  _labels[k]!.$2,
                  bySegment[k]!.length,
                ),
          },
        ),
        const SizedBox(height: 8),
        for (final alert in shown)
          CompactRow(
            key: ValueKey(alert['id']),
            title: alert['message'],
            subtitle: alert['storeName'],
            icon: AppIcons.infoOutline,
            tone: alert['kind'] == 'zero' || alert['kind'] == 'expired'
                ? AppTone.danger
                : AppTone.warning,
            onTap: widget.onAlert == null ? null : () => widget.onAlert!(alert),
          ),
        if (items.length > _preview && !all)
          TextButton(
            onPressed: () => setState(() => all = true),
            child: Text('Voir les ${items.length}'),
          ),
      ],
    );
  }
}
