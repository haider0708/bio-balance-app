import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/json.dart';
import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/files/files.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/util/money.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../catalog/catalog_repository.dart';
import '../media/media_repository.dart';
import '../sales/sales_history_screen.dart' show SaleTile;
import 'analytics_repository.dart';
import 'analytics_widgets.dart';
import 'lens.dart';
import 'lens_bar.dart';

/// The answer to a lens: the headline numbers against the period before, the curve, when people
/// buy, who, where and what makes the numbers, the stock it leaves, the money it owes and the
/// sales themselves. Every number and row opens the next, narrower question.
class ExplorerScreen extends ConsumerStatefulWidget {
  const ExplorerScreen({required this.lens, this.root = false, super.key});

  /// The Reports page: the whole scope of the person, starting with this month.
  ExplorerScreen.root({super.key}) : lens = Lens.thisMonth(), root = true;

  final Lens lens;
  final bool root;

  @override
  ConsumerState<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends ConsumerState<ExplorerScreen> {
  late Lens _lens = widget.lens;

  /// The previous answer, kept on screen while a changed lens loads, so nothing flashes.
  Json? _shown;

  @override
  void didUpdateWidget(ExplorerScreen old) {
    super.didUpdateWidget(old);
    if (old.lens != widget.lens) _lens = widget.lens;
  }

  void _set(Lens lens) => setState(() => _lens = lens);

  void _open(Lens lens) => context.push(lens.location());

  Future<void> _export() async {
    final t = AppLocalizations.of(context);
    await perform(context, () async {
      final bytes = await ref.read(analyticsRepositoryProvider).csv(_lens);
      await exportFile(
        'biobalance-sales-${_lens.from}-${_lens.to}.csv',
        bytes,
        'text/csv',
        subject: t.reportsTitle,
      );
    });
  }

  String _title(AppLocalizations t, Json? subject) {
    if (widget.root && _lens.facets.isEmpty) return t.reportsTitle;
    final s = subject ?? const <String, dynamic>{};
    return s.objOrNull('seller')?.str('name') ??
        s.objOrNull('product')?.str('name') ??
        s.objOrNull('pdv')?.str('name') ??
        s.objOrNull('group')?.str('name') ??
        s.strOrNull('family') ??
        s.objOrNull('region')?.str('name') ??
        t.analyticsTitle;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final async = ref.watch(analyticsProvider(_lens));
    if (async.hasValue) _shown = async.value;
    final data = async.value ?? _shown;
    final loading = async.isLoading;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(t, data?.objOrNull('subject'))),
        actions: [
          IconButton(
            tooltip: t.exportCsv,
            icon: const Icon(LucideIcons.fileSpreadsheet),
            onPressed: _export,
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 2,
            child: loading && data != null
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(analyticsProvider(_lens));
                ref.invalidate(
                  latestSalesProvider(_lens.copyWith(sort: Metric.units)),
                );
                await ref.read(analyticsProvider(_lens).future);
              },
              child: data == null
                  ? (async.hasError
                        ? ErrorState(
                            error: async.error!,
                            onRetry: () =>
                                ref.invalidate(analyticsProvider(_lens)),
                          )
                        : const LoadingState())
                  : _Answer(
                      lens: _lens,
                      data: data,
                      onChange: _set,
                      onOpen: _open,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Answer extends ConsumerWidget {
  const _Answer({
    required this.lens,
    required this.data,
    required this.onChange,
    required this.onOpen,
  });

  final Lens lens;
  final Json data;
  final ValueChanged<Lens> onChange;
  final ValueChanged<Lens> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final admin = ref.watch(meProvider).role == Role.admin;
    final totals = data.obj('totals');
    final before = data.obj('previousTotals');
    final change = data.obj('change');
    final subject = data.obj('subject');
    final breakdowns = data.obj('breakdowns');
    final metric = lens.sort;
    final totalOfMetric = metricOf(metric, totals);
    final empty = totals.integer('units') == 0;
    void narrow(Facet f, String id) => onOpen(lens.withFacet(f, id));
    final previous = data.obj('previous');
    final period =
        '${Dates.short(Dates.parseDay(previous.str('from')), t.localeName)} – '
        '${Dates.short(Dates.parseDay(previous.str('to')), t.localeName)}';

    final rankings = <Widget>[
      if (breakdowns.list('regions').isNotEmpty)
        RankingCard(
          title: t.anRegions,
          icon: LucideIcons.map,
          rows: breakdowns.list('regions'),
          metric: metric,
          total: totalOfMetric,
          onTap: (r) => narrow(Facet.region, r.str('id')),
        ),
      if (breakdowns.list('stores').isNotEmpty)
        RankingCard(
          title: t.anStores,
          icon: LucideIcons.store,
          rows: breakdowns.list('stores'),
          metric: metric,
          total: totalOfMetric,
          onTap: (r) => narrow(Facet.pdv, r.str('id')),
        ),
      if (breakdowns.list('products').isNotEmpty)
        RankingCard(
          title: t.anProducts,
          icon: LucideIcons.package,
          rows: breakdowns.list('products'),
          metric: metric,
          total: totalOfMetric,
          images: true,
          onTap: (r) => narrow(Facet.product, r.str('id')),
        ),
      if (breakdowns.list('sellers').isNotEmpty)
        RankingCard(
          title: t.anSellers,
          icon: LucideIcons.users,
          rows: breakdowns.list('sellers'),
          metric: metric,
          total: totalOfMetric,
          onTap: (r) => narrow(Facet.seller, r.str('id')),
        ),
      if (breakdowns.list('groups').isNotEmpty)
        RankingCard(
          title: t.anGroups,
          icon: LucideIcons.layers,
          rows: breakdowns.list('groups'),
          metric: metric,
          total: totalOfMetric,
          onTap: (r) => narrow(Facet.group, r.str('id')),
        ),
      if (breakdowns.list('families').isNotEmpty)
        RankingCard(
          title: t.anFamilies,
          icon: LucideIcons.tags,
          rows: breakdowns.list('families'),
          metric: metric,
          total: totalOfMetric,
          onTap: (r) => narrow(Facet.family, r.str('id')),
        ),
    ];

    final hours = data.list('hours');
    final active = [
      for (final h in hours)
        if (h.integer('units') > 0) h.integer('hour'),
    ];
    final firstHour = active.isEmpty
        ? 8
        : (active.first < 8 ? active.first : 8);
    final lastHour = active.isEmpty
        ? 20
        : (active.last > 20 ? active.last : 20);
    final placeLens = lens.pdvId != null || lens.sellerId != null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
      children: [
        LensBar(lens: lens, subject: subject, onChange: onChange),
        const Gap(12),
        SubjectCards(lens: lens, subject: subject),
        AutoGrid(
          minItemWidth: 150,
          maxColumns: 6,
          children: [
            KpiTile(
              icon: LucideIcons.package,
              label: t.kpiUnits,
              value: '${totals.integer('units')}',
              hint: t.vsPrevious(before.integer('units')),
              change: change.integerOrNull('units'),
              selected: metric == Metric.units,
              onTap: () => onChange(lens.copyWith(sort: Metric.units)),
            ),
            KpiTile(
              icon: LucideIcons.receipt,
              label: t.kpiSales,
              value: '${totals.integer('sales')}',
              hint: t.vsPrevious(before.integer('sales')),
              change: change.integerOrNull('sales'),
              selected: metric == Metric.sales,
              onTap: () => onChange(lens.copyWith(sort: Metric.sales)),
            ),
            KpiTile(
              icon: LucideIcons.banknote,
              label: t.kpiRewards,
              value: Money.format(
                totals.integer('rewardMillimes'),
                t.localeName,
                unit: false,
              ),
              hint: 'TND',
              change: change.integerOrNull('reward'),
              selected: metric == Metric.reward,
              onTap: () => onChange(lens.copyWith(sort: Metric.reward)),
            ),
            KpiTile(
              icon: LucideIcons.shoppingBasket,
              label: t.kpiPerSale,
              value: '${totals['unitsPerSale'] ?? 0}',
              hint: t.kpiProductsCount(totals.integer('products')),
            ),
            if (!placeLens)
              KpiTile(
                icon: LucideIcons.store,
                label: t.kpiStores,
                value: '${totals.integer('stores')}',
                hint:
                    totals.integerOrNull('silentStores') != null &&
                        totals.integer('silentStores') > 0
                    ? t.kpiSilent(totals.integer('silentStores'))
                    : null,
                onTap: () => context.push(storesBoardLocation(lens)),
              ),
            if (lens.sellerId == null)
              KpiTile(
                icon: LucideIcons.users,
                label: t.kpiSellers,
                value: '${totals.integer('sellers')}',
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Text(
            t.comparedWith(period),
            style: context.text.labelSmall?.copyWith(
              color: context.status.muted,
            ),
          ),
        ),
        _Quality(lens: lens, totals: totals),
        SectionHeader(
          switch (data.str('granularity')) {
            'hour' => t.chartByHour,
            'week' => t.chartByWeek,
            _ => t.chartByDay,
          },
          trailing: Text(
            metricLabel(t, metric),
            style: context.text.labelMedium?.copyWith(
              color: context.status.muted,
            ),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
          child: MetricChart(
            points: data.list('series'),
            metric: metric,
            granularity: data.str('granularity'),
            onTap: (p) {
              final from = p.str('key');
              if (data.str('granularity') == 'day') {
                onOpen(lens.copyWith(from: from, to: from));
              } else {
                final end = Dates.day(
                  Dates.parseDay(from).add(const Duration(days: 6)),
                );
                onOpen(
                  lens.copyWith(
                    from: from.compareTo(lens.from) < 0 ? lens.from : from,
                    to: end.compareTo(lens.to) > 0 ? lens.to : end,
                  ),
                );
              }
            },
          ),
        ),
        if (!empty) ...[
          const Gap(12),
          AutoGrid(
            minItemWidth: 320,
            maxColumns: 2,
            children: [
              if (!lens.isSingleDay)
                _Panel(
                  title: t.whenPeopleBuy,
                  child: PatternBars(
                    bars: [
                      for (var h = firstHour; h <= lastHour; h++)
                        (
                          label: h.toString().padLeft(2, '0'),
                          value: hours[h].integer('units'),
                        ),
                    ],
                  ),
                ),
              if (lens.days >= 7)
                _Panel(
                  title: t.byWeekday,
                  child: PatternBars(
                    bars: [
                      for (final dow in const [1, 2, 3, 4, 5, 6, 0])
                        (
                          label: weekdayName(dow, t.localeName),
                          value: data
                              .list('weekdays')
                              .firstWhere((w) => w.integer('weekday') == dow)
                              .integer('units'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (data.list('insights').isNotEmpty) ...[
          SectionHeader(t.whatTheNumbersSay),
          AutoGrid(
            minItemWidth: 340,
            maxColumns: 2,
            spacing: 8,
            children: [
              for (final i in data.list('insights'))
                InsightTile(
                  insight: i,
                  onTap: i.str('key') == 'SILENT_STORES'
                      ? () => context.push(
                          storesBoardLocation(lens, silentOnly: true),
                        )
                      : null,
                ),
            ],
          ),
        ],
        if (empty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: EmptyState(
              icon: LucideIcons.chartNoAxesColumn,
              title: t.noSalesInPeriod,
              message: t.noSalesInPeriodHint,
            ),
          ),
        if (rankings.isNotEmpty) ...[
          SectionHeader(t.anWhoWhereWhat),
          AutoGrid(minItemWidth: 400, maxColumns: 2, children: rankings),
        ],
        StockSection(
          lens: lens,
          stock: data.objOrNull('stock'),
          onOpen: onOpen,
        ),
        if (admin && data.objOrNull('money') != null)
          _MoneySection(money: data.obj('money')),
        _LatestSales(lens: lens, empty: empty),
        if (!placeLens) ...[
          const Gap(16),
          OutlinedButton.icon(
            onPressed: () => context.push(storesBoardLocation(lens)),
            icon: const Icon(LucideIcons.store),
            label: Text(t.allStoresBoard),
          ),
        ],
      ],
    );
  }
}

/// The address of the stores board for the places of a lens.
String storesBoardLocation(Lens lens, {bool silentOnly = false}) => Uri(
  path: '/explore/stores',
  queryParameters: {
    'from': lens.from,
    'to': lens.to,
    'region': ?lens.regionId,
    'group': ?lens.groupId,
    if (silentOnly) 'show': 'silent',
  },
).toString();

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.text.titleSmall),
        const Gap(12),
        child,
      ],
    ),
  );
}

/// Sales changed after the fact, shown so nothing is hidden: each opens the sales concerned.
class _Quality extends StatelessWidget {
  const _Quality({required this.lens, required this.totals});

  final Lens lens;
  final Json totals;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final voided = totals.integer('voided');
    final corrected = totals.integer('corrected');
    final late = totals.integer('late');
    if (voided + corrected + late == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (voided > 0)
            ActionChip(
              avatar: Icon(
                LucideIcons.ban,
                size: 16,
                color: context.status.danger,
              ),
              label: Text(t.qualityVoided(voided)),
              onPressed: () => context.push(
                '${lens.location('/explore/sales')}&show=voided',
              ),
            ),
          if (corrected > 0)
            ActionChip(
              avatar: Icon(
                LucideIcons.pencil,
                size: 16,
                color: context.status.info,
              ),
              label: Text(t.qualityCorrected(corrected)),
              onPressed: () => context.push(lens.location('/explore/sales')),
            ),
          if (late > 0)
            ActionChip(
              avatar: Icon(
                LucideIcons.cloudUpload,
                size: 16,
                color: context.status.muted,
              ),
              label: Text(t.qualityLate(late)),
              onPressed: () => context.push(lens.location('/explore/sales')),
            ),
        ],
      ),
    );
  }
}

/// Who and what the lens is about, with the way to its own page.
class SubjectCards extends ConsumerWidget {
  const SubjectCards({required this.lens, required this.subject, super.key});

  final Lens lens;
  final Json subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final admin = ref.watch(meProvider).role == Role.admin;
    final pdv = subject.objOrNull('pdv');
    final seller = subject.objOrNull('seller');
    final product = subject.objOrNull('product');
    final group = subject.objOrNull('group');
    final region = subject.objOrNull('region');
    final cards = <Widget>[
      if (seller != null)
        _SubjectCard(
          leading: Avatar(_initials(seller.str('name'))),
          title: seller.str('name'),
          lines: [
            [
              if (seller.strOrNull('pdv') != null) seller.str('pdv'),
              if (seller.strOrNull('region') != null) seller.str('region'),
            ].join(' · '),
            t.memberSince(Dates.full(seller.date('createdAt'), t.localeName)),
          ],
          status: seller.str('status'),
          actions: [
            if (seller.strOrNull('phone') != null)
              _Action(
                LucideIcons.phone,
                t.call,
                () => launchUrl(
                  Uri(
                    scheme: 'tel',
                    path: seller.str('phone').replaceAll(' ', ''),
                  ),
                ),
              ),
            if (seller.strOrNull('pdvId') != null && lens.pdvId == null)
              _Action(
                LucideIcons.store,
                t.facetStore,
                () => context.push(
                  lens
                      .withFacet(Facet.seller, null)
                      .withFacet(Facet.pdv, seller.str('pdvId'))
                      .location(),
                ),
              ),
          ],
        ),
      if (pdv != null)
        _SubjectCard(
          leading: const IconBadge(LucideIcons.store, size: 44),
          title: pdv.str('name'),
          lines: [
            [
              pdv.str('city'),
              if (pdv.strOrNull('group') != null) pdv.str('group'),
              pdv.str('region'),
            ].join(' · '),
            t.teamCount(pdv.integer('members')),
          ],
          status: pdv.str('status'),
          actions: [
            _Action(
              LucideIcons.externalLink,
              t.openStorePage,
              () => context.push('/pdvs/${pdv.str('id')}'),
            ),
            _Action(
              LucideIcons.boxes,
              t.stockTitle,
              () => context.push(
                '/stock/${pdv.str('id')}',
                extra: pdv.str('name'),
              ),
            ),
            if (pdv.strOrNull('phone') != null)
              _Action(
                LucideIcons.phone,
                t.call,
                () => launchUrl(
                  Uri(
                    scheme: 'tel',
                    path: pdv.str('phone').replaceAll(' ', ''),
                  ),
                ),
              ),
          ],
        ),
      if (product != null)
        _SubjectCard(
          leading: AuthImage(
            product.strOrNull('imageId'),
            width: 52,
            height: 52,
            placeholderIcon: LucideIcons.package,
          ),
          title: product.str('name'),
          lines: [
            [
              product.str('reference'),
              product.str('family'),
              if (product.str('packageSize').isNotEmpty)
                product.str('packageSize'),
            ].where((s) => s.isNotEmpty).join(' · '),
          ],
          status: product.flag('active') ? null : 'SUSPENDED',
          actions: [
            _Action(LucideIcons.bookOpen, t.openProductSheet, () async {
              final all = await ref.read(allProductsProvider.future);
              final p = all.where((p) => p.id == product.str('id')).firstOrNull;
              if (p != null && context.mounted) {
                await context.push('/catalog/${p.id}', extra: p);
              }
            }),
          ],
        ),
      if (group != null && pdv == null && seller == null)
        _SubjectCard(
          leading: const IconBadge(LucideIcons.layers, size: 44),
          title: group.str('name'),
          lines: [
            '${group.str('region')} · ${t.pdvCount(group.integer('stores'))}',
          ],
          status: group.str('status'),
          actions: [
            _Action(
              LucideIcons.store,
              t.allStoresBoard,
              () => context.push(storesBoardLocation(lens)),
            ),
          ],
        ),
      if (region != null &&
          admin &&
          pdv == null &&
          seller == null &&
          group == null)
        _SubjectCard(
          leading: const IconBadge(LucideIcons.map, size: 44),
          title: region.str('name'),
          lines: [t.facetRegion],
          actions: [
            _Action(
              LucideIcons.externalLink,
              t.openRegionPage,
              () => context.push(
                '/regions/${region.str('id')}',
                extra: region.str('name'),
              ),
            ),
          ],
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AutoGrid(minItemWidth: 340, maxColumns: 2, children: cards),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.isEmpty
      ? '?'
      : parts.take(2).map((p) => p[0].toUpperCase()).join();
}

class _Action {
  const _Action(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({
    required this.leading,
    required this.title,
    required this.lines,
    required this.actions,
    this.status,
  });

  final Widget leading;
  final String title;
  final List<String> lines;
  final List<_Action> actions;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final chip = switch (status) {
      'PENDING' => StatusChip(t.statusPending, tone: Tone.warning),
      'SUSPENDED' => StatusChip(t.statusSuspended),
      'REJECTED' => StatusChip(t.statusRejected, tone: Tone.danger),
      _ => null,
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleMedium),
                    for (final l in lines.where((l) => l.isNotEmpty))
                      Text(
                        l,
                        style: context.text.bodySmall?.copyWith(
                          color: context.status.muted,
                        ),
                      ),
                  ],
                ),
              ),
              ?chip,
            ],
          ),
          if (actions.isNotEmpty) ...[
            const Gap(10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final a in actions)
                  OutlinedButton.icon(
                    onPressed: a.onTap,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: Icon(a.icon, size: 16),
                    label: Text(a.label),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The stock behind the sales: where a product sits, what a store holds, or what runs out.
class StockSection extends StatefulWidget {
  const StockSection({
    required this.lens,
    required this.stock,
    required this.onOpen,
    super.key,
  });

  final Lens lens;
  final Json? stock;
  final ValueChanged<Lens> onOpen;

  @override
  State<StockSection> createState() => _StockSectionState();
}

class _StockSectionState extends State<StockSection> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final stock = widget.stock;
    if (stock == null) return const SizedBox.shrink();
    final lens = widget.lens;
    Widget more(int count) => count > 8
        ? TextButton.icon(
            onPressed: () => setState(() => _all = !_all),
            icon: Icon(
              _all ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 18,
            ),
            label: Text(_all ? t.seeLess : t.seeMore(count)),
          )
        : const SizedBox.shrink();
    switch (stock.str('kind')) {
      case 'product':
        final rows = stock.list('rows');
        final shown = _all ? rows : rows.take(8).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(t.stockWhere),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusChip(
                  t.stockInStores(stock.integer('total')),
                  icon: LucideIcons.store,
                  tone: Tone.info,
                ),
                StatusChip(
                  t.stockInGrossistes(stock.integer('inGrossistes')),
                  icon: LucideIcons.warehouse,
                  tone: Tone.neutral,
                ),
              ],
            ),
            const Gap(10),
            if (rows.isEmpty)
              AppCard(child: Text(t.stockNowhere))
            else
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  children: [
                    for (final r in shown)
                      _StockRow(
                        leading: Icon(
                          r.str('kind') == 'DEPOT'
                              ? LucideIcons.warehouse
                              : LucideIcons.store,
                          color: context.colors.primary,
                        ),
                        title: r.str('name'),
                        subtitle: [
                          r.str('city'),
                          if (r.strOrNull('region') != null) r.str('region'),
                          if (r.str('kind') == 'PDV' && r.integer('sold') > 0)
                            t.perDay('${r['perDay']}'),
                        ].join(' · '),
                        quantity: r.integer('quantity'),
                        chip: r.str('kind') == 'DEPOT'
                            ? null
                            : DaysLeftChip(
                                quantity: r.integer('quantity'),
                                daysLeft: r.integerOrNull('daysLeft'),
                              ),
                        onTap: r.str('kind') == 'DEPOT'
                            ? () =>
                                  context.push('/depots/${r.str('locationId')}')
                            : () => widget.onOpen(
                                lens.withFacet(Facet.pdv, r.str('locationId')),
                              ),
                      ),
                    more(rows.length),
                  ],
                ),
              ),
          ],
        );
      case 'store':
        final rows = stock.list('rows');
        final shown = _all ? rows : rows.take(8).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              t.stockHere,
              trailing: TextButton(
                onPressed: () => context.push('/stock/${lens.pdvId}'),
                child: Text(t.stockTitle),
              ),
            ),
            Text(
              t.stockPaceHint,
              style: context.text.bodySmall?.copyWith(
                color: context.status.muted,
              ),
            ),
            const Gap(8),
            if (rows.isEmpty)
              AppCard(child: Text(t.stockNowhere))
            else
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  children: [
                    for (final r in shown)
                      _StockRow(
                        leading: AuthImage(
                          r.strOrNull('imageId'),
                          width: 38,
                          height: 38,
                          radius: 10,
                          placeholderIcon: LucideIcons.package,
                        ),
                        title: r.str('name'),
                        subtitle: [
                          r.str('family'),
                          if (r.integer('sold') > 0) t.perDay('${r['perDay']}'),
                        ].where((s) => s.isNotEmpty).join(' · '),
                        quantity: r.integer('quantity'),
                        chip: DaysLeftChip(
                          quantity: r.integer('quantity'),
                          daysLeft: r.integerOrNull('daysLeft'),
                        ),
                        onTap: lens.productId == null
                            ? () => widget.onOpen(
                                lens.withFacet(
                                  Facet.product,
                                  r.str('productId'),
                                ),
                              )
                            : null,
                      ),
                    more(rows.length),
                  ],
                ),
              ),
          ],
        );
      default:
        final out = stock.list('runningOut');
        final dead = stock.obj('dead');
        Widget product(Json p, Widget chip) => _StockRow(
          leading: AuthImage(
            p.strOrNull('imageId'),
            width: 38,
            height: 38,
            radius: 10,
            placeholderIcon: LucideIcons.package,
          ),
          title: p.str('name'),
          subtitle: [
            p.str('family'),
            if (p.integer('sold') > 0) t.perDay('${p['perDay']}'),
          ].where((s) => s.isNotEmpty).join(' · '),
          quantity: p.integer('quantity'),
          chip: chip,
          onTap: () =>
              widget.onOpen(lens.withFacet(Facet.product, p.str('id'))),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(t.stockHealth),
            Text(
              t.stockPaceHint,
              style: context.text.bodySmall?.copyWith(
                color: context.status.muted,
              ),
            ),
            const Gap(8),
            AutoGrid(
              minItemWidth: 400,
              maxColumns: 2,
              children: [
                _Panel(
                  title: t.runsOutSoon,
                  child: out.isEmpty
                      ? Row(
                          children: [
                            Icon(
                              LucideIcons.circleCheck,
                              color: context.status.success,
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(t.stockPaceFine)),
                          ],
                        )
                      : Column(
                          children: [
                            for (final p in out)
                              product(
                                p,
                                DaysLeftChip(
                                  quantity: p.integer('quantity'),
                                  daysLeft: p.integerOrNull('daysLeft'),
                                ),
                              ),
                          ],
                        ),
                ),
                if (dead.integer('count') > 0)
                  _Panel(
                    title: t.notMoving(dead.integer('count')),
                    child: Column(
                      children: [
                        for (final p in dead.list('items'))
                          product(p, StatusChip(t.noRecentSales)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
    }
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.quantity,
    this.chip,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final int quantity;
  final Widget? chip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
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
                Text(t.units(quantity), style: context.text.titleSmall),
                if (chip != null) ...[const SizedBox(height: 4), chip!],
              ],
            ),
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
      ),
    );
  }
}

