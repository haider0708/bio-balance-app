import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/api/json.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// Units sold per day over the last two weeks.
class TrendChart extends StatelessWidget {
  const TrendChart({required this.days, super.key});

  final List<Json> days;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final values = [for (final d in days) d.integer('units').toDouble()];
    final max = values.fold<double>(0, (a, b) => b > a ? b : a);
    final total = values.fold<double>(0, (a, b) => a + b).round();
    return Semantics(
      label: t.trendSemantics(total),
      child: SizedBox(
        height: 150,
        child: BarChart(
          BarChartData(
            maxY: max == 0 ? 5 : max * 1.2,
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
                        i >= days.length ||
                        i % 3 != (days.length - 1) % 3)
                      return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        days[i].str('day').substring(8),
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
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                  '${days[group.x].str('day').substring(5)}\n${t.units(rod.toY.round())}',
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
                      width: 12,
                      color: i == values.length - 1
                          ? context.colors.primary
                          : context.colors.primary.withValues(alpha: 0.35),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(5),
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
