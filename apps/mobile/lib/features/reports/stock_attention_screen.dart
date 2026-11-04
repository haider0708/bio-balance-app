import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/list_tools.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/dashboard_widgets.dart' show StockAttentionTile;
import 'reports_repository.dart';

/// Products that are nearly out, grouped by store so a long list stays readable.
class StockAttentionScreen extends ConsumerStatefulWidget {
  const StockAttentionScreen({super.key});

  @override
  ConsumerState<StockAttentionScreen> createState() =>
      _StockAttentionScreenState();
}

class _StockAttentionScreenState extends ConsumerState<StockAttentionScreen> {
  String _query = '';
  int _show = 0;
  bool _byPieces = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final rows = ref.watch(stockAttentionProvider);
    final canOrder = ref.watch(meProvider).role == Role.responsable;
    return Scaffold(
      appBar: AppBar(title: Text(t.needsAttention)),
      body: Column(
        children: [
          ListToolbar(
            hint: t.searchStockAttention,
            onSearch: (v) => setState(() => _query = v),
            sort: SortMenu<bool>(
              value: _byPieces,
              onChanged: (v) => setState(() => _byPieces = v),
              options: [(false, t.sortMostUrgent), (true, t.sortPiecesLeast)],
            ),
            chips: FilterChips<int>(
              value: _show,
              onChanged: (v) => setState(() => _show = v ?? 0),
              options: [(0, t.all), (1, t.outOfStock), (2, t.stockLow)],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
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
                    EmptyState(
                      icon: LucideIcons.circleCheck,
                      title: t.stockAllGood,
                    ),
                  ],
                ),
                builder: (all) {
                  final list = all
                      .where(
                        (r) => switch (_show) {
                          1 => r.quantity <= 0,
                          2 => r.quantity > 0,
                          _ => true,
                        },
                      )
                      .where(
                        (r) => matchesSearch(_query, [
                          r.place,
                          r.product,
                          r.family,
                        ]),
                      )
                      .toList();
                  if (list.isEmpty) {
                    return ListView(
                      children: [
                        EmptyState(
                          icon: LucideIcons.search,
                          title: t.noResults,
                        ),
                      ],
                    );
                  }
                  final byStore = <String, List<AttentionRow>>{};
                  for (final r in list) {
                    byStore.putIfAbsent(r.locationId, () => []).add(r);
                  }
                  final stores = byStore.values.toList()
                    ..sort((a, b) {
                      if (_byPieces) {
                        final fewestA = a
                            .map((r) => r.quantity)
                            .reduce((x, y) => x < y ? x : y);
                        final fewestB = b
                            .map((r) => r.quantity)
                            .reduce((x, y) => x < y ? x : y);
                        return fewestA.compareTo(fewestB);
                      }
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
          ),
        ],
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