/// The rewards in money for the scope: owed, waiting for payment, paid in the period.
class _MoneySection extends StatelessWidget {
  const _MoneySection({required this.money});

  final Json money;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = t.localeName;
    final pending = money.obj('pending');
    final paid = money.obj('paid');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.moneyTitle),
        AutoGrid(
          minItemWidth: 200,
          maxColumns: 3,
          children: [
            StatTile(
              icon: LucideIcons.wallet,
              label: t.moneyOwed,
              value: Money.format(money.integer('owedMillimes'), locale),
              hint: t.moneyOwedHint,
            ),
            StatTile(
              icon: LucideIcons.hourglass,
              tone: pending.integer('count') > 0 ? Tone.warning : Tone.neutral,
              label: t.moneyPending,
              value: Money.format(pending.integer('amountMillimes'), locale),
              hint: t.moneyRequests(pending.integer('count')),
              onTap: () => context.push('/payouts'),
            ),
            StatTile(
              icon: LucideIcons.circleCheck,
              tone: Tone.success,
              label: t.moneyPaid,
              value: Money.format(paid.integer('amountMillimes'), locale),
              hint: t.moneyRequests(paid.integer('count')),
            ),
          ],
        ),
      ],
    );
  }
}

/// The sales themselves, newest first: the truth behind every number above.
class _LatestSales extends ConsumerWidget {
  const _LatestSales({required this.lens, required this.empty});

  final Lens lens;
  final bool empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    if (empty) return const SizedBox.shrink();
    // The order of the rankings does not change the sales: one list per question.
    final key = lens.copyWith(sort: Metric.units);
    final sales = ref.watch(latestSalesProvider(key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          t.latestSales,
          trailing: TextButton(
            onPressed: () => context.push(lens.location('/explore/sales')),
            child: Text(t.seeAllSales),
          ),
        ),
        sales.when(
          data: (list) => list.isEmpty
              ? AppCard(child: Text(t.noSalesInPeriod))
              : Column(
                  children: [
                    for (final s in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SaleTile(
                          sale: s,
                          showSeller: true,
                          showDate: true,
                        ),
                      ),
                  ],
                ),
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(latestSalesProvider(key)),
          ),
        ),
      ],
    );
  }
}
