import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/util/money.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/trend_chart.dart';
import '../media/media_repository.dart';
import 'reports_repository.dart';

typedef InsightsQuery = ({String from, String to, String? regionId});

/// One call that answers "what do these numbers mean": comparison, mix, ranking, stock pace.
final insightsProvider = FutureProvider.autoDispose.family<Json, InsightsQuery>(
  (ref, q) async =>
      await ref
              .watch(apiClientProvider)
              .get(
                '/v1/reports/insights',
                query: {'from': q.from, 'to': q.to, 'regionId': q.regionId},
              )
          as Json,
);

const _mix = [
  Color(0xFF146C43),
  Color(0xFF4FC3F7),
  Color(0xFFFFB300),
  Color(0xFFEF6C57),
  Color(0xFF8E7CC3),
  Color(0xFF90A4AE),
];

/// Wraps a tab: loads the insights, pulls to refresh, and shows the same loading and error states.
class _InsightsTab extends ConsumerWidget {
  const _InsightsTab({required this.range, required this.builder});

  final InsightsQuery range;
  final List<Widget> Function(BuildContext context, Json data) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(insightsProvider(range));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(insightsProvider(range));
        await ref.read(insightsProvider(range).future);
      },
      child: AsyncBody(
        value: data,
        onRetry: () => ref.invalidate(insightsProvider(range)),
        builder: (d) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: builder(context, d),
        ),
      ),
    );
  }
}

/// +12 % / −8 %, green or red; nothing when there was nothing to compare with.
class ChangeBadge extends StatelessWidget {
  const ChangeBadge(this.change, {super.key});

  final int? change;

  @override
  Widget build(BuildContext context) {
    if (change == null) return const SizedBox.shrink();
    final up = change! >= 0;
    final color = up ? context.status.success : context.status.danger;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? LucideIcons.trendingUp : LucideIcons.trendingDown,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          '${up ? '+' : ''}$change %',
          style: context.text.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    this.hint,
    this.change,
    this.icon,
  });

  final String label;
  final String value;
  final String? hint;
  final int? change;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: context.colors.primary),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, style: context.text.headlineSmall),
          ),
          Row(
            children: [
              if (hint != null)
                Expanded(
                  child: Text(
                    hint!,
                    style: context.text.labelSmall?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
                )
              else
                const Spacer(),
              ChangeBadge(change),
            ],
          ),
        ],
      ),
    );
  }
}

String _weekday(int dow, String locale) {
  // 0 is Sunday; 2024-01-07 was a Sunday.
  return DateFormat.E(locale).format(DateTime(2024, 1, 7 + dow));
}

/// A sentence the numbers say, in the person's language.
({IconData icon, Tone tone, String text}) _sentence(
  AppLocalizations t,
  String key,
  Json p,
) {
  final locale = t.localeName;
  switch (key) {
    case 'TOP_FAMILY':
      final change = p['change'] as int?;
      return (
        icon: LucideIcons.layers,
        tone: Tone.success,
        text: [
          t.insTopFamily(p.str('family'), p.integer('share')),
          if (change != null)
            change >= 0 ? t.insUpOn(change) : t.insDownOn(change.abs()),
        ].join(' '),
      );
    case 'STORE_DOWN':
      return (
        icon: LucideIcons.trendingDown,
        tone: Tone.danger,
        text: t.insStoreDown(p.str('store'), p.integer('change').abs()),
      );
    case 'STORE_UP':
      return (
        icon: LucideIcons.trendingUp,
        tone: Tone.success,
        text: t.insStoreUp(p.str('store'), p.integer('change')),
      );
    case 'RUNNING_OUT':
      return (
        icon: LucideIcons.packageMinus,
        tone: Tone.warning,
        text: t.insRunningOut(p.integer('count'), p.integer('days')),
      );
    case 'DEAD_STOCK':
      return (
        icon: LucideIcons.packageX,
        tone: Tone.muted,
        text: t.insDeadStock(p.integer('count')),
      );
    case 'BEST_WEEKDAY':
      return (
        icon: LucideIcons.calendarDays,
        tone: Tone.info,
        text: t.insBestWeekday(
          _weekday(p.integer('weekday'), locale),
          p.integer('share'),
        ),
      );
    case 'TOP_SELLER':
      return (
        icon: LucideIcons.trophy,
        tone: Tone.success,
        text: t.insTopSeller(p.str('name'), p.integer('units')),
      );
    default:
      return (
        icon: LucideIcons.banknote,
        tone: Tone.info,
        text: t.insRewardPerUnit(
          Money.format(p.integer('amountMillimes'), locale),
        ),
      );
  }
}

class InsightsOverview extends ConsumerWidget {
  const InsightsOverview({required this.range, super.key});

