import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/dashboard_widgets.dart' show StockAttentionTile;
import 'reports_repository.dart';

/// Products that are nearly out, grouped by store so a long list stays readable.
class StockAttentionScreen extends ConsumerWidget {
  const StockAttentionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final rows = ref.watch(stockAttentionProvider);
    final canOrder = ref.watch(meProvider).role == Role.responsable;
    return Scaffold(
      appBar: AppBar(title: Text(t.needsAttention)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(stockAttentionProvider);
          await ref.read(stockAttentionProvider.future);
        },
        child: AsyncBody(
          value: rows,
          onRetry: () => ref.invalidate(stockAttentionProvider),
          isEmpty: (l) => l.isEmpty,
          empty: ListView(
            children: [
              EmptyState(icon: LucideIcons.circleCheck, title: t.stockAllGood),
            ],
          ),
          builder: (list) {
            final byStore = <String, List<AttentionRow>>{};
            for (final r in list) {
              byStore.putIfAbsent(r.locationId, () => []).add(r);
            }
            final stores = byStore.values.toList()
              ..sort((a, b) {
                final outA = a.where((r) => r.quantity <= 0).length;
                final outB = b.where((r) => r.quantity <= 0).length;
                return outB != outA ? outB - outA : b.length - a.length;
              });
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: stores.length,
              separatorBuilder: (_, _) => const Gap(8),
              itemBuilder: (context, i) => _StoreGroup(
                rows: stores[i],
                canOrder: canOrder,
                startOpen: i == 0,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StoreGroup extends StatefulWidget {
  const _StoreGroup({
    required this.rows,
    required this.canOrder,
    required this.startOpen,
  });

  final List<AttentionRow> rows;
  final bool canOrder;
  final bool startOpen;

  @override
  State<_StoreGroup> createState() => _StoreGroupState();
}

class _StoreGroupState extends State<_StoreGroup> {
  late bool _open = widget.startOpen;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final out = widget.rows.where((r) => r.quantity <= 0).length;
    final low = widget.rows.length - out;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(LucideIcons.store),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.rows.first.place,
                          style: context.text.titleSmall,
                        ),
                        Text(
                          [
                            if (low > 0) t.almostOutCount(low),
                            if (out > 0) t.outCount(out),
                          ].join(' · '),
                          style: context.text.bodySmall?.copyWith(
                            color: context.status.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 18,
                    color: context.status.muted,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Column(
                children: [
                  for (final r in widget.rows)
                    StockAttentionTile(row: r, canOrder: widget.canOrder),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
