import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/json.dart';
import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/util/money.dart';
import '../../core/widgets/components.dart';
import '../../l10n/app_localizations.dart';
import '../media/media_repository.dart';
import 'lens.dart';

/// The value of [metric] in a row of the analytics (current period).
int metricOf(Metric metric, Json row) => row.integer(switch (metric) {
  Metric.units => 'units',
  Metric.sales => 'sales',
  Metric.reward => 'rewardMillimes',
});

/// The same value in the period before.
int beforeOf(Metric metric, Json row) => row.integer(switch (metric) {
  Metric.units => 'beforeUnits',
  Metric.sales => 'beforeSales',
  Metric.reward => 'beforeRewardMillimes',
});

/// Change in percent; null when there was nothing to compare with.
int? changeOf(int now, int before) =>
    before == 0 ? null : ((now - before) * 100 / before).round();

String metricText(AppLocalizations t, Metric metric, int value) =>
    switch (metric) {
      Metric.units => t.units(value),
      Metric.sales => t.salesCount(value),
      Metric.reward => Money.format(value, t.localeName),
    };

String metricLabel(AppLocalizations t, Metric metric) => switch (metric) {
  Metric.units => t.kpiUnits,
  Metric.sales => t.kpiSales,
  Metric.reward => t.kpiRewards,
};

String weekdayName(int dow, String locale) =>
    // 0 is Sunday; 2024-01-07 was a Sunday.
    DateFormat.E(locale).format(DateTime(2024, 1, 7 + dow));

/// +12 % / −8 %, green or red; nothing when there was nothing to compare with.
class ChangeBadge extends StatelessWidget {
  const ChangeBadge(this.change, {this.compact = false, super.key});