  final InsightsQuery range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final locale = t.localeName;
    final trend = ref.watch(
      salesReportProvider((
        from: range.from,
        to: range.to,
        groupBy: 'day',
        regionId: range.regionId,
        pdvId: null,
        sellerId: null,
        productId: null,
        family: null,
      )),
    );
    return _InsightsTab(
      range: range,
      builder: (context, d) {
        final totals = d.obj('totals');
        final families = d.list('families');
        final weekdays = d.list('weekdays');
        final order = [1, 2, 3, 4, 5, 6, 0];
        final topWeekday = weekdays.fold<int>(
          1,
          (m, w) => w.integer('units') > m ? w.integer('units') : m,
        );
        final best = d.objOrNull('bestDay');
        final slow = d.objOrNull('slowDay');
        final totalUnits = totals.integer('units');
        return [
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  icon: LucideIcons.package,
                  label: t.totalUnits,
                  value: '$totalUnits',
                  change: totals['unitsChange'] as int?,
                  hint: t.vsPrevious(totals.integer('previousUnits')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Kpi(
                  icon: LucideIcons.banknote,
                  label: t.reward,
                  value: Money.format(
                    totals.integer('rewardMillimes'),
                    locale,
                    unit: false,
                  ),
                  hint: 'TND',
                  change: totals['rewardChange'] as int?,
                ),
              ),
            ],
          ),
          const Gap(12),
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  icon: LucideIcons.receipt,
                  label: t.salesTitleShort,
                  value: '${totals.integer('sales')}',
                  change: totals['salesChange'] as int?,
                  hint: t.unitsPerSale('${totals['unitsPerSale']}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Kpi(
                  icon: LucideIcons.store,
                  label: t.activeStoresLabel,
                  value: '${totals.integer('activeStores')}',
                  hint: t.sellersCount(totals.integer('activeSellers')),
                ),
              ),
            ],
          ),
          if (d.list('insights').isNotEmpty) ...[
            SectionHeader(t.whatTheNumbersSay),
            for (final i in d.list('insights'))
              Builder(
                builder: (context) {
                  final s = _sentence(t, i.str('key'), i.obj('params'));
                  final c = s.tone.colors(context);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: c.soft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(s.icon, size: 18, color: c.strong),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                s.text,
                                style: context.text.bodyMedium?.copyWith(
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
          SectionHeader(t.dailySales),
          AppCard(
            child: trend.when(
              data: (r) => r.trend.length <= 62
                  ? TrendChart(days: r.trend)
                  : const SizedBox(height: 40),
              loading: () => const SizedBox(
                height: 150,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => const SizedBox(height: 40),
            ),
          ),
          if (best != null && slow != null) ...[
            const Gap(12),
            Row(
              children: [
                Expanded(
                  child: _Kpi(
                    icon: LucideIcons.arrowUp,
                    label: t.bestDay,
                    value: t.units(best.integer('units')),
                    hint: Dates.short(Dates.parseDay(best.str('day')), locale),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Kpi(
                    icon: LucideIcons.arrowDown,
                    label: t.slowestDay,
                    value: t.units(slow.integer('units')),
                    hint: Dates.short(Dates.parseDay(slow.str('day')), locale),
                  ),
                ),
              ],
            ),
          ],
          SectionHeader(t.byWeekday),
          AppCard(
            child: SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final dow in order)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final units = weekdays
                              .firstWhere((w) => w.integer('weekday') == dow)
                              .integer('units');
                          final top = units == topWeekday && units > 0;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '$units',
                                style: context.text.labelSmall?.copyWith(
                                  color: context.status.muted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                height: 6 + 70 * (units / topWeekday),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: top
                                      ? context.colors.primary
                                      : context.colors.primary.withValues(
                                          alpha: 0.28,
                                        ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _weekday(dow, locale),
                                style: context.text.labelSmall,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (families.isNotEmpty) ...[
            SectionHeader(t.salesByFamily),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 16,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < families.length; i++)
                            Expanded(
                              flex: families[i].integer('units'),
                              child: ColoredBox(color: _mix[i % _mix.length]),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Gap(12),
                  for (var i = 0; i < families.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _mix[i % _mix.length],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              families[i].str('name'),
                              style: context.text.bodyMedium,
                            ),
                          ),
                          ChangeBadge(families[i]['change'] as int?),
                          const SizedBox(width: 10),
                          Text(
                            '${totalUnits == 0 ? 0 : (families[i].integer('units') * 100 / totalUnits).round()} %',
                            style: context.text.titleSmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ];
      },
    );
  }
}

class InsightsStores extends StatelessWidget {
  const InsightsStores({required this.range, super.key});

  final InsightsQuery range;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _InsightsTab(
      range: range,
      builder: (context, d) {
        final stores = d.list('stores');
        if (stores.isEmpty) {
          return [
            EmptyState(
              icon: LucideIcons.chartNoAxesColumn,
              title: t.noSalesInPeriod,
            ),
          ];
        }
        final top = stores.first.integer('units');
        return [
          for (var i = 0; i < stores.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${i + 1}',
                            style: context.text.titleSmall?.copyWith(
                              color: i == 0
                                  ? context.colors.primary
                                  : context.status.muted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stores[i].str('name'),
                                style: context.text.titleSmall,
                              ),
                              Text(
                                stores[i].str('city'),
                                style: context.text.bodySmall?.copyWith(
                                  color: context.status.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          t.units(stores[i].integer('units')),
                          style: context.text.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: stores[i].integer('units') / top,
                        minHeight: 6,
                        backgroundColor: context.status.mutedSoft,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          t.shareOfTotal(stores[i].integer('share')),
                          style: context.text.bodySmall?.copyWith(
                            color: context.status.muted,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          Money.format(
                            stores[i].integer('rewardMillimes'),
                            t.localeName,
                          ),
                          style: context.text.bodySmall?.copyWith(
                            color: context.status.muted,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ChangeBadge(stores[i]['change'] as int?),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ];
      },
    );
  }
}

class InsightsProducts extends StatelessWidget {
  const InsightsProducts({required this.range, super.key});

  final InsightsQuery range;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _InsightsTab(
      range: range,
      builder: (context, d) {
        final products = d.list('products');
        if (products.isEmpty) {
          return [
            EmptyState(
              icon: LucideIcons.chartNoAxesColumn,
              title: t.noSalesInPeriod,
            ),
          ];
        }
        final top = products.first.integer('units');
        return [
          for (var i = 0; i < products.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}',
                        style: context.text.titleSmall?.copyWith(
                          color: i == 0
                              ? context.colors.primary
                              : context.status.muted,
                        ),
                      ),
                    ),
                    AuthImage(
                      products[i].strOrNull('imageId'),
                      width: 48,
                      height: 48,
                      radius: 10,
                      placeholderIcon: LucideIcons.package,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            products[i].str('name'),
                            style: context.text.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: products[i].integer('units') / top,
                              minHeight: 5,
                              backgroundColor: context.status.mutedSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          t.units(products[i].integer('units')),
                          style: context.text.titleSmall,
                        ),
                        ChangeBadge(products[i]['change'] as int?),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ];
      },
    );
  }
}

class InsightsTeam extends StatelessWidget {
  const InsightsTeam({required this.range, super.key});

  final InsightsQuery range;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _InsightsTab(
      range: range,
      builder: (context, d) {
        final sellers = d.list('sellers');
        if (sellers.isEmpty) {
          return [
            EmptyState(icon: LucideIcons.trophy, title: t.noSalesInPeriod),
          ];
        }
        final top = sellers.first.integer('units');
        return [
          for (var i = 0; i < sellers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: i == 0
                          ? const Color(0xFFFFE08A)
                          : context.colors.primaryContainer,
                      child: i == 0
                          ? const Icon(
                              LucideIcons.trophy,
                              size: 18,
                              color: Color(0xFF8A5A00),
                            )
                          : Text(
                              '${i + 1}',
                              style: context.text.titleSmall?.copyWith(
                                color: context.colors.primary,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sellers[i].str('name'),
                            style: context.text.titleSmall,
                          ),
                          Text(
                            '${sellers[i].str('store')} · ${t.salesCount(sellers[i].integer('sales'))}',
                            style: context.text.bodySmall?.copyWith(
                              color: context.status.muted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: sellers[i].integer('units') / top,
                              minHeight: 5,
                              backgroundColor: context.status.mutedSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      t.units(sellers[i].integer('units')),
                      style: context.text.titleSmall,
                    ),
                  ],
                ),
              ),
            ),
        ];
      },
    );
  }
}

class InsightsStock extends StatelessWidget {
  const InsightsStock({required this.range, super.key});

  final InsightsQuery range;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _InsightsTab(
      range: range,
      builder: (context, d) {
        final stock = d.obj('stock');
        final out = stock.list('runningOut');
        final dead = stock.obj('dead');
        Widget product(Json p, Widget trailing) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                AuthImage(
                  p.strOrNull('imageId'),
                  width: 48,
                  height: 48,
                  radius: 10,
                  placeholderIcon: LucideIcons.package,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    p.str('name'),
                    style: context.text.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                trailing,
              ],
            ),
          ),
        );
        return [
          Text(
            t.stockPaceHint,
            style: context.text.bodyMedium?.copyWith(
              color: context.status.muted,
            ),
          ),
          SectionHeader(t.runsOutSoon),
          if (out.isEmpty)
            AppCard(
              child: Row(
                children: [
                  Icon(LucideIcons.circleCheck, color: context.status.success),
                  const SizedBox(width: 12),
                  Expanded(child: Text(t.stockPaceFine)),
                ],
              ),
            ),
          for (final p in out)
            product(
              p,
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusChip(
                    p.integer('days') == 0
                        ? t.outOfStock
                        : t.daysLeft(p.integer('days')),
                    tone: p.integer('days') <= 2 ? Tone.danger : Tone.warning,
                  ),
                  Text(
                    t.stockAtPace(p.integer('stock'), '${p['perDay']}'),
                    style: context.text.bodySmall?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
                ],
              ),
            ),
          if (dead.integer('count') > 0) ...[
            SectionHeader(t.notMoving(dead.integer('count'))),
            for (final p in dead.list('items'))
              product(
                p,
                Text(
                  t.units(p.integer('stock')),
                  style: context.text.titleSmall,
                ),
              ),
          ],
        ];
      },
    );
  }
}
