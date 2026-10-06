import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/util/money.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../network/network_repository.dart';
import 'reports_repository.dart';

enum _Period { week, month, lastMonth, custom }

/// Sales over a period, grouped the way you need, with a spreadsheet export.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Period _period = _Period.month;
  String _groupBy = 'pdv';
  String? _regionId;
  DateTimeRange? _custom;

  ({String from, String to}) get _range {
    final now = DateTime.now();
    return switch (_period) {
      _Period.week => (
        from: Dates.day(now.subtract(const Duration(days: 6))),
        to: Dates.day(now),
      ),
      _Period.month => (
        from: Dates.day(DateTime(now.year, now.month)),
        to: Dates.day(now),
      ),
      _Period.lastMonth => (
        from: Dates.day(DateTime(now.year, now.month - 1)),
        to: Dates.day(DateTime(now.year, now.month, 0)),
      ),
      _Period.custom => (
        from: Dates.day(_custom?.start ?? now),
        to: Dates.day(_custom?.end ?? now),
      ),
    };
  }

  ReportQuery get _query => (
    from: _range.from,
    to: _range.to,
    groupBy: _groupBy,
    regionId: _regionId,
  );

  Future<void> _export() async {
    final t = AppLocalizations.of(context);
    await perform(context, () async {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/biobalance-sales-${_range.from}-${_range.to}.csv';
      await ref
          .read(reportsRepositoryProvider)
          .downloadCsv(
            from: _range.from,
            to: _range.to,
            regionId: _regionId,
            path: path,
          );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'text/csv')],
          subject: t.reportsTitle,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final admin = me.role == Role.admin;
    final report = ref.watch(salesReportProvider(_query));
    final regions = ref.watch(regionsProvider).value ?? const [];
    final groups = [
      ('day', t.byDay),
      ('pdv', t.byPdv),
      ('product', t.byProductShort),
      ('family', t.byFamily),
      ('seller', t.bySeller),
      if (admin) ('region', t.byRegion),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsTitle),
        actions: [
          IconButton(
            tooltip: t.exportCsv,
            icon: const Icon(LucideIcons.share),
            onPressed: _export,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(salesReportProvider(_query));
          await ref.read(salesReportProvider(_query).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (p, label) in [
                  (_Period.week, t.last7Days),
                  (_Period.month, t.thisMonth),
                  (_Period.lastMonth, t.lastMonth),
                  (_Period.custom, t.customPeriod),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _period == p,
                    onSelected: (_) async {
                      if (p == _Period.custom) {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2026),
                          lastDate: DateTime.now(),
                          initialDateRange: _custom,
                        );
                        if (picked == null) return;
                        _custom = picked;
                      }
                      setState(() => _period = p);
                    },
                  ),
              ],
            ),
            const Gap(8),
            if (admin)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: Text(t.allRegions),
                    selected: _regionId == null,
                    onSelected: (_) => setState(() => _regionId = null),
                  ),
                  for (final r in regions)
                    ChoiceChip(
                      label: Text(r.name),
                      selected: _regionId == r.id,
                      onSelected: (_) => setState(() => _regionId = r.id),
                    ),
                ],
              ),
            const Gap(8),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (value, label) in groups)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: FilterChip(
                        label: Text('${t.groupedBy} $label'),
                        selected: _groupBy == value,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _groupBy = value),
                      ),
                    ),
                ],
              ),
            ),
            const Gap(8),
            AsyncBody(
              value: report,
              onRetry: () => ref.invalidate(salesReportProvider(_query)),
              builder: (r) {
                final top = r.rows.fold<int>(
                  0,
                  (m, e) => e.units > m ? e.units : m,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: t.salesTitleShort,
                            value: '${r.sales}',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatTile(
                            label: t.totalUnits,
                            value: '${r.units}',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatTile(
                            label: t.reward,
                            value: Money.format(
                              r.rewardMillimes,
                              t.localeName,
                              unit: false,
                            ),
                            hint: 'TND',
                          ),
                        ),
                      ],
                    ),
                    const Gap(12),
                    if (r.rows.isEmpty)
                      EmptyState(
                        icon: LucideIcons.chartNoAxesColumn,
                        title: t.noSalesInPeriod,
                      )
                    else
                      for (final row in r.rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        row.label,
                                        style: context.text.titleSmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      t.units(row.units),
                                      style: context.text.titleSmall,
                                    ),
                                  ],
                                ),
                                const Gap(8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: LinearProgressIndicator(
                                    value: top == 0 ? 0 : row.units / top,
                                    minHeight: 6,
                                    backgroundColor: context.status.mutedSoft,
                                  ),
                                ),
                                const Gap(6),
                                Text(
                                  '${t.salesCount(row.sales)} · ${Money.format(row.rewardMillimes, t.localeName)}',
                                  style: context.text.bodySmall?.copyWith(
                                    color: context.status.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Products that are nearly out or below zero, at each place.
class StockAttentionScreen extends ConsumerWidget {
  const StockAttentionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final rows = ref.watch(stockAttentionProvider);
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
          builder: (list) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Gap(8),
            itemBuilder: (context, i) {
              final r = list[i];
              final negative = r.quantity < 0;
              return AppCard(
                onTap: () =>
                    context.push('/stock/${r.locationId}', extra: r.place),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.product, style: context.text.titleSmall),
                          Text(
                            '${r.place} · ${r.family}',
                            style: context.text.bodySmall?.copyWith(
                              color: context.status.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(
                      '${r.quantity}',
                      tone: negative ? Tone.danger : Tone.warning,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