  final int? change;
  final bool compact;

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
          size: compact ? 12 : 14,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          '${up ? '+' : ''}$change %',
          style: (compact ? context.text.labelSmall : context.text.labelMedium)
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// A headline number. The three measures can be tapped to choose what the curve and rankings show.
class KpiTile extends StatelessWidget {
  const KpiTile({
    required this.icon,
    required this.label,
    required this.value,
    this.hint,
    this.change,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  final int? change;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        borderColor: selected ? context.colors.primary : null,
        color: selected ? context.colors.primaryContainer : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(icon, size: 28),
                const SizedBox(width: 8),
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
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: context.text.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    hint ?? '',
                    style: context.text.labelSmall?.copyWith(
                      color: context.status.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ChangeBadge(change, compact: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The curve of a period: bars per hour, day or week. A day or a week can be tapped to open it.
class MetricChart extends StatelessWidget {
  const MetricChart({
    required this.points,
    required this.metric,
    required this.granularity,
    this.onTap,
    super.key,
  });

  final List<Json> points;
  final Metric metric;

  /// `hour`, `day` or `week`.
  final String granularity;
  final void Function(Json point)? onTap;

  String _axis(String key, String locale) => switch (granularity) {
    'hour' => key,
    'week' => DateFormat('d/M', locale).format(Dates.parseDay(key)),
    _ => key.substring(8),
  };

  String _full(String key, AppLocalizations t) => switch (granularity) {
    'hour' => '${key}h',
    'week' => t.weekOf(Dates.short(Dates.parseDay(key), t.localeName)),
    _ => Dates.short(Dates.parseDay(key), t.localeName),
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final values = [for (final p in points) metricOf(metric, p).toDouble()];
    final max = values.fold<double>(0, (a, b) => b > a ? b : a);
    final every = (points.length / 8).ceil().clamp(1, 1000);
    final total = values.fold<double>(0, (a, b) => a + b).round();
    return Semantics(
      label: '${metricLabel(t, metric)}: ${metricText(t, metric, total)}',
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            maxY: max == 0 ? 5 : max * 1.18,
            alignment: BarChartAlignment.spaceBetween,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: max == 0 ? 1 : (max / 3).ceilToDouble(),
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: context.colors.outlineVariant, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 ||
                        i >= points.length ||
                        (points.length - 1 - i) % every != 0) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _axis(points[i].str('key'), t.localeName),
                        style: context.text.labelSmall?.copyWith(
                          color: context.status.muted,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchCallback: (event, response) {
                final spot = response?.spot;
                if (onTap == null ||
                    spot == null ||
                    event is! FlTapUpEvent ||
                    granularity == 'hour') {
                  return;
                }
                onTap!(points[spot.touchedBarGroupIndex]);
              },
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                  '${_full(points[group.x].str('key'), t)}\n${metricText(t, metric, rod.toY.round())}',
                  TextStyle(
                    color: context.colors.onPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < values.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: values[i],
                      width: points.length > 40 ? 5 : 12,
                      color: values[i] == max && max > 0
                          ? context.colors.primary
                          : context.colors.primary.withValues(alpha: 0.4),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small bars for a pattern (hours of the day, days of the week); the busiest one stands out.
class PatternBars extends StatelessWidget {
  const PatternBars({required this.bars, super.key});

  final List<({String label, int value})> bars;

  @override
  Widget build(BuildContext context) {
    final top = bars.fold<int>(1, (m, b) => b.value > m ? b.value : m);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final b in bars)
            Expanded(
              child: Tooltip(
                message: '${b.label} · ${b.value}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 4 + 76 * (b.value / top),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: b.value == top && b.value > 0
                            ? context.colors.primary
                            : context.colors.primary.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      child: Text(
                        b.label,
                        style: context.text.labelSmall?.copyWith(
                          color: context.status.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A ranking: who, where or what makes the numbers. Each row opens a narrower lens.
class RankingCard extends StatefulWidget {
  const RankingCard({
    required this.title,
    required this.icon,
    required this.rows,
    required this.metric,
    required this.total,
    required this.onTap,
    this.images = false,
    this.initial = 5,
    super.key,
  });

  final String title;
  final IconData icon;
  final List<Json> rows;
  final Metric metric;

  /// The lens's total of [metric], for each row's share.
  final int total;
  final void Function(Json row) onTap;
  final bool images;
  final int initial;

  @override
  State<RankingCard> createState() => _RankingCardState();
}

class _RankingCardState extends State<RankingCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final rows = _all ? widget.rows : widget.rows.take(widget.initial).toList();
    final top = widget.rows.fold<int>(
      1,
      (m, r) => metricOf(widget.metric, r) > m ? metricOf(widget.metric, r) : m,
    );
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 18, color: context.colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.title, style: context.text.titleSmall),
              ),
              Text(
                '${widget.rows.length}',
                style: context.text.labelMedium?.copyWith(
                  color: context.status.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < rows.length; i++)
            _RankRow(
              rank: i + 1,
              row: rows[i],
              metric: widget.metric,
              top: top,
              total: widget.total,
              image: widget.images,
              onTap: () => widget.onTap(rows[i]),
            ),
          if (widget.rows.length > widget.initial)
            TextButton.icon(
              onPressed: () => setState(() => _all = !_all),
              icon: Icon(
                _all ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 18,
              ),
              label: Text(_all ? t.seeLess : t.seeMore(widget.rows.length)),
            ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.row,
    required this.metric,
    required this.top,
    required this.total,
    required this.image,
    required this.onTap,
  });

  final int rank;
  final Json row;
  final Metric metric;
  final int top;
  final int total;
  final bool image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final value = metricOf(metric, row);
    final share = total == 0 ? 0 : (value * 100 / total).round();
    final sub = row.strOrNull('sub');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: [
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
            if (image) ...[
              AuthImage(
                row.strOrNull('imageId'),
                width: 40,
                height: 40,
                radius: 10,
                placeholderIcon: LucideIcons.package,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.str('name').isEmpty ? '—' : row.str('name'),
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sub != null && sub.isNotEmpty)
                    Text(
                      sub,
                      style: context.text.bodySmall?.copyWith(
                        color: context.status.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: value / top,
                      minHeight: 5,
                      backgroundColor: context.status.mutedSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  metricText(t, metric, value),
                  style: context.text.titleSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$share %',
                      style: context.text.labelSmall?.copyWith(
                        color: context.status.muted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    ChangeBadge(
                      changeOf(value, beforeOf(metric, row)),
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 2),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: context.status.muted,
            ),
          ],
        ),
      ),
    );
  }
}

/// A sentence the numbers say, in the person's language.
({IconData icon, Tone tone, String text}) insightSentence(
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
    case 'SILENT_STORES':
      return (
        icon: LucideIcons.store,
        tone: Tone.warning,
        text: t.insSilentStores(p.integer('count')),
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
    case 'BEST_HOUR':
      return (
        icon: LucideIcons.clock,
        tone: Tone.info,
        text: t.insBestHour(
          '${p.integer('hour').toString().padLeft(2, '0')}h',
          p.integer('share'),
        ),
      );
    case 'BEST_WEEKDAY':
      return (
        icon: LucideIcons.calendarDays,
        tone: Tone.info,
        text: t.insBestWeekday(
          weekdayName(p.integer('weekday'), locale),
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

class InsightTile extends StatelessWidget {
  const InsightTile({required this.insight, this.onTap, super.key});

  final Json insight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = insightSentence(t, insight.str('key'), insight.obj('params'));
    final c = s.tone.colors(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(s.icon, size: 17, color: c.strong),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              s.text,
              style: context.text.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
          if (onTap != null)
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: context.status.muted,
            ),
        ],
      ),
    );
  }
}

/// Days of stock left, as a coloured pill.
class DaysLeftChip extends StatelessWidget {
  const DaysLeftChip({
    required this.quantity,
    required this.daysLeft,
    super.key,
  });

  final int quantity;
  final int? daysLeft;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (quantity <= 0) return StatusChip(t.outOfStock, tone: Tone.danger);
    if (daysLeft == null) return StatusChip(t.noRecentSales);
    return StatusChip(
      t.daysLeft(daysLeft!),
      tone: daysLeft! <= 3
          ? Tone.danger
          : daysLeft! <= 7
          ? Tone.warning
          : Tone.success,
    );
  }
}

/// The chart button on a store, group, product or team member page: opens its analytics
/// (last 30 days). Only managers see it.
class AnalyticsButton extends ConsumerWidget {
  const AnalyticsButton({required this.facet, required this.id, super.key});

  final Facet facet;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(meProvider).role;
    if (role != Role.admin && role != Role.responsable) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: AppLocalizations.of(context).analyticsTitle,
      icon: const Icon(LucideIcons.chartColumnBig),
      onPressed: () =>
          context.push(Lens.lastDays(30).withFacet(facet, id).location()),
    );
  }
}
