import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/json.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/util/money.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import 'analytics_repository.dart';
import 'analytics_widgets.dart';
import 'lens.dart';
import 'lens_bar.dart';

enum _Show { all, selling, silent, pending, lowStock }

enum _Order { units, change, lastSale, name }

/// Every point of sale of the scope side by side, selling or not: units, trend, team, last sale
/// and stock alerts. The silent ones are one tap away. Each row opens the store's analytics.
class StoresBoardScreen extends ConsumerStatefulWidget {
  const StoresBoardScreen({
    required this.from,
    required this.to,
    this.regionId,
    this.groupId,
    this.silentOnly = false,
    super.key,
  });

  factory StoresBoardScreen.fromQuery(Map<String, String> q) {
    final lens = Lens.fromQuery(q);
    return StoresBoardScreen(
      from: lens.from,
      to: lens.to,
      regionId: lens.regionId,
      groupId: lens.groupId,
      silentOnly: q['show'] == 'silent',
    );
  }

  final String from;
  final String to;
  final String? regionId;
  final String? groupId;
  final bool silentOnly;

  @override
  ConsumerState<StoresBoardScreen> createState() => _StoresBoardScreenState();
}

class _StoresBoardScreenState extends ConsumerState<StoresBoardScreen> {
  late String _from = widget.from;
  late String _to = widget.to;
  late _Show _show = widget.silentOnly ? _Show.silent : _Show.all;
  _Order _order = _Order.units;
  String _query = '';

  StoresQuery get _q => (
    from: _from,
    to: _to,
    regionId: widget.regionId,
    groupId: widget.groupId,
  );

  bool _keep(Json r) {
    final active = r.str('status') == 'ACTIVE';
    final ok = switch (_show) {
      _Show.all => true,
      _Show.selling => active && r.integer('units') > 0,
      _Show.silent => active && r.integer('units') == 0,
      _Show.pending => r.str('status') == 'PENDING',
      _Show.lowStock => active && r.integer('low') + r.integer('out') > 0,
    };
    if (!ok) return false;
    if (_query.isEmpty) return true;
    return [
      r.str('name'),
      r.str('city'),
      r.str('region'),
      r.str('group'),
    ].any((s) => s.toLowerCase().contains(_query));
  }

  int _compare(Json a, Json b) => switch (_order) {
    _Order.units => b.integer('units').compareTo(a.integer('units')),
    _Order.change => (a['change'] as int? ?? 1 << 30).compareTo(
      b['change'] as int? ?? 1 << 30,
    ),
    _Order.lastSale => (a.dateOrNull('lastSaleAt') ?? DateTime(2000)).compareTo(
      b.dateOrNull('lastSaleAt') ?? DateTime(2000),
    ),
    _Order.name =>
      a.str('name').toLowerCase().compareTo(b.str('name').toLowerCase()),
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final data = ref.watch(storesBoardProvider(_q));
    return Scaffold(
      appBar: AppBar(
        title: Text(t.storesBoardTitle),
        actions: [
          PopupMenuButton<_Order>(
            tooltip: t.sortBy,
            icon: const Icon(LucideIcons.arrowDownUp),
            initialValue: _order,
            onSelected: (o) => setState(() => _order = o),
            itemBuilder: (_) => [
              for (final (o, label) in [
                (_Order.units, t.sortUnits),
                (_Order.change, t.sortChange),
                (_Order.lastSale, t.sortLastSale),
                (_Order.name, t.sortName),
              ])
                CheckedPopupMenuItem(
                  value: o,
                  checked: _order == o,
                  child: Text(label),
                ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(storesBoardProvider(_q));
          await ref.read(storesBoardProvider(_q).future);
        },
        child: AsyncBody(
          value: data,
          onRetry: () => ref.invalidate(storesBoardProvider(_q)),
          builder: (d) {
            final s = d.obj('summary');
            final rows = d.list('rows').where(_keep).toList()..sort(_compare);
            final top = d
                .list('rows')
                .fold<int>(
                  1,
                  (m, r) => r.integer('units') > m ? r.integer('units') : m,
                );
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
              children: [
                PeriodChips(
                  from: _from,
                  to: _to,
                  onChanged: (from, to) => setState(() {
                    _from = from;
                    _to = to;
                  }),
                ),
                const Gap(8),
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(LucideIcons.search),
                    hintText: t.searchStores,
                  ),
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
                const Gap(8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (show, label) in [
                        (_Show.all, t.boardAll(s.integer('total'))),
                        (_Show.selling, t.boardSelling(s.integer('selling'))),
                        (_Show.silent, t.boardSilent(s.integer('silent'))),
                        (
                          _Show.lowStock,
                          t.boardLowStock(s.integer('lowStock')),
                        ),
                        (_Show.pending, t.boardPending(s.integer('pending'))),
                      ])
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: FilterChip(
                            label: Text(label),
                            selected: _show == show,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _show = show),
                          ),
                        ),
                    ],
                  ),
                ),
                const Gap(8),
                if (rows.isEmpty)
                  EmptyState(icon: LucideIcons.store, title: t.noResults)
                else
                  AutoGrid(
                    minItemWidth: 420,
                    maxColumns: 2,
                    spacing: 10,
                    children: [
                      for (final r in rows)
                        _StoreRow(
                          row: r,
                          top: top,
                          onTap: () => context.push(
                            Lens(
                              from: _from,
                              to: _to,
                              pdvId: r.str('id'),
                            ).location(),
                          ),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StoreRow extends StatelessWidget {
  const _StoreRow({required this.row, required this.top, required this.onTap});

  final Json row;
  final int top;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final status = row.str('status');
    final units = row.integer('units');
    final last = row.dateOrNull('lastSaleAt');
    final silent = status == 'ACTIVE' && units == 0;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                LucideIcons.store,
                size: 38,
                tone: silent ? Tone.warning : Tone.neutral,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.str('name'),
                      style: context.text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        row.str('city'),
                        if (row.strOrNull('group') != null) row.str('group'),
                        row.str('region'),
                      ].join(' · '),
                      style: context.text.bodySmall?.copyWith(
                        color: context.status.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(t.units(units), style: context.text.titleSmall),
                  ChangeBadge(row['change'] as int?, compact: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: units / top,
              minHeight: 5,
              backgroundColor: context.status.mutedSoft,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (status == 'PENDING')
                StatusChip(t.statusPending, tone: Tone.warning)
              else if (status == 'SUSPENDED')
                StatusChip(t.statusSuspended)
              else if (silent)
                StatusChip(t.boardNoSale, tone: Tone.warning),
              StatusChip(
                t.teamCount(row.integer('members')),
                icon: LucideIcons.users,
                tone: Tone.info,
              ),
              if (row.integer('sales') > 0)
                StatusChip(
                  '${t.salesCount(row.integer('sales'))} · ${Money.format(row.integer('rewardMillimes'), t.localeName)}',
                  icon: LucideIcons.receipt,
                  tone: Tone.neutral,
                ),
              if (row.integer('out') > 0)
                StatusChip(t.outCount(row.integer('out')), tone: Tone.danger),
              if (row.integer('low') > 0)
                StatusChip(
                  t.almostOutCount(row.integer('low')),
                  tone: Tone.warning,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            last == null
                ? t.neverSold
                : t.lastSaleOn(Dates.dateTime(last, t.localeName)),
            style: context.text.labelSmall?.copyWith(
              color: context.status.muted,
            ),
          ),
        ],
      ),
    );
  }
}
