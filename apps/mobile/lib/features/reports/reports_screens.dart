import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/files/files.dart';

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
import '../dashboard/dashboard_widgets.dart' show StockAttentionTile;
import '../dashboard/trend_chart.dart';
import 'reports_insights.dart';
import '../media/media_repository.dart';
import '../network/network_repository.dart';
import 'reports_repository.dart';

enum _Period { week, month, lastMonth, custom }

/// A narrowing of the report picked by tapping a row: this store, this product, this seller.
class _Focus {
  const _Focus(this.kind, this.key, this.label);

  final String kind;
  final String key;
  final String label;
}

/// Sales over a period: totals against the period before, a daily chart and a ranking
/// you can tap to look closer. A spreadsheet export is one tap away.
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
  final List<_Focus> _focus = [];

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

  String? _focused(String kind) =>
      _focus.where((f) => f.kind == kind).firstOrNull?.key;

  InsightsQuery get _insightsQuery =>
      (from: _range.from, to: _range.to, regionId: _regionId);

  ReportQuery get _query => (
    from: _range.from,
    to: _range.to,
    groupBy: _groupBy,
    regionId: _regionId,
    pdvId: _focused('pdv'),
    sellerId: _focused('seller'),
    productId: _focused('product'),
    family: _focused('family'),
  );

  Future<void> _export() async {
    final t = AppLocalizations.of(context);
    await perform(context, () async {
      final bytes = await ref
          .read(reportsRepositoryProvider)
          .csv(from: _range.from, to: _range.to, regionId: _regionId);
      await exportFile(
        'biobalance-sales-${_range.from}-${_range.to}.csv',
        bytes,
        'text/csv',
        subject: t.reportsTitle,
      );
    });
  }

  /// Tapping a row narrows the report to it and shows the next level down.
  void _drill(ReportRow row) {
    final kind = switch (_groupBy) {
      'pdv' => 'pdv',
      'product' => 'product',
      'seller' => 'seller',
      'family' => 'family',
      'region' => 'region',
      _ => null,
    };
    if (kind == null) return;
    setState(() {
      if (kind == 'region') {
        _regionId = row.key;
        _groupBy = 'pdv';
        return;
      }
      _focus.add(_Focus(kind, row.key, row.label));
      _groupBy = switch (kind) {
        'pdv' => 'seller',
        'seller' => 'product',
        'family' => 'product',
        _ => 'day',
      };
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
      ('pdv', t.byPdv),
      ('product', t.byProductShort),
      ('family', t.byFamily),
      ('seller', t.bySeller),
      ('day', t.byDay),
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
      body: DefaultTabController(
        length: 6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (p, label) in [
                          (_Period.week, t.last7Days),
                          (_Period.month, t.thisMonth),
                          (_Period.lastMonth, t.lastMonth),
                          (_Period.custom, t.customPeriod),
                        ])
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: ChoiceChip(
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
                          ),
                      ],
                    ),
                  ),
                  if (admin) ...[
                    const Gap(4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: ChoiceChip(
                              label: Text(t.allRegions),
                              selected: _regionId == null,
                              onSelected: (_) =>
                                  setState(() => _regionId = null),
                            ),
                          ),
                          for (final r in regions)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 8),
                              child: ChoiceChip(
                                label: Text(r.name),
                                selected: _regionId == r.id,
                                onSelected: (_) =>
                                    setState(() => _regionId = r.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: t.reportOverview),
                Tab(text: t.tabPdvs),
                Tab(text: t.reportProducts),
                Tab(text: t.reportTeam),
                Tab(text: t.reportStock),
                Tab(text: t.reportDetails),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  InsightsOverview(range: _insightsQuery),
                  InsightsStores(range: _insightsQuery),
                  InsightsProducts(range: _insightsQuery),
                  InsightsTeam(range: _insightsQuery),
                  InsightsStock(range: _insightsQuery),
                  RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(salesReportProvider(_query));
                      await ref.read(salesReportProvider(_query).future);
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      children: [
                        if (_focus.isNotEmpty) ...[
                          const Gap(4),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final f in _focus)
                                InputChip(
                                  label: Text(f.label),
                                  onDeleted: () => setState(() {
                                    final i = _focus.indexOf(f);
                                    _focus.removeRange(i, _focus.length);
                                    _groupBy = switch (f.kind) {
                                      'pdv' => 'pdv',
                                      'seller' => 'seller',
                                      'family' => 'family',
                                      _ => 'product',
                                    };
                                  }),
                                ),
                            ],
                          ),
                        ],
                        const Gap(8),
                        AsyncBody(
                          value: report,
                          onRetry: () =>
                              ref.invalidate(salesReportProvider(_query)),
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
                                      child: _Metric(
                                        label: t.totalUnits,
                                        value: '${r.units}',
                                        change: SalesReport.change(
                                          r.units,
                                          r.previousUnits,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _Metric(
                                        label: t.reward,
                                        value: Money.format(
                                          r.rewardMillimes,
                                          t.localeName,
                                          unit: false,
                                        ),
                                        hint: 'TND',
                                        change: SalesReport.change(
                                          r.rewardMillimes,
                                          r.previousRewardMillimes,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _Metric(
                                        label: t.salesTitleShort,
                                        value: '${r.sales}',
                                      ),
                                    ),
                                  ],
                                ),
                                if (r.trend.isNotEmpty &&
                                    r.trend.length <= 62) ...[
                                  const Gap(12),
                                  AppCard(child: TrendChart(days: r.trend)),
                                ],
                                const Gap(12),
                                SizedBox(
                                  height: 44,
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    children: [
                                      for (final (value, label) in groups)
                                        Padding(
                                          padding:
                                              const EdgeInsetsDirectional.only(
                                                end: 8,
                                              ),
                                          child: FilterChip(
                                            label: Text(
                                              '${t.groupedBy} $label',
                                            ),
                                            selected: _groupBy == value,
                                            showCheckmark: false,
                                            onSelected: (_) => setState(
                                              () => _groupBy = value,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const Gap(4),
                                if (r.rows.isEmpty)
                                  EmptyState(
                                    icon: LucideIcons.chartNoAxesColumn,
                                    title: t.noSalesInPeriod,
                                  )
                                else
                                  for (var i = 0; i < r.rows.length; i++)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _ReportRowCard(
                                        row: r.rows[i],
                                        rank: _groupBy == 'day' ? null : i + 1,
                                        top: top,
                                        product: _groupBy == 'product',
                                        onTap: _groupBy == 'day'
                                            ? null
                                            : () => _drill(r.rows[i]),
                                      ),
                                    ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.hint,
    this.change,
  });

  final String label;
  final String value;
  final String? hint;
  final int? change;

  @override
  Widget build(BuildContext context) {
    final up = (change ?? 0) >= 0;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.bodySmall?.copyWith(
              color: context.status.muted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, style: context.text.headlineSmall),
          ),
          if (hint != null)
            Text(
              hint!,
              style: context.text.labelSmall?.copyWith(
                color: context.status.muted,
              ),
            ),
          if (change != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  up ? LucideIcons.trendingUp : LucideIcons.trendingDown,
                  size: 14,
                  color: up ? context.status.success : context.status.danger,
                ),
                const SizedBox(width: 4),
                Text(
                  '${up ? '+' : ''}$change %',
                  style: context.text.labelMedium?.copyWith(
                    color: up ? context.status.success : context.status.danger,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportRowCard extends StatelessWidget {
  const _ReportRowCard({
    required this.row,
    required this.top,
    required this.product,
    this.rank,
    this.onTap,
  });

  final ReportRow row;
  final int top;
  final bool product;
  final int? rank;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          if (rank != null)
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                style: context.text.titleSmall?.copyWith(
                  color: rank == 1
                      ? context.colors.primary
                      : context.status.muted,
                ),
              ),
            ),
          if (product) ...[
            AuthImage(
              row.imageId,
              width: 44,
              height: 44,
              radius: 10,
              placeholderIcon: LucideIcons.package,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: context.text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: top == 0 ? 0 : row.units / top,
                    minHeight: 5,
                    backgroundColor: context.status.mutedSoft,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${t.salesCount(row.sales)} · ${Money.format(row.rewardMillimes, t.localeName)}',
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(t.units(row.units), style: context.text.titleSmall),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: context.status.muted,
            ),
          ],
        ],
      ),
    );
  }
}

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
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
